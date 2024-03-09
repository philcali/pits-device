from pinthesky.config import ConfigUpdate, ShadowConfigHandler
from pinthesky.handler import Handler
from requests import get, exceptions
import datetime
import logging
import threading


logger = logging.getLogger(__name__)
fields = [
    "cert_path",
    "key_path",
    "cacert_path",
    "thing_name",
    "role_alias",
    "credentials_endpoint"
]


class Session(Handler, ShadowConfigHandler):
    """
    An auth session wrapper that caches AWS credential material until expiry.
    """
    def __init__(
            self, cert_path, key_path, cacert_path,
            thing_name, role_alias, credentials_endpoint):
        self.cert_path = cert_path
        self.key_path = key_path
        self.cacert_path = cacert_path
        self.thing_name = thing_name
        self.role_alias = role_alias
        self.credentials = None
        self.refresh_lock = threading.Lock()
        self.__set_endpoint(credentials_endpoint)

    def __set_endpoint(self, endpoint):
        if endpoint is not None and "https://" not in endpoint:
            endpoint = f'https://{endpoint}'
        self.credentials_endpoint = endpoint

    def __is_expired(self, current_time):
        expiration = self.credentials['expiration'].replace('Z', ' UTC')
        expiry = datetime.datetime.strptime(expiration, "%Y-%m-%dT%H:%M:%S %Z")
        return expiry < current_time

    def update_document(self) -> ConfigUpdate:
        return ConfigUpdate('cloud_connection', {
            'cert_path': self.cert_path,
            'cacert_path': self.cacert_path,
            'key_path': self.key_path,
            'thing_name': self.thing_name,
            'role_alias': self.role_alias,
            'credentials_endpoint': self.credentials_endpoint
        })

    def on_file_change(self, event):
        if "current" in event["content"]:
            desired = event["content"]["current"]["state"]["desired"]
            con = desired["cloud_connection"]
            with self.refresh_lock:
                self.credentials = None
                for field in fields:
                    if field in con:
                        val = con[field]
                        if field == "credentials_endpoint":
                            self.__set_endpoint(val)
                        else:
                            setattr(self, field, con[field])

    def login(self, force=False):
        ct = datetime.datetime.utcnow()
        if force or self.credentials is None or self.__is_expired(ct):
            with self.refresh_lock:
                try:
                    self.credentials = None
                    if self.credentials_endpoint is not None:
                        res = get(
                            '/'.join([
                                self.credentials_endpoint,
                                'role-aliases',
                                self.role_alias,
                                'credentials']),
                            headers={'x-amzn-iot-thingname': self.thing_name},
                            verify=self.cacert_path,
                            cert=(self.cert_path, self.key_path))
                        res.raise_for_status()
                        payload = res.json()
                        if "credentials" not in payload:
                            logger.warning(
                                f'Expected "credentials", received: {payload}')
                        else:
                            self.credentials = payload['credentials']
                except exceptions.Timeout:
                    logger.error(
                        "Request timeout to %s",
                        self.credentials_endpoint)
                except exceptions.HTTPError as err:
                    logger.error(
                        "Failed to refresh AWS credentials from %s: %s",
                        self.credentials_endpoint,
                        err,
                        exc_info=err)
                except exceptions.RequestException as err:
                    logger.error(
                        "Failed to refresh AWS credentials from %s",
                        self.credentials_endpoint,
                        exc_info=err)
        return self.credentials
