from collections import namedtuple
import json
import logging
import os

from pinthesky.handler import Handler


logger = logging.getLogger(__name__)


ConfigUpdate = namedtuple('ConfigUpdate', ['name', 'body'])


class ShadowConfigHandler:
    '''
    Handler for updating parts of the shadow document for camera
    configuration. Handlers are expected to return a ConfigUpdate
    or None if there is no update.
    '''
    def update_document(self) -> ConfigUpdate:
        pass


class ShadowConfig(Handler):
    def __init__(
            self,
            events,
            configure_input,
            configure_output) -> None:
        self.__events = events
        self.__configure_input = configure_input
        self.__configure_output = configure_output
        self.__handlers = []

    def add_handler(self, handler: ShadowConfigHandler):
        self.__handlers.append(handler)

    def is_empty(self):
        if not os.path.exists(self.__configure_output):
            return True
        with open(self.__configure_output, 'r') as f:
            content = f.read()
            if len(content) == 0:
                return True
            body = json.loads(content)
            return len(body) == 0

    def __should_update(self, ub):
        return ub == 'empty' and self.is_empty() or ub == 'always'

    def reset_from_document(self):
        if self.is_empty():
            logger.info("Skipping reset, as configuration is empty.")
        else:
            with open(self.__configure_output, 'r') as f:
                content = json.loads(f.read())
                self.__events.fire_event('file_change', {
                    'file_name': self.__configure_output,
                    'content': content
                })

    def update_document(self, parser):
        if self.__should_update(parser.shadow_update):
            resulting_document = {}
            for handler in self.__handlers:
                rval = handler.update_document()
                if rval is not None:
                    resulting_document[rval.name] = rval.body
            if len(resulting_document) == 0:
                logger.info('There was no update, Skipping.')
                return False
            logger.info(f'Updating config document with {resulting_document}')
            with open(self.__configure_input, 'w') as f:
                f.write(json.dumps(resulting_document))
            logger.info(f'Successfully updated {self.__configure_input}')
            return True
        return False

    def on_file_change(self, event):
        if event['file_name'] == self.__configure_output:
            if os.path.getsize(self.__configure_input) > 0:
                logger.info(f'Truncating {self.__configure_input}')
                # TODO: probably want to lock on it
                with open(self.__configure_input, 'w') as f:
                    f.write("")
        elif event['file_name'] == self.__configure_input:
            logger.info(
                f'Config update received on {event["timestamp"]}',
                extra={
                    'emf': {
                        'CloudWatchMetrics': [
                            {
                                'Dimensions': ['ThingName', 'Operation'],
                                'Metrics': [
                                    {
                                        'Name': 'Shadow',
                                        'Unit': 'Count'
                                    }
                                ]
                            }
                        ],
                        'Shadow': 1,
                        'Operation': 'ConfigUpdate',
                    }
                })
