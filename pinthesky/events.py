from math import floor
import logging
import threading
import time
import queue

from functools import partial
from pinthesky.handler import Handler

logger = logging.getLogger(__name__)
event_names = [
    'motion_start',
    'flush_end',
    'combine_end',
    'upload_end',
    'file_change'
]


class EventThread(threading.Thread):
    """
    This thread wraps a queue to flush events sequentially. A Handler could be
    added, or more general anonymous functions.
    """
    def __init__(self):
        super().__init__(daemon=True)
        self.event_queue = queue.Queue()
        self.running = True
        self.handlers = {}

    def on(self, handler: Handler):
        for event_name in event_names:
            method_name = f'on_{event_name}'
            method = getattr(handler, method_name)
            self.on_event(event_name=event_name, handler=partial(method))

    def on_event(self, event_name, handler):
        if event_name not in self.handlers:
            self.handlers[event_name] = []
        self.handlers[event_name].append(handler)

    def fire_event(self, event_name, context={}):
        event_data = {
            'name': event_name,
            'timestamp': floor(time.time())
        }
        if event_name in self.handlers:
            self.event_queue.put(dict(context, **event_data))

    def run(self):
        logger.info('Starting the event handler thread')
        while self.running:
            message = self.event_queue.get()
            if message['name'] in self.handlers:
                for handler in self.handlers[message['name']]:
                    handler(message)
            self.event_queue.task_done()

    def stop(self):
        self.running = False
