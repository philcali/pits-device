import boto3
import logging
import threading
import queue
import json
import datetime
from math import floor
from pinthesky import VERSION
from pinthesky.handler import Handler
from pinthesky.config import ConfigUpdate, ShadowConfigHandler


class CloudWatchManager(Handler, ShadowConfigHandler):
    """
    This manager object controls the adaptation of pinthesky logging by
    plugging directly into the shadow update process. When changes are
    detected, it'll readapt CloudWatch logging as necessary. This includes
    the background thread and event type filter, as well as dynamic enable
    and disable.
    """
    def __init__(
            self,
            session=None,
            log_group_name=None,
            log_level=logging.INFO,
            enabled=False,
            delineate_stream=True,
            threaded=False,
            namespace='Pits/Device',
            event_type='logs'):
        self.session = session
        self.log_group_name = log_group_name
        self.log_level = log_level
        self.enabled = enabled
        self.delineate_stream = delineate_stream
        self.namespace = namespace
        self.threaded = threaded
        self.event_type = event_type
        self.event_handler = None
        self.log_handler = None
        self.log_thread = None
        self.refresh_lock = threading.Lock()

    def adapt_logging(self):
        with self.refresh_lock:
            root = logging.getLogger('pinthesky')
            try:
                root.setLevel(self.log_level)
            except ValueError or TypeError:
                self.log_level = logging.INFO
                root.setLevel(self.log_level)
            # Prepare the ingest stream, stop any running background execution
            if self.log_thread is not None:
                self.log_thread.stop()
                self.log_thread = None
            log_stream = CloudWatchLoggingStream(
                delineate_stream=self.delineate_stream,
                enabled=self.enabled,
                log_group_name=self.log_group_name,
                session=self.session)
            # Create handler that writes logs to CW
            if self.log_handler is not None:
                root.removeHandler(self.log_handler)
                self.log_handler = None
            self.log_handler = logging.StreamHandler(stream=log_stream)
            self.log_handler.setFormatter(
                logging.Formatter(
                    "%(asctime)s %(name)s [%(levelname)s] %(message)s"))
            # Create handler that writes EMF to CW
            format = CloudWatchEventFormat(
                session=self.session,
                namespace=self.namespace)
            if self.event_handler is not None:
                root.removeHandler(self.event_handler)
                self.event_handler = None
            self.event_handler = logging.StreamHandler(stream=log_stream)
            self.event_handler.addFilter(CloudWatchEventFilter())
            self.event_handler.setFormatter(format)
            if self.enabled and self.threaded:
                # Replace stream to be backed by thread
                self.log_thread = ThreadedStream(stream=log_stream)
                self.log_handler.setStream(self.log_thread)
                self.event_handler.setStream(self.log_thread)
                self.log_thread.start()
            # Enable Logs, EMF, or both
            if self.enabled and self.event_type in ['logs', 'all']:
                root.addHandler(self.log_handler)
            if self.enabled and self.event_type in ['emf', 'all']:
                root.addHandler(self.event_handler)

    def update_document(self) -> ConfigUpdate:
        return ConfigUpdate('cloudwatch', {
            'threaded': self.threaded,
            'enabled': self.enabled,
            'delineate_stream': self.delineate_stream,
            'log_group_name': self.log_group_name,
            'metric_namespace': self.namespace,
            'log_level': logging.getLevelName(self.log_level),
            'event_type': self.event_type,
        })

    def on_file_change(self, event):
        if "current" in event["content"]:
            desired = event["content"]["current"]["state"]["desired"]
            cloudwatch = desired.get("cloudwatch", {})
            self.enabled = cloudwatch.get("enabled", self.enabled)
            self.threaded = cloudwatch.get("threaded", self.threaded)
            self.delineate_stream = cloudwatch.get("delineate_stream", self.delineate_stream)
            self.log_group_name = cloudwatch.get("log_group_name", self.log_group_name)
            self.namespace = cloudwatch.get("metric_namespace", self.namespace)
            self.event_type = cloudwatch.get("event_type", self.event_type)
            self.log_level = cloudwatch.get("log_level", self.log_level)
            self.adapt_logging()

    def stop(self):
        if self.log_thread is not None:
            self.log_thread.stop()


class CloudWatchLoggingStream():
    """
    This is a stream-like object to flush messages into a CloudWatch LogGroup.
    The stream itself is compatible with a logging.StreamHandler, which allows
    consumers to set it directly. The stream is dynamically configurable
    through a Thing's shadow update document, allowing customers to enable or
    disable the remote logging feature and target LogGroup.

    handler = logging.StreamHandler(stream=CloudWatchLoggingStream(...))
    logging.getLogger(__name__).addHandler(handler)
    """
    def __init__(
            self,
            session=None,
            log_group_name=None,
            enabled=False,
            delineate_stream=True):
        self.session = session
        self.log_group_name = log_group_name
        self.log_stream_name = None
        self.enabled = enabled
        self.delineate_stream = delineate_stream

    def _log_stream_name(self, now, cloudwatch):
        month = f'0{now.month}' if now.month < 10 else now.month
        day = f'0{now.day}' if now.day < 10 else now.day
        desired_stream = f'{now.year}/{month}/{day}'
        if self.delineate_stream and self.session.thing_name is not None:
            desired_stream += f'@{self.session.thing_name}'
        if self.log_stream_name != desired_stream:
            resp = cloudwatch.describe_log_streams(
                logGroupName=self.log_group_name,
                logStreamNamePrefix=desired_stream)
            for log_stream in resp['logStreams']:
                if log_stream['logStreamName'] == desired_stream:
                    self.log_stream_name = desired_stream
                    break
            if not self.log_stream_name:
                cloudwatch.create_log_stream(
                    logGroupName=self.log_group_name,
                    logStreamName=desired_stream)
                self.log_stream_name = desired_stream
        return self.log_stream_name

    def write(self, message, ingest=None):
        credentials = self.session.login()
        if not self.enabled or not credentials or not self.log_group_name:
            return
        now = ingest if ingest is not None else datetime.datetime.now()
        session = boto3.Session(
            credentials['accessKeyId'],
            credentials['secretAccessKey'],
            credentials['sessionToken'])
        cloudwatch = session.client('logs')
        log_stream_name = self._log_stream_name(now, cloudwatch)
        cloudwatch.put_log_events(
            logGroupName=self.log_group_name,
            logStreamName=log_stream_name,
            logEvents=[
                {
                    'message': message.rstrip('\n'),
                    'timestamp': floor(now.timestamp()) * 1000
                }
            ]
        )


class CloudWatchEventFilter():
    """
    A logging.Filterer filter that is intended to be used in conjunction with
    a CloudWatchEventFormat for a logging.StreamHandler. This allows the
    application to write using the EMF for specific logs tied to metrics.

    logging.info(f'Something happened', extra={
        'emf': {
            'CloudWatchMetrics': [{
                'Namespace': 'PitsDevice', # Optional,
                'Dimensions: [ [ 'Operation' ] ],
                'Metrics': [
                    {
                        'Name': 'Size',
                        'Unit': 'Bytes',
                    }
                ],
            }],
            'Operation': 'Upload',
            'File': 'motion.<timestamp>.h264',
            'Size': '<file_size>'
        },
    })
    """
    def filter(self, record: logging.LogRecord) -> bool:
        return 'emf' in record.__dict__


class CloudWatchEventFormat():
    """
    This log format will convert log messages into applicable AWS CloudWatch
    EMF style. At a minimum, we log if this is an error, but input may
    include anything. To force custom EMF, use CloudWatchEventFilter on a
    logger or handler.
    """
    def __init__(self, session=None, namespace='Pits/Device') -> None:
        self.session = session
        self.namespace = namespace

    def format(self, record: logging.LogRecord):
        existing_emf = getattr(record, 'emf', {})
        # At a high level, we're interested in daemon failures. A logger
        # may post other useful metrics, but we honestly don't care.
        emf = {
            '_aws': {
                'Timestamp': int(record.created) * 1000,
                'CloudWatchMetrics': [
                    {
                        'Namespace': self.namespace,
                        'Dimensions': [['ThingName']],
                        'Metrics': [
                            {
                                'Name': 'Failure',
                                'Unit': 'Count',
                            }
                        ]
                    }
                ],
            },
            'ThingName': self.session.thing_name,
            'Name': record.name,
            'Message': record.getMessage(),
            'Version': VERSION,
            'Failure': 1 if record.levelno >= logging.ERROR else 0,
        }
        if 'CloudWatchMetrics' in existing_emf:
            for cwm in existing_emf['CloudWatchMetrics']:
                if 'Dimensions' not in cwm or 'Metrics' not in cwm:
                    continue
                emf['_aws']['CloudWatchMetrics'].append({
                    **cwm,
                    'Namespace': self.namespace if 'Namespace' not in cwm else cwm['Namespace']
                })
            del existing_emf['CloudWatchMetrics']
        emf.update(existing_emf)
        return json.dumps(emf)


class ThreadedStream(threading.Thread):
    """
    An optional queue backed logging.StreamHandler stream to prevent
    foreground interactions to block other threads from logging
    activities.

    stream_thread = ThreadStream(stream=CloudWatchLoggingStream())
    stream_thread.run()
    handler = logging.StreamHandler(stream=stream_thread)
    logging.getLogger(__name__).addHandler(handler)
    """
    def __init__(self, stream):
        super().__init__(daemon=True)
        self.stream = stream
        self.queue = queue.Queue()
        self.running = False

    def write(self, message):
        self.queue.put_nowait({
            'message': message,
            'timestamp': datetime.datetime.now(),
        })

    def run(self) -> None:
        self.running = True
        while self.running:
            log = self.queue.get()
            try:
                self.stream.write(log['message'], log['timestamp'])
            finally:
                self.queue.task_done()

    def stop(self):
        self.queue.join()
        self.running = False
