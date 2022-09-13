import json
import logging
from threading import Lock

from pinthesky.handler import Handler

logger = logging.getLogger(__name__)


class Output(Handler):
    """
    A handler that writes event content to a specified location.
    Watchers on the other end are expected to handle the inotify events.
    """
    def __init__(self, output_file, thing_name=None):
        self.output_file = output_file
        self.thing_name = thing_name
        self.write_lock = Lock()

    def __on_event(self, event):
        logger.debug(f'Flushing {event["name"]} to {self.output_file}')
        # Augment the thing name in outbound messages
        if self.thing_name is not None:
            event["thing_name"] = self.thing_name
        with self.write_lock:
            with open(self.output_file, 'w') as f:
                f.write(json.dumps(event))

    def on_upload_end(self, event):
        self.__on_event(event)

    def on_health_end(self, event):
        self.__on_event(event)

    def reset(self):
        with open(self.output_file, 'w') as f:
            f.write("")
