from datetime import datetime
from pinthesky.handler import Handler
import logging
import time
import threading


logger = logging.getLogger(__name__)


class CameraThread(threading.Thread, Handler):
    """
    A thread that manages a picamera.PiCamera instance.
    """
    def __init__(
            self, events, sensitivity=10, resolution=(640, 480),
            framerate=20, rotation=270, buffer=15, recording_window=None,
            camera_class=None,
            stream_class=None,
            motion_detection_class=None):
        super().__init__(daemon=True)
        self.__camera_class = camera_class
        self.__stream_class = stream_class
        self.__motion_detection_class = motion_detection_class
        self.running = True
        self.flushing_stream = False
        self.flushing_ts = None
        self.events = events
        self.buffer = buffer
        self.sensitivity = sensitivity
        self.camera = self.__new_camera()
        self.camera.resolution = resolution
        self.camera.framerate = framerate
        self.camera.rotation = rotation
        self.historical_stream = self.__new_stream_buffer()
        self.recording_window = recording_window
        self.configuration_lock = threading.Lock()
        self.__set_recording_window()

    def __set_recording_window(self):
        if self.recording_window is not None:
            self.start_window, self.end_window = map(
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
        return self.__stream_class(self.camera, seconds=self.buffer)

    def __new_camera(self):
        if self.__camera_class is None:
            from picamera import PiCamera
            self.__camera_class = PiCamera
        return self.__camera_class()

    def on_motion_start(self, event):
        if not self.flushing_stream:
            logger.debug(
                f'Starting a flush on motion event from {event["timestamp"]}')
            self.flushing_ts = event['timestamp']
            self.flushing_stream = True

    def on_file_change(self, event):
        if "current" in event["content"]:
            cam_obj = event["content"]["current"]["state"]["desired"]["camera"]
            logger.info(f'Update camera fields in {cam_obj}')
            # Hold potentially dangerous mutations if the camera is flushing
            with self.configuration_lock:
                previsouly_recording = self.pause()
                # Update wrapper fields
                for field in ["buffer", "sensitivity", "recording_window"]:
                    if field in cam_obj:
                        setattr(self, field, cam_obj[field])
                        if field == "recording_window":
                            self.__set_recording_window()
                # Update picamera fields
                for field in ["rotation", "resolution", "framerate"]:
                    if field in cam_obj:
                        val = cam_obj[field]
                        if field == "resolution":
                            val = tuple(map(int, val.split("x")))
                        setattr(self.camera, field, val)
                if previsouly_recording:
                    self.resume()

    def __flush_video(self):
        # Want to flush when it is safe to flush
        with self.configuration_lock:
            self.camera.split_recording(f'{self.flushing_ts}.after.h264')
            self.historical_stream.copy_to(f'{self.flushing_ts}.before.h264')
            self.historical_stream.clear()
            time.sleep(self.buffer)
            self.camera.split_recording(self.historical_stream)
            self.flushing_stream = False
            self.events.fire_event('flush_end', {
                'start_time': self.flushing_ts
            })

    def run(self):
        logger.info('Starting camera thread')
        self.resume()
        while self.running:
            if not self.flushing_stream and self.recording_window:
                now = datetime.now()
                if now.hour < self.start_window or now.hour > self.end_window:
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
            return True
        return False

    def resume(self):
        if not self.camera.recording:
            self.historical_stream = self.__stream_class(
                self.camera,
                seconds=self.buffer)
            self.camera.start_recording(
                self.historical_stream,
                format='h264',
                motion_output=self.__new_motion_detect())
            logger.info("Camera is now recording")
            return True
        return False

    def stop(self):
        self.running = False
        self.camera.stop_recording()
        self.camera.close()
