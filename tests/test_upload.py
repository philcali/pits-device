from datetime import datetime
from math import floor
import os
from time import time
from unittest.mock import patch
from pinthesky.upload import S3Upload
from pinthesky.events import EventThread
from pinthesky.session import Session


@patch('boto3.Session')
def test_upload(bsession):
    events = EventThread()
    session = Session(
        cert_path="cert_path",
        key_path="key_path",
        cacert_path="cacert_path",
        thing_name="thing_name",
        role_alias="role_alias",
        credentials_endpoint="example.com")
    upload = S3Upload(
        events=events,
        bucket_name="bucket_name",
        bucket_prefix="motion-videos",
        session=session)
    now = datetime.now()
    next_year = datetime(year=now.year + 1, month=now.month, day=1)
    session.credentials = {
        'accessKeyId': 'abc',
        'secretAccessKey': 'efg',
        'sessionToken': '123',
        'expiration': next_year.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    events.on(session)
    events.on(upload)
    events.start()
    video_file = 'test_video.h264'
    with open(video_file, 'w') as f:
        f.write("hello")
    events.fire_event('combine_end', {
        'start_time': floor(time()),
        'combine_video': video_file
    })
    while events.event_queue.unfinished_tasks > 0:
        pass
    try:
        assert bsession.called
    finally:
        if os.path.exists(video_file):
            os.remove(video_file)
