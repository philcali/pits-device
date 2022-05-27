import json

from pinthesky.handler import Handler


class Output(Handler):
    """
    A handler that writes event content to a specified location.
    Watchers on the other end are expected to handle the inotify events.
    """
    def __init__(self, output_file):
        self.output_file = output_file

    def __on_event(self, event):
        with open(self.output_file, 'w') as f:
            f.write(json.dumps(event))

    def on_motion_start(self, event):
        self.__on_event(event)

    def on_combine_end(self, event):
        self.__on_event(event)

    def on_upload_end(self, event):
        self.__on_event(event)
