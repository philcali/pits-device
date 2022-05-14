#!/bin/env python3

from setuptools import setup

setup(
    name="pinthesky",
    version="0.0.1",
    description="Simple Pi In The Sky device Integration",
    author="Philip Cali",
    author_email="philip.cali@gmail.com",
    url="https://github.com/philcali/pinthesky-device",
    license="Apache License 2.0",
    packages=['pinthesky'],
    install_requires=[
        'boto3',
        'requests',
        'numpy',
        'inotify-simple',
        'picamera'
    ]
)