import json
import logging
import os
import threading

from inotify_simple import INotify, flags

logger = logging.getLogger(__name__)


class InputThread(threading.Thread):
    def __init__(self, events, input_file, inotify=None):
        super().__init__(daemon=True)
        self.input_file = input_file
        self.running = True
        self.inotify = inotify or INotify()
        self.events = events
        if not os.path.exists(input_file):
            with open(self.input_file, 'w') as f:
                f.write('{}')


    def fire_event(self):
        with open(self.input_file, 'r') as f:
            js = json.loads(f.read())
            self.events.fire_event(js['name'], js['context'])

    
    def run(self):
        logger.info(f'Watching input for {self.input_file}')
        watch_flags = flags.CREATE | flags.MODIFY
        self.watched = self.inotify.add_watch(self.input_file, watch_flags)
        while self.running:
            for event in self.inotify.read():
                if flags.from_mask(event.mask) is flags.CREATE | flags.MODIFY:
                    self.fire_event()                    

    
    def stop(self):
        self.running = False
        self.inotify.rm_watch(self.watched)
