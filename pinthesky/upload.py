import boto3
import os
import logging

from pinthesky.handler import Handler

logger = logging.getLogger(__name__)

class S3Upload(Handler):
    def __init__(self, events, bucket_name, bucket_prefix, session):
        self.events = events
        self.bucket_name = bucket_name
        self.bucket_prefix = bucket_prefix
        self.session = session


    def on_combine_end(self, event):
        creds = self.session.login()
        if self.bucket_name is not None and creds is not None:
            video_file = os.path.basename(event['combine_video'])
            bucket_location = f'{self.bucket_prefix}/{self.session.thing_name}/{video_file}'
            logger.debug(f"Uploading to s3://{self.bucket_name}/{bucket_location}")
            session = boto3.Session(
                creds['accessKeyId'],
                creds['secretAccessKey'],
                creds['sessionToken'])
            try:
                s3 = session.client('s3')
                with open(event['combine_video'], 'rb') as f:
                    s3.upload_fileobj(f, self.bucket_name, bucket_location)
                self.events.fire('upload_end', {
                    'start_time': event['start_time'],
                    'upload': {
                        'bucket_name': self.bucket_name,
                        'bucket_key': bucket_location
                    }
                })
            except RuntimeError as e:
                logger.error(f'Failed to upload to s3://{self.bucket_name}/{bucket_location}: {e}')
            finally:
                # TODO: add a failure strategy / retry attempt here
                os.remove(event['combine_video'])
