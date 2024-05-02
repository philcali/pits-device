import boto3
import json
import logging
from base64 import b64encode
from botocore.exceptions import ClientError
from pinthesky.config import ConfigUpdate, ShadowConfigHandler
from pinthesky.handler import Handler
from threading import Thread


FRAME_SIZE = 32768

logger = logging.getLogger(__name__)


class ProtocolData():
    def __init__(self, manager, event_data) -> None:
        self.manager = manager
        self.event_data = event_data

    def protocol(self):
        pass

    def send(self):
        return self.manager.post_to_connection(
            connection_id=self.event_data['connection']['id'],
            data=self.protocol(),
            binary=True,
        )


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
        logger.info('Starting connection background thread')
        try:
            while True:
                buf = self.buffer.read1(FRAME_SIZE)
                if buf:
                    if not self.manager.post_to_connection(
                        connection_id=self.event_data['connection']['id'],
                        data=buf,
                        binary=True
                    ):
                        break
                elif self.buffer.poll() is not None:
                    break
        finally:
            logger.info('Recording on camera has ended')
            self.buffer.close()
            self.events.fire_event('record_end', {
                **self.event_data,
                'session': {
                    'stop': True
                }
            })


class ConnectionManager(ShadowConfigHandler, Handler):
    def __init__(self, session, enabled=False, endpoint_url=None, region_name=None) -> None:
        self.session = session
        self.endpoint_url = endpoint_url
        self.enabled = enabled
        self.region_name = region_name

    def update_document(self) -> ConfigUpdate:
        return ConfigUpdate("dataplane", {
            'enabled': self.enabled,
            'endpoint_url': self.endpoint_url,
            'region_name': self.region_name,
        })

    def on_file_change(self, event):
        if "current" in event["content"]:
            desired = event["content"]["current"]["state"]["desired"]
            dataplane = desired.get("dataplane", {})
            self.enabled = dataplane.get("enabled", self.enabled)
            self.endpoint_url = dataplane.get("endpoint_url", self.endpoint_url)
            self.region_name = dataplane.get("region_name", self.region_name)

    def post_to_connection(self, connection_id, data, endpoint_override=None, binary=False):
        if not self.enabled:
            return False
        endpoint_url = endpoint_override if endpoint_override is not None else self.endpoint_url
        if endpoint_url is None:
            return False
        credentials = self.session.login()
        if credentials is None:
            return False
        session = boto3.Session(
            aws_access_key_id=credentials['accessKeyId'],
            aws_secret_access_key=credentials['secretAccessKey'],
            aws_session_token=credentials['sessionToken'],
        )
        management = session.client(
            'apigatewaymanagementapi',
            endpoint_url=endpoint_url,
            region_name=self.region_name,
        )
        try:
            management.post_to_connection(
                ConnectionId=connection_id,
                Data=data if not binary else b64encode(data),
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
                data=json.dumps({'invoke': {**event}}).encode('utf-8'),
                endpoint_override=event['connection'].get('management_endpoint'),
            )

    def on_record_end(self, event):
        connection = event.get('connection', {})
        if connection.get('manager_id', None) is not None:
            self.manager.post_to_connection(
                connection_id=event['connection']['manager_id'],
                data=json.dumps({'invoke': {**event}}).encode('utf-8'),
                endpoint_override=event['connection'].get('management_endpoint'),
            )

    def on_configuration_end(self, event):
        self._post_back(event)

    def on_upload_end(self, event):
        self._post_back(event)

    def on_health_end(self, event):
        self._post_back(event)
