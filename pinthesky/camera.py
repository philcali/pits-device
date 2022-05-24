from datetime import datetime
import logging
import picamera
import picamera.array
import numpy as np
import time
import threading

from pinthesky.handler import Handler

logger = logging.getLogger(__name__)

class MotionDetector(picamera.array.PiMotionAnalysis):
    '''
    Adapted motion detection class from the PiCamera documentation.
    Performs vactor calculation on a sensitivity threshold.
    '''
    def __init__(self, camera, events, sensitivity=10, size=None):
        super(MotionDetector, self).__init__(camera, size)
        self.events = events
        self.sensitivity = sensitivity


    def analyse(self, a):
        a = np.sqrt(
            np.square(a['x'].astype(np.float)) +
            np.square(a['y'].astype(np.float))
            ).clip(0, 255).astype(np.uint8)
        if (a > 60).sum() > self.sensitivity:
            self.events.fire_event('motion_start')


class CameraThread(threading.Thread, Handler):
    def __init__(self, events, sensitivity=10, resolution=(640, 480), framerate=20, rotation=270, buffer=15, recording_window=None):
        super().__init__(daemon=True)
        self.running = True
        self.flushing_stream = False
        self.flushing_timestamp = None
        self.events = events
        self.buffer = buffer
        self.sensitivity = sensitivity
        self.camera = picamera.PiCamera()
        self.camera.resolution = resolution
        self.camera.framerate = framerate
        self.camera.rotation = rotation
        self.historical_stream = picamera.PiCameraCircularIO(self.camera, seconds=self.buffer)
        self.recording_window = recording_window
        self.configuration_lock = threading.Lock()
        self.__set_recording_window()


    def __set_recording_window(self):
        if self.recording_window is not None:
            self.start_window, self.end_window = map(int, self.recording_window.split('-'))


    def on_motion_start(self, event):
        if not self.flushing_stream:
            logger.debug(f'Starting a flush on motion event from {event["timestamp"]}')
            self.flushing_timestamp = event['timestamp']
            self.flushing_stream = True


    def on_file_change(self, event):
        if "current" in event["content"]:
            cam_obj = event["content"]["current"]["state"]["desired"]["camera"]
            # Hold potentially dangerous mutations if the camera is flushing
            with self.configuration_lock:
                self.pause()
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
                self.resume()


    def __flush_video(self):
        # Want to flush when it is safe to flush
        with self.configuration_lock:
            self.camera.split_recording(f'{self.flushing_timestamp}.after.h264')
            self.historical_stream.copy_to(f'{self.flushing_timestamp}.before.h264')
            self.historical_stream.clear()
            time.sleep(self.buffer)
            self.camera.split_recording(self.historical_stream)
            self.flushing_stream = False
            self.events.fire_event('flush_end', {
                'start_time': self.flushing_timestamp
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
            self.historical_stream.clear()
            logger.info("Camera recording is now paused")


    def resume(self):
        if not self.camera.recording:
            self.historical_stream = picamera.PiCameraCircularIO(self.camera, seconds=self.buffer)
            self.camera.start_recording(
                self.historical_stream,
                format='h264',
                motion_output=MotionDetector(self.camera, self.events, sensitivity=self.sensitivity))
            logger.info("Camera is now recording")


    def stop(self):
        self.running = False
        self.camera.stop_recording()
        self.camera.close()
