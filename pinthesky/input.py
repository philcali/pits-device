import json
import logging
import os
import threading

from pinthesky.handler import Handler
from inotify_simple import INotify, flags

logger = logging.getLogger(__name__)


class INotifyThread(threading.Thread):
    def __init__(self, events, inotify=None):
        super().__init__(daemon=True)
        self.running = True
        self.inotify = inotify or INotify()
        self.events = events
        self.handlers = {}


    def touch_empty(self, file_name):
        if not os.path.exists(file_name):
            with open(file_name, 'w') as f:
                f.write('{}')


    def watch_file(self, file_name):
        watch_flags = flags.CREATE | flags.MODIFY
        logger.info(f'Watching input for {file_name}')
        return self.inotify.add_watch(file_name, watch_flags)

    
    def notify_change(self, file_name):
        if file_name not in self.handlers:
            self.touch_empty()
            self.handlers[file_name] = self.watch_file(file_name)


    def fire_event(self, event):
        file_name = None
        for name, wd in self.handlers.items():
            if event.wd == wd:
                file_name = name
        if file_name is not None:
            with open(file_name, 'r') as f:
                js = json.loads(f.read())
                self.events.fire_event('file_change', {
                    'file_name': file_name,
                    'content': js
                })


    def run(self):
        while self.running:
            for event in self.inotify.read():
                if flags.from_mask(event.mask) is flags.CREATE | flags.MODIFY:
                    self.fire_event(event)


    def stop(self):
        self.running = False
        for watched in self.watched:
            self.inotify.rm_watch(watched)


class InputHandler(Handler):
    def __init__(self, events):
        self.events = events
        pass


    def on_file_change(self, event):
        if "name" in event['content'] and "context" in event['content']:
            self.events.fire_event(event['content']['name'], event['content']['context'])