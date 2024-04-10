import boto3
import json
from botocore.exceptions import ClientError
from functools import partial
from pinthesky.connection import ConnectionThread, ConnectionHandler, ConnectionManager, ProcessBuffer
from pinthesky.events import EventThread
from unittest.mock import patch, MagicMock
from test_handler import TestHandler


def test_connection_thread():
    manager = MagicMock()
    process = MagicMock()
    stdout = MagicMock()
    events = EventThread()
    handler = TestHandler()
    buffer = ProcessBuffer(process=process)
    connection_thread = ConnectionThread(
        events=events,
        manager=manager,
        buffer=buffer,
        event_data={
            'connection': {
                'id': '$connectionId',
            }
        }
    )

    def poll():
        return True
    
    process.poll = poll
    process.stdout = stdout

    def read1(size):
        return None

    manager.post_to_connection = MagicMock()
    process.stdout.read1 = read1
    process.stdout.close = poll

    events.on(handler)
    events.start()
    connection_thread.start()
    events.event_queue.join()
    assert handler.calls['record_end'] == 1
    manager.post_to_connection.assert_not_called()


def test_connection_thread_manager_failed():
    manager = MagicMock()
    process = MagicMock()
    stdout = MagicMock()
    events = EventThread()
    handler = TestHandler()
    buffer = ProcessBuffer(process=process)
    connection_thread = ConnectionThread(
        events=events,
        manager=manager,
        buffer=buffer,
        event_data={
            'connection': {
                'id': '$connectionId',
            }
        }
    )

    def poll():
        return None
    
    process.poll = poll
    process.stdout = stdout

    def read1(size):
        return "data"

    def post_to_connection(connection_id, data):
        return False
    
    manager.post_to_connection = post_to_connection
    process.stdout.read1 = read1
    process.stdout.close = poll

    events.on(handler)
    events.start()
    connection_thread.start()
    events.event_queue.join()
    assert handler.calls['record_end'] == 1


def test_connection_manager_no_url():
    session = MagicMock()
    manager = ConnectionManager(
        session=session,
        endpoint_url=None,
    )

    management = MagicMock()
    with patch.object(boto3.Session, 'client', return_value=management) as mock_client:
        manager.post_to_connection("$connectionId", {})

    mock_client.assert_not_called()


def test_connection_manager_no_credentials():
    session = MagicMock()
    manager = ConnectionManager(
        session=session,
        endpoint_url="http://example.com",
    )

    def login():
        return None

    session.login = login

    management = MagicMock()
    with patch.object(boto3.Session, 'client', return_value=management) as mock_client:
        manager.post_to_connection("$connectionId", {})

    mock_client.assert_not_called()


def test_connection_manager_happy_path():
    session = MagicMock()
    manager = ConnectionManager(
        session=session,
        endpoint_url="http://example.com",
    )

    def login():
        return {
            'accessKeyId': 'accessKeyId',
            'secretAccessKey': 'secretAccessKey',
            'sessionToken': 'sessionToken',
        }

    session.login = login

    def post_to_connection(ConnectionId, Data):
        assert ConnectionId == "$connectionId"
        assert Data == {
            'test': 'farts'
        }

    management = MagicMock()
    management.post_to_connection = post_to_connection
    with patch.object(boto3.Session, 'client', return_value=management) as mock_client:
        assert manager.post_to_connection("$connectionId", {
            'test': 'farts'
        })

    mock_client.assert_called_once()


def test_connection_manager_post_failed():
    session = MagicMock()
    manager = ConnectionManager(
        session=session,
        endpoint_url="http://example.com",
    )

    def login():
        return {
            'accessKeyId': 'accessKeyId',
            'secretAccessKey': 'secretAccessKey',
            'sessionToken': 'sessionToken',
        }

    session.login = login

    def post_to_connection(ConnectionId, Data):
        raise ClientError({}, 'PostToConnections')

    management = MagicMock()
    management.post_to_connection = post_to_connection
    with patch.object(boto3.Session, 'client', return_value=management) as mock_client:
        assert not manager.post_to_connection("$connectionId", {
            'test': 'farts'
        })

    mock_client.assert_called_once()


def test_connection_handler():
    manager = MagicMock()
    handler = ConnectionHandler(manager=manager)

    events = [
        'record',
        'configuration',
        'health',
        'upload',
    ]

    for event in events:
        method_name = f'on_{event}_end'
        method = getattr(handler, method_name)

        def post_to_connection(connection_id, data):
            assert connection_id == "$connectionId" if event != 'record' else "$managerId"
            assert json.loads(data.decode('utf-8')) == {
                'name': event,
                'connection': {
                    'id': '$connectionId',
                    'manager_id': '$managerId',
                }
            }

        manager.post_to_connection = post_to_connection

        partial(method)({
            'name': event,
            'connection': {
                'id': '$connectionId',
                'manager_id': '$managerId',
            }
        })
