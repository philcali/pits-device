import logging
import time
import json
import boto3
from datetime import datetime
from unittest.mock import patch, MagicMock
from pinthesky.events import EventThread
from pinthesky.session import Session
from pinthesky.cloudwatch import CloudWatchEventFilter, CloudWatchEventFormat, CloudWatchLoggingStream, ThreadedStream
from pinthesky.config import ConfigUpdate


class CaptureHandler(logging.Handler):
    def __init__(self, level) -> None:
        super().__init__(level)
        self.records = []

    def emit(self, record: logging.LogRecord) -> None:
        self.records.append(record)


class CaptureStream():
    def __init__(self, sleep=True) -> None:
        self.messages = []
        self.sleep = sleep

    def write(self, message, ingest=None):
        self.messages.append(message)
        if self.sleep:
            time.sleep(0.01)


def test_cloudwatch_event_filter():
    filterer = logging.Filterer()
    filterer.addFilter(CloudWatchEventFilter())

    handler = CaptureHandler(level=logging.INFO)
    handler.addFilter(filter=filterer)

    emf = {
        'CloudWatchMetrics': [
            {
                'Dimensions': ['ThingName'],
                'Metrics': [
                    {
                        'Unit': 'Count',
                        'Name': 'Log'
                    }
                ]
            }
        ],
        'Log': 1
    }

    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)
    logger.addHandler(logging.NullHandler())
    logger.info("This is a message")
    logger.info("This is an event message", extra={
        'emf': emf
    })

    assert len(handler.records) == 1
    assert getattr(handler.records[0], 'emf') == emf


def test_threaded_stream():
    stream = CaptureStream()
    stream_thread = ThreadedStream(stream=stream)
    stream_thread.start()

    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)
    logger.addHandler(logging.StreamHandler(stream=stream_thread))

    for i in range(0, 10):
        logger.info('Found message %d', i)

    assert len(stream.messages) < 10
    # allow the messages to flush
    stream_thread.stop()
    assert len(stream.messages) == 10
    assert stream.messages == [
        'Found message 0\n',
        'Found message 1\n',
        'Found message 2\n',
        'Found message 3\n',
        'Found message 4\n',
        'Found message 5\n',
        'Found message 6\n',
        'Found message 7\n',
        'Found message 8\n',
        'Found message 9\n',
    ]


def test_cloudwatch_event_format():
    session = Session(
        cacert_path="capath",
        cert_path="cert_path",
        key_path="key_path",
        role_alias="role_alias",
        thing_name="thing_name",
        credentials_endpoint="credentials_endpoint")
    stream = CaptureStream(sleep=False)
    format = CloudWatchEventFormat(session=session)

    events = EventThread()
    events.on(format)
    events.start()
    events.fire_event('file_change', {
        'content': {
            'current': {
                'state': {
                    'desired': {
                        'cloudwatch_metrics': {
                            'namespace': 'Pits/ThingName',
                        }
                    }
                }
            }
        }
    })
    events.event_queue.join()

    assert format.update_document() == ConfigUpdate('cloudwatch_metrics', {
        'namespace': 'Pits/ThingName',
    })

    handler = logging.StreamHandler(stream=stream)
    handler.setFormatter(format)

    logger = logging.getLogger(__name__)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    logger.info('Info message', extra={
        'emf': {
            'CloudWatchMetrics': [
                {
                    'Namespace': 'Override',
                    'Dimensions': [['ThingName', 'FartName']],
                    'Metrics': [
                        {
                            'Name': 'Farts',
                            'Unit': 'Count'
                        }
                    ],
                }
            ],
            'FartName': 'Smoky',
            'Farts': 1
        }
    })
    logger.error('Failure message', exc_info=BaseException(), extra={
        'emf': {
        }
    })
    assert len(stream.messages) == 2
    info_event = json.loads(stream.messages[0])
    assert info_event['ThingName'] == 'thing_name'
    assert info_event['Name'] == 'test_cloudwatch'
    assert info_event['Message'] == 'Info message'
    assert info_event['Failure'] == 0
    error_event = json.loads(stream.messages[1])
    assert error_event['ThingName'] == 'thing_name'
    assert error_event['Name'] == 'test_cloudwatch'
    assert error_event['Message'] == 'Failure message'
    assert error_event['Failure'] == 1


def test_cloudwatch_logging_stream():
    events = EventThread()
    session = Session(
        cacert_path="capath",
        cert_path="cert_path",
        key_path="key_path",
        role_alias="role_alias",
        thing_name="thing_name",
        credentials_endpoint="credentials_endpoint")
    now = datetime.now()
    next_year = datetime(year=now.year + 1, month=now.month, day=1)
    session.credentials = {
        'accessKeyId': 'abc',
        'secretAccessKey': 'efg',
        'sessionToken': '123',
        'expiration': next_year.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    logs = MagicMock()
    logs.describe_log_streams = MagicMock()
    logs.create_log_stream = MagicMock()
    logs.put_log_events = MagicMock()

    logging_stream = CloudWatchLoggingStream(session=session)

    handler = logging.StreamHandler(stream=logging_stream)
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)

    # Will ignore
    logger.info("Info Message")

    events.on(logging_stream)
    events.start()
    events.fire_event('file_change', {
        'content': {
            'current': {
                'state': {
                    'desired': {
                        'cloudwatch_logging': {
                            'enabled': True,
                            'log_group_name': 'Pits/Device',
                            'delineate_stream': True,
                        }
                    }
                }
            }
        }
    })
    events.event_queue.join()
    # Confirm config update
    assert logging_stream.update_document() == ConfigUpdate('cloudwatch_logging', {
        'enabled': 'True',
        'delineate_stream': 'True',
        'log_group_name': 'Pits/Device',
    })

    with patch.object(boto3.Session, 'client', return_value=logs) as mock_method:
        logger.info('CW Info')
        logs.describe_log_streams.assert_called_once()
        logs.create_log_stream.assert_called_once()
        logs.put_log_events.assert_called_once()

    mock_method.assert_called_once()
