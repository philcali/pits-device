from unittest import mock
from pinthesky.config import ConfigUpdate
from pinthesky.events import EventThread
from pinthesky.camera import CameraThread


def test_configuration_change():
    camera_class = mock.MagicMock
    stream_class = mock.MagicMock
    motion_class = mock.MagicMock
    events = EventThread()
    camera = CameraThread(
        events=events,
        camera_class=camera_class,
        stream_class=stream_class,
        motion_detection_class=motion_class,
        sensitivity=10,
        resolution=(640, 480),
        framerate=20,
        rotation=270,
        buffer=15,
        recording_window="0-23")
    events.on(camera)
    events.start()
    events.fire_event('file_change', {
        'content': {
            'current': {
                'state': {
                    'desired': {
                        'camera': {
                            'buffer': '20',
                            'sensitivity': '20',
                            'recording_window': '12-20',
                            'rotation': '180',
                            'resolution': '320x240',
                            'framerate': '30',
                            'encoding_bitrate': '5000000',
                            'encoding_profile': 'main',
                            'encoding_level': '2.1'
                        }
                    }
                }
            }
        }
    })
    while events.event_queue.unfinished_tasks > 0:
        pass
    assert camera.recording_window == '12-20'
    assert camera.buffer == 20
    assert camera.sensitivity == 20
    assert camera.encoding_bitrate == 5000000
    assert camera.encoding_level == '2.1'
    assert camera.encoding_profile == 'main'
    assert camera.camera.framerate == 30
    assert camera.camera.rotation == 180
    assert camera.camera.resolution == (320, 240)
    assert camera.camera.stop_recording.is_called
    assert camera.camera.start_recording.is_called


def test_configuration_update():
    camera_class = mock.MagicMock
    stream_class = mock.MagicMock
    motion_class = mock.MagicMock
    events = EventThread()
    camera = CameraThread(
        events=events,
        camera_class=camera_class,
        stream_class=stream_class,
        motion_detection_class=motion_class,
        sensitivity=10,
        resolution=(640, 480),
        framerate=20,
        rotation=270,
        buffer=15,
        recording_window="0-23")
    assert camera.update_document() == ConfigUpdate('camera', {
        'buffer': 15,
        'sensitivity': 10,
        'rotation': 270,
        'resolution': '640x480',
        'framerate': 20,
        'recording_window': '0-23',
        'encoding_level': camera.encoding_level,
        'encoding_profile': camera.encoding_profile,
        'encoding_bitrate': camera.encoding_bitrate
    })
