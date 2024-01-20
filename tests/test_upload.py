from datetime import datetime
from math import floor
import os
from time import time
from unittest.mock import patch
from pinthesky.upload import S3Upload
from pinthesky.events import EventThread
from pinthesky.session import Session
from test_handler import TestHandler


@patch('boto3.Session')
def test_upload(bsession):
    test_handler = TestHandler()
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
    events.on(test_handler)
    events.start()
    tuple = [
        ('combine_end', 'combine_video'),
        ('capture_image_end', 'image_file')
    ]
    for event_name, field in tuple:
        data_file = f'{field}.data'
        with open(data_file, 'w') as f:
            f.write("hello")
        context = {'start_time': floor(time()), 'trigger': 'motion'}
        context[field] = data_file
        events.fire_event(event_name, context)
    while events.event_queue.unfinished_tasks > 0:
        pass
    try:
        assert bsession.called
        # Called once because image prefix is unset
        assert test_handler.calls['upload_end'] == 1
    finally:
        for event_name, field in tuple:
            if os.path.exists(f'{field}.data'):
                os.remove(f'{field}.data')


@patch('boto3.Session')
def test_image_upload(bsession):
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
        bucket_image_prefix="capture_images",
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
    image_file = 'test_image.jpg'
    with open(image_file, 'w') as f:
        f.write("hello")
    events.fire_event('capture_image_end', {
        'start_time': floor(time()),
        'image_file': image_file
    })
    while events.event_queue.unfinished_tasks > 0:
        pass
    try:
        assert bsession.called
    finally:
        if os.path.exists(image_file):
            os.remove(image_file)
