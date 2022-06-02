#!/bin/env python3

from setuptools import setup, find_packages


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="pinthesky",
    version="0.1.1",
    description="Simple Pi In The Sky device Integration",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="Philip Cali",
    author_email="philip.cali@gmail.com",
    url="https://github.com/philcali/pits-device",
    license="Apache License 2.0",
    packages=find_packages(),
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent"
    ],
    install_requires=[
        'boto3',
        'requests',
        'numpy',
        'inotify-simple',
        'picamera'
    ],
    extras_require={
        'test': ['pytest', 'requests-mock']
    }
)
