from datetime import timedelta
import json
import os
from pinthesky import VERSION
from pinthesky.config import ConfigUpdate
from pinthesky.events import EventThread
from pinthesky.health import DeviceHealth
from pinthesky.output import Output
from tests.test_handler import TestHandler


def test_device_health():
    handler = TestHandler()
    events = EventThread()
    events.on(handler)
    events.start()
    device_health = DeviceHealth(events=events)
    try:
        assert device_health.emit_health(force=True)
        while not events.event_queue.empty():
            pass
        assert handler.calls["health_end"] == 1
    finally:
        events.stop()


def test_device_health_flush():
    output_file = "test_output.json"
    output = Output(output_file=output_file)
    events = EventThread()
    device_health = DeviceHealth(
        events=events,
        flush_delta=timedelta(microseconds=1))
    events.on(output)
    events.on(device_health)
    events.start()
    try:
        events.fire_event('recording_change', {
            'recording': True
        })
        events.fire_event('flush_end')
        while events.event_queue.unfinished_tasks > 0:
            pass
        assert device_health.emit_health()
        while events.event_queue.unfinished_tasks > 0:
            pass
        with output.write_lock:
            with open(output_file, 'r') as f:
                content = json.loads(f.read())
        assert content['version'] == VERSION
        assert content['recording_status']
        assert content['motion_captured'] == 1
        validate_existence = [
            'start_time',
            'up_time',
            'cpu_count',
            'cpu_used',
            'disk_total',
            'disk_free',
            'disk_used',
            'ip_addr',
            'mem_total',
            'mem_avail',
            'mem_free'
        ]
        for field in validate_existence:
            assert field in content
    finally:
        events.stop()
        os.remove(output_file)


def test_update():
    events = EventThread()
    device_health = DeviceHealth(events=events)
    events.on(device_health)
    events.start()
    try:
        assert device_health.flush_delta.seconds == 3600
        events.fire_event('file_change', {
            'content': {
                'current': {
                    'state': {
                        'desired': {
                            'health': {
                                'interval': '60'
                            }
                        }
                    }
                }
            }
        })
        while events.event_queue.unfinished_tasks > 0:
            pass
        assert device_health.flush_delta.seconds == 60
    finally:
        events.stop()


def test_update_document():
    events = EventThread()
    device_health = DeviceHealth(events=events)
    assert device_health.update_document() == ConfigUpdate('health', {
        'interval': 3600
    })
