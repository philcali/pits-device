from cmath import e
from requests import request, exceptions
import datetime
import logging
import threading

logger = logging.getLogger(__name__)

class Session():
    def __init__(self, cert_path, key_path, cacert_path, thing_name, role_alias, credentials_endpoint):
        self.cert_path = cert_path
        self.key_path = key_path
        self.cacert_path = cacert_path
        self.thing_name = thing_name
        self.role_alias = role_alias
        self.credentials_endpoint = credentials_endpoint
        self.credentials = None
        self.refresh_lock = threading.Lock()
        if "https://" not in credentials_endpoint:
            self.credentials_endpoint = f'https://{credentials_endpoint}'


    def parse_time(expiration):
        return datetime.datetime.strptime(expiration, "%Y-%m-%dT%H:%M:%SZ")


    def login(self, force=False):
        current_time = datetime.datetime.now()
        if force or self.credentials is None or self.parse_time(self.credentials['expiration']) < current_time:
            with self.refresh_lock:
                try: 
                    self.credentials = None
                    res = request.get(
                        '/'.join([self.credentials_endpoint, 'role-aliases', self.role_alias, 'credentials']),
                        headers={'x-amzn-iot-thingname', self.thing_name},
                        verify=self.cacert_path,
                        cert=(self.cert_path, self.key_path))
                    res.raise_for_status()
                    self.credentials = res.json()
                except exceptions.Timeout:
                    logger.error("Request timeout to %s", self.credentials_endpoint)
                except exceptions.HTTPError as err:
                    logger.error("Failed to refresh AWS credentials from %s: %s",
                        self.credentials_endpoint, err)
                except exceptions.RequestException:
                    logger.error("Failed to refresh AWS credentials from %s",
                        self.credentials_endpoint)
        return self.credentials
