import boto3
import json
import logging
from botocore.exceptions import ClientError
from pinthesky.handler import Handler
from threading import Thread


FRAME_SIZE = 32768

logger = logging.getLogger(__name__)


class ConnectionBuffer():
    def close(self):
        pass

    def read1(self, size):
        pass

    def poll(self):
        pass


class ProcessBuffer(ConnectionBuffer):
    def __init__(self, process) -> None:
        self.process = process

    def read1(self, size):
        return self.process.stdout.read1(size)

    def close(self):
        self.process.stdout.close()

    def poll(self):
        return self.process.poll()


class ConnectionThread(Thread):
    def __init__(self, buffer, manager, event_data, events):
        super().__init__()
        self.buffer = buffer
        self.manager = manager
        self.event_data = event_data
        self.events = events

    def run(self):
        try:
            while True:
                buf = self.buffer.read1(FRAME_SIZE)
                if buf:
                    if not self.manager.post_to_connection(self.event_data['connection']['id'], buf):
                        break
                elif self.buffer.poll() is not None:
                    break
        finally:
            self.buffer.close()
            self.events.fire_event('record_end', {
                **self.event_data,
                'session': {
                    'stop': True
                }
            })


class ConnectionManager:
    def __init__(self, session, endpoint_url=None) -> None:
        self.session = session
        self.endpoint_url = endpoint_url

    def post_to_connection(self, connection_id, data):
        if self.endpoint_url is None:
            return
        credentials = self.session.login()
        if credentials is None:
            return
        session = boto3.Session(
            aws_access_key_id=credentials['accessKeyId'],
            aws_secret_access_key=credentials['secretAccessKey'],
            aws_session_token=credentials['sessionToken'],
        )
        management = session.client(
            'apigatewaymanagementapi',
            endpoint_url=self.endpoint_url
        )
        try:
            management.post_to_connection(
                ConnectionId=connection_id,
                Data=data
            )
        except ClientError as e:
            logger.error(f'Failed to post to {connection_id}: {e}', exc_info=e)
            return False
        return True


class ConnectionHandler(Handler):
    def __init__(self, manager) -> None:
        self.manager = manager

    def _post_back(self, event):
        if 'id' in event.get('connection', {}):
            self.manager.post_to_connection(
                connection_id=event['connection']['id'],
                data=json.dumps(event).encode('utf-8')
            )

    def on_record_end(self, event):
        if 'manager_id' in event.get('connection', {}):
            self.manager.post_to_connection(
                connection_id=event['connection']['manager_id'],
                data=json.dumps(event).encode('utf-8')
            )

    def on_configuration_end(self, event):
        self._post_back(event)

    def on_upload_end(self, event):
        self._post_back(event)

    def on_health_end(self, event):
        self._post_back(event)
