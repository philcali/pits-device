import json
import logging
import os
import threading

from pinthesky.handler import Handler
from inotify_simple import INotify, flags

logger = logging.getLogger(__name__)


class INotifyThread(threading.Thread):
    """
    Wrapper class for an INotify watcher. The thread polls events externally
    configured, and pumps changes back into the EventThread. Subscribers are
    notified via the `file_change` event.
    """
    def __init__(self, events, inotify=None):
        super().__init__(daemon=True)
        self.running = True
        self.inotify = inotify or INotify()
        self.events = events
        self.handlers = {}

    def __touch_empty(self, file_name):
        if not os.path.exists(file_name):
            with open(file_name, 'w') as f:
                f.write('{}')

    def __watch_file(self, file_name):
        watch_flags = flags.CREATE | flags.MODIFY
        logger.info(f'Watching input for {file_name}')
        return self.inotify.add_watch(file_name, watch_flags)

    def __fire_event(self, event):
        file_name = None
        for name, wd in self.handlers.items():
            if event.wd == wd:
                file_name = name
        if file_name is not None:
            with open(file_name, 'r') as f:
                content = f.read()
                if content == "":
                    logger.debug(f'The {file_name} was zeroed out. Skipping.')
                    return
                js = json.loads(content)
                self.events.fire_event('file_change', {
                    'file_name': file_name,
                    'content': js
                })
            with open(file_name, 'w') as f:
                f.write("")
            logger.info(f'Zeroing out {file_name} for further use')

    def notify_change(self, file_name):
        if file_name not in self.handlers:
            self.__touch_empty(file_name)
            self.handlers[file_name] = self.__watch_file(file_name)

    def run(self):
        while self.running:
            for event in self.inotify.read():
                mask = flags.from_mask(event.mask)
                if flags.MODIFY in mask or flags.CREATE in mask:
                    self.__fire_event(event)

    def stop(self):
        self.running = False
        for watched in self.watched:
            self.inotify.rm_watch(watched)


class InputHandler(Handler):
    """
    An INotify handler that watches to files who content translate into events.
    """
    def __init__(self, events):
        self.events = events
        pass

    def on_file_change(self, event):
        if "name" in event['content'] and "context" in event['content']:
            content = event['content']
            self.events.fire_event(content['name'], content['context'])
