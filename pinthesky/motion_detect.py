import picamera.array
import numpy as np


class MotionDetector(picamera.array.PiMotionAnalysis):
    """
    Adapted motion detection class from the PiCamera documentation.
    Performs vactor calculation on a sensitivity threshold.
    """
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
