import json

from pinthesky.handler import Handler


class Output(Handler):
    def __init__(self, output_file):
        self.output_file = output_file

    
    def on_event(self, event):
        with open(self.output_file, 'w') as f:
            f.write(json.dumps(event))


    def on_motion_start(self, event):
        self.on_event(event)


    def on_combine_end(self, event):
        self.on_event(event)


    def on_upload_end(self, event):
        self.on_event(event)
