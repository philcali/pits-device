import io
import os
from subprocess import Popen, PIPE


class VideoConversion():
    def __init__(self, camera) -> None:
        self.camera = camera
        self.process = Popen([
            'ffmpeg',
            '-f', 'rawvideo',
            '-pix_fmt', 'yuv420p',
            '-s', '%dx%d' % camera.resolution,
            '-r', str(float(camera.framerate)),
            '-i', '-',
            '-f', 'mpeg1video',
            '-b', '800k',
            '-r', str(float(camera.framerate)),
            '-'],
            stdin=PIPE, stdout=PIPE, stderr=io.open(os.devnull, 'wb'),
            shell=False, close_fds=True)

    def write(self, b):
        self.process.stdin.write(b)

    def flush(self):
        self.process.stdin.close()
        self.process.wait()
