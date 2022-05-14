import logging
import picamera
import picamera.array
import numpy as np
import time
import threading

from pinthesky.handler import Handler

logger = logging.getLogger(__name__)

class MotionDetector(picamera.array.PiMotionAnalysis):
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
    def __init__(self, events, sensitivity=10, resolution=(640, 480), framerate=20, rotation=270, buffer=15):
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

    
    def on_motion_start(self, event):
        if not self.flushing_stream:
            logger.debug(f'Starting a flush on motion event from {event["timestamp"]}')
            self.flushing_timestamp = event['timestamp']
            self.flushing_stream = True


    def flush_video(self):
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
        self.camera.start_recording(
            self.historical_stream,
            format='h264',
            motion_output=MotionDetector(self.camera, self.events, sensitivity=self.sensitivity))
        while self.running:
            self.camera.wait_recording(1)
            if self.flushing_stream:
                self.flush_video()


    def stop(self):
        self.running = False
        self.camera.stop_recording()
        self.camera.close()
