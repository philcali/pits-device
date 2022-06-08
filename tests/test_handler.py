from pinthesky.handler import Handler
from pinthesky.events import EventThread, event_names


class TestHandler(Handler):
    def __on_event(self, event_name, event):
        if not hasattr(self, 'calls'):
            self.calls = {}
        if event_name not in self.calls:
            self.calls[event_name] = 0
        self.calls[event_name] += 1

    def on_upload_end(self, event):
        self.__on_event('upload_end', event)

    def on_combine_end(self, event):
        self.__on_event('combine_end', event)

    def on_flush_end(self, event):
        self.__on_event('flush_end', event)

    def on_motion_start(self, event):
        self.__on_event('motion_start', event)

    def on_file_change(self, event):
        self.__on_event('file_change', event)


def test_handler():
    handler = TestHandler()
    events = EventThread()
    events.on(handler)
    events.start()
    for event_name in event_names:
        events.fire_event(event_name)
    while not events.event_queue.empty():
        pass
    for event_name in event_names:
        assert handler.calls[event_name] == 1
    events.stop()