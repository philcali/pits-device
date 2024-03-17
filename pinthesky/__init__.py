import logging

VERSION = "0.8.0"


def set_stream_logger(name="pinthesky", level=logging.DEBUG, fmt_string=None):
    if fmt_string is None:
        fmt_string = "%(asctime)s %(name)s [%(levelname)s] %(message)s"

    logger = logging.getLogger(name)
    logger.setLevel(level)
    handler = logging.StreamHandler()
    handler.setLevel(level)
    formatter = logging.Formatter(fmt_string)
    handler.setFormatter(formatter)
    logger.addHandler(handler)


logging.getLogger('pinthesky').addHandler(logging.NullHandler())
