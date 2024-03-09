from datetime import datetime
from pinthesky.config import ConfigUpdate, ShadowConfigHandler
from pinthesky.handler import Handler
from pinthesky.health import DeviceHealth
import logging
import time
import threading


logger = logging.getLogger(__name__)


class CameraThread(threading.Thread, Handler, ShadowConfigHandler):
    """
    A thread that manages a picamera.PiCamera instance.
    """
    def __init__(
            self, events, sensitivity=10, resolution=(640, 480),
            framerate=20, rotation=270, buffer=15, recording_window=None,
            encoding_bitrate=17000000,
            encoding_profile='high',
            encoding_level="4",
            camera_class=None,
            stream_class=None,
            motion_detection_class=None,
            capture_dir=None,
            device_health=None,
            buffer_size=None):
        super().__init__(daemon=True)
        self.__camera_class = camera_class
        self.__stream_class = stream_class
        self.__motion_detection_class = motion_detection_class
        self.running = True
        self.flushing_stream = False
        self.flushing_ts = None
        self.flushing_buffer = None
        self.flushing_trigger = None
        self.buffer_size = buffer_size
        self.events = events
        self.buffer = buffer
        self.sensitivity = sensitivity
        self.encoding_bitrate = encoding_bitrate
        self.encoding_profile = encoding_profile
        self.encoding_level = encoding_level
        self.camera = self.__new_camera()
        self.camera.resolution = resolution
        self.camera.framerate = framerate
        self.camera.rotation = rotation
        self.historical_stream = self.__new_stream_buffer()
        self.recording_window = recording_window
        self.capture_dir = capture_dir
        self.device_health = device_health
        if self.device_health is None:
            self.device_health = DeviceHealth(events=events)
        self.configuration_lock = threading.Lock()
        self.__set_recording_window()

    def __set_recording_window(self):
        if self.recording_window is not None:
            self.start_hour, self.end_hour = map(
                int, self.recording_window.split('-'))

    def __new_motion_detect(self):
        if self.__motion_detection_class is None:
            from pinthesky.motion_detect import MotionDetector
            self.__motion_detection_class = MotionDetector
        return self.__motion_detection_class(
            self.camera, self.events, self.sensitivity)

    def __new_stream_buffer(self):
        if self.__stream_class is None:
            from picamera import PiCameraCircularIO
            self.__stream_class = PiCameraCircularIO
        kwargs = {'bitrate': self.encoding_bitrate}
        if self.buffer_size is not None:
            kwargs['size'] = self.buffer_size
        else:
            kwargs['seconds'] = self.buffer // 2
        return self.__stream_class(self.camera, **kwargs)

    def __new_camera(self):
        if self.__camera_class is None:
            from picamera import PiCamera
            self.__camera_class = PiCamera
        return self.__camera_class()

    def on_capture_image(self, event):
        result = f'{self.capture_dir}/img-{event["timestamp"]}.jpg'
        if 'file_name' in event:
            result = f'{self.capture_dir}/{event["file_name"]}'
        self.camera.capture(result, use_video_port=True)
        logger.debug(f'Capture to {result}')
        self.events.fire_event('capture_image_end', {
            'image_file': result,
            'start_time': event['timestamp']
        })

    def __flush_start(self, trigger, event):
        if not self.flushing_stream:
            logger.info(
                f'Starting a flush on {trigger} video from {event["timestamp"]}')
            self.flushing_ts = event['timestamp']
            self.flushing_buffer = self.buffer
            if 'duration' in event:
                self.flushing_buffer = event['duration']
            self.flushing_stream = True
            self.flushing_trigger = trigger

    def on_motion_start(self, event):
        self.__flush_start('motion', event)

    def on_capture_video(self, event):
        # Make sure to lock on other configuration changes before mutating camera state
        with self.configuration_lock:
            self.resume()
            self.__flush_start('manual', event)

    def update_document(self) -> ConfigUpdate:
        return ConfigUpdate('camera', {
            'buffer': self.buffer,
            'buffer_size': self.buffer_size,
            'sensitivity': self.sensitivity,
            'rotation': self.camera.rotation,
            'resolution': 'x'.join(map(str, self.camera.resolution)),
            'framerate': self.camera.framerate.numerator,
            'recording_window': self.recording_window,
            'encoding_level': self.encoding_level,
            'encoding_profile': self.encoding_profile,
            'encoding_bitrate': self.encoding_bitrate
        })

    def on_file_change(self, event):
        self_types = {
            "buffer": int,
            "buffer_size": int,
            "sensitivity": int,
            "encoding_bitrate": int,
            "rotation": int,
            "framerate": int
        }

        def identity(x):
            return x

        def set_fields_on(cam_obj, on_obj, fields):
            for field in fields:
                if field in cam_obj:
                    value = cam_obj[field]
                    value = self_types.get(field, identity)(value)
                    if field == "resolution":
                        value = tuple(map(int, value.split("x")))
                    setattr(on_obj, field, value)
                    if field == "recording_window":
                        self.__set_recording_window()

        if "current" in event["content"]:
            cam_obj = event["content"]["current"]["state"]["desired"]["camera"]
            logger.info(f'Update camera fields in {cam_obj}')
            # Hold potentially dangerous mutations if the camera is flushing
            with self.configuration_lock:
                previsouly_recording = self.pause()
                # Update wrapper fields
                set_fields_on(on_obj=self, cam_obj=cam_obj, fields=[
                    "buffer",
                    "buffer_size",
                    "sensitivity",
                    "recording_window",
                    "encoding_bitrate",
                    "encoding_profile",
                    "encoding_level"
                ])
                # Update picamera fields
                set_fields_on(on_obj=self.camera, cam_obj=cam_obj, fields=[
                    "rotation", "resolution", "framerate"
                ])
                if previsouly_recording:
                    self.resume()

    def __flush_video(self):
        # Want to flush when it is safe to flush
        with self.configuration_lock:
            self.camera.split_recording(f'{self.flushing_ts}.after.h264')
            self.historical_stream.copy_to(f'{self.flushing_ts}.before.h264')
            self.historical_stream.clear()
            logger.debug("Flushed buffered contents")
            time.sleep(self.flushing_buffer)
            self.camera.split_recording(self.historical_stream)
            self.events.fire_event('flush_end', {
                'start_time': self.flushing_ts,
                'trigger': self.flushing_trigger
            })
            self.flushing_stream = False

    def run(self):
        logger.info('Starting camera thread')
        self.resume()
        while self.running:
            self.device_health.emit_health(force=False)
            # Configuration lock will prevent a race on "resume" from update
            with self.configuration_lock:
                if not self.flushing_stream and self.recording_window:
                    now = datetime.now()
                    if now.hour < self.start_hour or now.hour > self.end_hour:
                        self.pause()
                        time.sleep(1)
                        continue
                    else:
                        self.resume()
            self.camera.wait_recording(1)
            if self.flushing_stream:
                self.__flush_video()

    def pause(self):
        if self.camera.recording:
            self.camera.stop_recording()
            logger.info("Camera recording is now paused")
            self.events.fire_event('recording_change', {
                'recording': False
            })
            return True
        return False

    def resume(self):
        if not self.camera.recording:
            self.historical_stream = self.__new_stream_buffer()
            self.camera.start_recording(
                self.historical_stream,
                format='h264',
                bitrate=self.encoding_bitrate,
                profile=self.encoding_profile,
                level=self.encoding_level,
                motion_output=self.__new_motion_detect())
            logger.info("Camera is now recording")
            self.events.fire_event('recording_change', {
                'recording': True
            })
            return True
        return False

    def stop(self):
        self.running = False
        self.camera.stop_recording()
        self.camera.close()
