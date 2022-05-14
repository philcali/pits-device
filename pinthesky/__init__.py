import logging

class NullHandler(logging.Handler):
    def emit(self, record: logging.LogRecord) -> None:
        pass

logging.getLogger('pinthesky').addHandler(NullHandler())