from pinthesky.session import Session, fields
from pinthesky.events import EventThread
from datetime import datetime
from requests import exceptions


ENDPOINT = 'https://example.com/role-aliases/role_alias/credentials'


def test_session(requests_mock):
    requests_mock.get(ENDPOINT, json={
        "credentials": {
            "accessKeyId": "abc",
            "secretAccessKey": "efg",
            "sessionToken": "123",
            "expiration": datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ")
        }
    })
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint="https://example.com")
    credentials = session.login()
    assert credentials['accessKeyId'] == "abc"
    assert credentials['secretAccessKey'] == "efg"
    assert credentials['sessionToken'] == "123"
    assert credentials == session.login()


def test_session_invalid_payload(requests_mock):
    requests_mock.get(ENDPOINT, json={
        "message": "Not what I expected, but I can deal."
    })
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint="https://example.com")
    credentials = session.login()
    assert credentials is None


def test_session_empty_endpoint():
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint=None)
    credentials = session.login()
    assert credentials is None


def test_update():
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint="https://example.com")
    events = EventThread()
    events.on(session)
    events.start()
    events.fire_event('file_change', {
        'content': {
            'current': {
                'state': {
                    'desired': {
                        'cloud_connection': {
                            'cert_path': 'new_cert_path',
                            'key_path': 'new_key_path',
                            'cacert_path': 'new_cacert_path',
                            'thing_name': 'new_thing_name',
                            'role_alias': 'new_role_alias',
                            'credentials_endpoint': 'localhost'
                        }
                    }
                }
            }
        }
    })
    while events.event_queue.unfinished_tasks > 0:
        pass
    for field in fields:
        value = f'new_{field}'
        if field == 'credentials_endpoint':
            value = 'https://localhost'
        assert getattr(session, field) == value


def test_timeout(requests_mock):
    requests_mock.get(ENDPOINT, exc=exceptions.ConnectTimeout)
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint="https://example.com")
    credentials = session.login()
    assert credentials is None


def test_general_error(requests_mock):
    requests_mock.get(ENDPOINT, exc=exceptions.RequestException)
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint="https://example.com")
    credentials = session.login()
    assert credentials is None


def test_bad_error_code(requests_mock):
    requests_mock.get(ENDPOINT, status_code=401)
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint="https://example.com")
    credentials = session.login()
    assert credentials is None
