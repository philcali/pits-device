import io
import os
from subprocess import Popen, PIPE
from pinthesky.connection import ProtocolData
from struct import Struct


JSMPEG_MAGIC = b'jsmp'
JSMPEG_HEADER = Struct('>4sHH')


class JSMPEGHeader(ProtocolData):
    def __init__(self, manager, event_data, camera) -> None:
        super().__init__(manager, event_data)
        self.camera = camera

    def protocol(self):
        (width, height) = self.camera.resolution
        return JSMPEG_HEADER.pack(JSMPEG_MAGIC, width, height)


class VideoConversion():
    def __init__(self, camera) -> None:
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
