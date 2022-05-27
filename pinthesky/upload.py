import boto3
import os
import logging

from pinthesky.handler import Handler

logger = logging.getLogger(__name__)


class S3Upload(Handler):
    """
    Handles the `combine_end` to flush the video content to a specific path by
    thing name. Note: if the session is not connected to a remote IoT Thing,
    then this handle does nothing.
    """
    def __init__(self, events, bucket_name, bucket_prefix, session):
        self.events = events
        self.bucket_name = bucket_name
        self.bucket_prefix = bucket_prefix
        self.session = session

    def on_combine_end(self, event):
        creds = self.session.login()
        if self.bucket_name is not None and creds is not None:
            video = os.path.basename(event['combine_video'])
            loc = f'{self.bucket_prefix}/{self.session.thing_name}/{video}'
            logger.debug(f"Uploading to s3://{self.bucket_name}/{loc}")
            session = boto3.Session(
                creds['accessKeyId'],
                creds['secretAccessKey'],
                creds['sessionToken'])
            try:
                s3 = session.client('s3')
                with open(event['combine_video'], 'rb') as f:
                    s3.upload_fileobj(f, self.bucket_name, loc)
                self.events.fire_event('upload_end', {
                    'start_time': event['start_time'],
                    'upload': {
                        'bucket_name': self.bucket_name,
                        'bucket_key': loc
                    }
                })
            except RuntimeError as e:
                logger.error(
                    f'Failed to upload to s3://{self.bucket_name}/{loc}: {e}')
            finally:
                # TODO: add a failure strategy / retry attempt here
                os.remove(event['combine_video'])
