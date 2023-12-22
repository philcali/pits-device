import json
import os
import time
from pinthesky.input import INotifyThread, InputHandler
from pinthesky.events import EventThread
from test_handler import TestHandler


def test_input_reader():
    test_file = "test_file.json"
    events = EventThread()
    notify = INotifyThread(events)
    handler = InputHandler(events)
    client_handler = TestHandler()
    with open(test_file, 'w') as f:
        f.write("{}")
    notify.notify_change(test_file)
    events.on(handler)
    events.on(client_handler)
    events.start()
    notify.start()
    try:
        for i in range(0, 5):
            with open(test_file, 'w') as f:
                f.write(json.dumps({
                    "name": "motion_start",
                    "context": {
                    }
                }))
            # Let the queues catch it
            time.sleep(0.01)
            # Item is flushed, verify it
            with open(test_file, "r") as f:
                assert f.read() == ""
        assert client_handler.calls['motion_start'] == 5
        assert client_handler.calls['file_change'] == 5
    finally:
        notify.stop()
        events.stop()
        os.remove(test_file)
