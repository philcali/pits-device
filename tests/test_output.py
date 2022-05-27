import os
import time
from pinthesky.output import Output
from pinthesky.events import EventThread, event_names
from pinthesky.input import INotifyThread
from tests.test_handler import TestHandler

def test_output():
    events = EventThread()
    test_output = 'test_output.json'
    with open(test_output, 'w') as f:
        f.write("")
    client = TestHandler()
    output = Output(output_file=test_output)
    notify = INotifyThread(events)
    notify.notify_change(test_output)
    events.on(output)
    events.on(client)
    events.start()
    notify.start()
    for event_name in event_names:
        events.fire_event(event_name=event_name, context={
            "file_name": test_output
        })
        time.sleep(0.02)
    os.remove(test_output)
    assert client.calls['file_change'] == 4