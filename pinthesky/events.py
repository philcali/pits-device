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
    'file_change',
    'capture_image',
    'capture_image_end',
    'capture_video',
    'recording_change',
    'health',
    'health_end'
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
            self.on_event(
                event_name=event_name,
                handler=partial(method),
                handler_name=handler.__class__.__name__)

    def on_event(self, event_name, handler, handler_name):
        if event_name not in self.handlers:
            self.handlers[event_name] = []
        self.handlers[event_name].append({
            'handler': handler,
            'name': handler_name
        })

    def fire_event(self, event_name, context={}):
        event_data = {
            'name': event_name,
            'timestamp': floor(time.time())
        }
        if event_name in self.handlers:
            logger.debug(f'Pushing {event_data["name"]} to event queue')
            self.event_queue.put(dict(context, **event_data))

    def run(self):
        logger.info('Starting the event handler thread')
        while self.running:
            message = self.event_queue.get()
            unprocessed_messages = self.event_queue.qsize()
            if message['name'] in self.handlers:
                for handler in self.handlers[message['name']]:
                    emf = {
                        'CloudWatchMetrics': [
                            {
                                'Dimensions': [
                                    ['ThingName', 'Operation'],
                                    ['ThingName', 'Event']
                                ],
                                'Metrics': [
                                    {
                                        'Name': 'EventProcessed',
                                        'Unit': 'Count',
                                    },
                                    {
                                        'Name': 'EventBacklog',
                                        'Unit': 'Count',
                                    },
                                    {
                                        'Name': 'Time',
                                        'Unit': 'Seconds',
                                    }
                                ]
                            }
                        ],
                        'Operation': 'EventHandle',
                        'Handler': handler["name"],
                        'Event': message['name'],
                        'EventProcessed': 1,
                        'EventBacklog': unprocessed_messages,
                    }
                    try:
                        handler['handler'](message)
                        emf['Time'] = floor(time.time()) - message['timestamp']
                        logger.info(f'Handler {handler["name"]} processed {message["name"]}',
                                    extra={'emf': emf})
                    except Exception as e:
                        emf['EventProcessed'] = 0
                        emf['Time'] = floor(time.time()) - message['timestamp']
                        logger.error(
                            f'Failed to handle {message["name"]}: {e}',
                            exc_info=e,
                            extra={'emf': emf})
            self.event_queue.task_done()

    def stop(self):
        self.event_queue.join()
        self.running = False
