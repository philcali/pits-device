import boto3
import os
import logging
import time

from math import floor
from pinthesky.config import ConfigUpdate, ShadowConfigHandler
from pinthesky.handler import Handler

logger = logging.getLogger(__name__)


class S3Upload(Handler, ShadowConfigHandler):
    """
    Handles the `combine_end` to flush the video content to a specific path by
    thing name. Note: if the session is not connected to a remote IoT Thing,
    then this handle does nothing.
    """
    def __init__(
            self, events,
            bucket_name,
            bucket_prefix,
            session,
            bucket_image_prefix=None,
            enaabled=True):
        self.events = events
        self.bucket_name = bucket_name
        self.bucket_prefix = bucket_prefix
        self.session = session
        self.bucket_image_prefix = bucket_image_prefix
        self.enabled = enaabled

    def update_document(self) -> ConfigUpdate:
        return ConfigUpdate('storage', {
            'enabled': self.enabled,
            'bucket_name': self.bucket_name,
            'video_prefix': self.bucket_prefix,
            'image_prefix': self.bucket_image_prefix,
        })

    def on_file_change(self, event):
        if 'current' in event['content']:
            desired = event['content']['current']['state']['desired']
            storage = desired.get('storage', {})
            self.enabled = storage.get('enabled', self.enabled)
            self.bucket_name = storage.get('bucket_name', self.bucket_name)
            self.bucket_prefix = storage.get('video_prefix', self.bucket_prefix)
            self.bucket_image_prefix = storage.get('image_prefix', self.bucket_image_prefix)

    def __upload_to_bucket(
            self,
            prefix,
            file_obj,
            source,
            extra_args=None,
            file_type=None):
        creds = self.session.login()
        if self.bucket_name is not None and creds is not None:
            video = os.path.basename(file_obj)
            loc = f'{prefix}/{self.session.thing_name}/{video}'
            logger.debug(f"Uploading to s3://{self.bucket_name}/{loc}")
            session = boto3.Session(
                creds['accessKeyId'],
                creds['secretAccessKey'],
                creds['sessionToken'])
            stat = os.stat(file_obj)
            emf = {
                'CloudWatchMetrics': [
                    {
                        'Dimensions': [
                            ['ThingName', 'Operation'],
                            ['ThingName', 'FileType'],
                        ],
                        'Metrics': [
                            {
                                'Name': 'Size',
                                'Unit': 'Bytes',
                            },
                            {
                                'Name': 'UploadProcessed',
                                'Unit': 'Count',
                            },
                            {
                                'Name': 'Time',
                                'Unit': 'Seconds',
                            }
                        ]
                    }
                ],
                'Size': stat.st_size,
                'Operation': 'Upload',
                'UploadProcessed': 0,
                'File': video,
                'FileType': file_type,
                'Source': source['name'],
            }
            try:
                s3 = session.client('s3')
                with open(file_obj, 'rb') as f:
                    if self.enabled:
                        s3.upload_fileobj(f, self.bucket_name, loc, ExtraArgs=extra_args)
                        emf['UploadProcessed'] = 1
                        self.events.fire_event('upload_end', {
                            'start_time': source['start_time'],
                            'upload': {
                                'bucket_name': self.bucket_name,
                                'bucket_key': loc
                            },
                            'source': source
                        })
                    end_timestamp = floor(time.time())
                    emf['Time'] = end_timestamp - source['start_time']
                    logger.info(f'Uploaded to s3://{self.bucket_name}/{loc}', extra={
                        'emf': emf,
                    })
            except RuntimeError as e:
                end_timestamp = floor(time.time())
                emf['Time'] = end_timestamp - source['start_time']
                logger.error(
                    f'Failed to upload to s3://{self.bucket_name}/{loc}: {e}',
                    exc_info=e,
                    extra={
                        'emf': emf
                    })
            finally:
                # TODO: add a failure strategy / retry attempt here
                os.remove(file_obj)

    def on_capture_image_end(self, event):
        if self.bucket_image_prefix is not None:
            self.__upload_to_bucket(
                self.bucket_image_prefix,
                event['image_file'],
                event,
                file_type='image')

    def on_combine_end(self, event):
        self.__upload_to_bucket(
            self.bucket_prefix,
            event['combine_video'],
            event,
            file_type='video',
            extra_args={
                'Metadata': {
                    'trigger': event['trigger']
                }
            })
