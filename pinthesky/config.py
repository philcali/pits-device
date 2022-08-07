from collections import namedtuple
import json
import logging
import os


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


class ShadowConfig:
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

    def __is_empty(self):
        if not os.path.exists(self.__configure_output):
            return True
        with open(self.__configure_output, 'r') as f:
            body = json.loads(f.read())
            return len(body) == 0

    def __should_update(self, ub):
        return ub == 'empty' and self.__is_empty() or ub == 'always'

    def reset_from_document(self):
        if self.__is_empty():
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
            payload = {
                'current': {
                    'state': {
                        'desired': resulting_document
                    }
                }
            }
            logger.info(f'Updating config document with {payload}')
            with open(self.__configure_input, 'w') as f:
                f.write(json.dumps(payload))
            logger.info(f'Successfully updated {self.__configure_input}')
            return True
        return False
