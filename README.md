# Pi In The Sky - Device

[![Python package](https://github.com/philcali/pits-device/actions/workflows/python-package.yml/badge.svg)](https://github.com/philcali/pits-device/actions/workflows/python-package.yml) [![Total alerts](https://img.shields.io/lgtm/alerts/g/philcali/pits-device.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/philcali/pits-device/alerts/) [![Language grade: Python](https://img.shields.io/lgtm/grade/python/g/philcali/pits-device.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/philcali/pits-device/context:python)

This is the Pi In The Sky (pits) device-side software.

## Installation

To install the device software directly from GitHub, or build against it:

```
pip3 install pinthesky
```

You can also use the guided install from your work station to remotely configure a RPi via ssh. Some pre-requisites are:

1. Need to be able to `sudo` if selected to assume root
1. Make your life easier with `ssh-copy-id user@ip` for pub key auth
1. Have the `aws` CLI on your workstation with permission to create things, roles, S3 buckets, and policies
1. Run `sh` locally to enter the guide:

```
mkdir -p $HOME/bin \
    && wget -O $HOME/bin/pitsctl https://raw.githubusercontent.com/philcali/pits-device/main/service/main.sh \
    && chmod +x $HOME/bin/pitsctl \
    && pitsctl -h
```

## Architecture

![pinthesky.png](https://raw.githubusercontent.com/philcali/pits-device/main/images/pinthesky.png)

The `pinthesky` daemon is very light-weight. The entirety of the application runs on 3 threads:

- Single thread to manage the camera
- Single thread to poll an event queue
- Single thread to poll inotify

The camera thread detects motion vectors in the recording. The buffer is flushed and an event is
signaled to combine the buffered video with the live stream. The `h264` file triggers an event
to begin an upload to S3, if S3 was configured. The following camera configuration flags exists:

```
  --combine-dir COMBINE_DIR
                        the directory to combine video, defaults to
                        motion_videos
  --rotation ROTATION   rotate the video, valid arguments [0, 90, 180, 270]
  --resolution RESOLUTION
                        camera resolution, defaults 640x480
  --framerate FRAMERATE
                        framerate of the camera, defaults to 20
  --buffer BUFFER       buffer size in seconds, defaults to 15
  --sensitivity SENSITIVITY
                        sensitivity of the motion detection math, default 10
```

Where does `inotify` come into play? An optional integration with
`aws-iot-device-client` exists to handle the MQTT related connections to AWS IoT. Through
the `aws-iot-device-client`, the `pinthesky` can read MQTT published messages from a file. These
events will populate the internal event queue. This is useful for manually triggering a video upload.

The `aws-iot-device-client` can also listen to AWS IoT Shadow Document updates. These updates
are written to a file which `pinthesky` can read to reconfigure the camera (buffer, framerate, etc).
The follow configuration is used to poll `inotify` for changes:

```
  --event-input EVENT_INPUT
                        file representing external input, default input.json
  --event-output EVENT_OUTPUT
                        file representing external output, default output.json
  --configure-input CONFIGURE_INPUT
                        file for configuration input, default config-
                        input.json
  --configure-output CONFIGURE_OUTPUT
                        file for configuration output, default config-
                        output.json
```

The integration with AWS is entirely optional through AWS IoT device configuration.
Running the daemon with the following commands allow the device to exchange temporary
AWS V4 credentials with a X509 certificate:

```
  --thing-name THING_NAME
                        the AWS IoT ThingName for use in upload
  --thing-cert THING_CERT
                        the AWS IoT certificate associated to the Thing
  --thing-key THING_KEY
                        the AWS IoT certificate pair associated to the Thing
  --ca-cert CA_CERT     the root CA certificate to authenticate the
                        certificate
  --credentials-endpoint CREDENTIALS_ENDPOINT
                        the AWS IoT Credentials Provider endpoint
  --role-alias ROLE_ALIAS
                        the AWS IoT Role Alias to pull credentials
```

Once credentials are obtained, the `pinthesky` daemon will attempt to upload to an S3 bucket
location. These values are configured with:

```
  --bucket-name BUCKET_NAME
                        the S3 bucket to upload motion detection files
  --bucket-prefix BUCKET_PREFIX
                        the prefix to upload the motion files to, default
                        motion_videos
```


__Note__: These can be configured correctly for you if you follow the guided `pitsctl` installation
wizard.

## Usage

The `pitsctl` entry point can handle three targets:

- `install`: Installs or updates software and agents for running the camera control
- `remove`: Removes all configuration, cloud resources, software and agents
- `inspect`: Inpects the installation on the device

```
Usage: pitsctl - v0.1.3: Install or manage pinthesky software
  -h: Prints out this help message
  -t: Define the target, applicable values are 'install', 'remove', 'inspect'
  -m: Client machine connection details
  -r: Assume root permission for management
  -v: Prints the version and exists
```

### Example Install

Runs the install wizard on a pi from a client machine

```
pitsctl -t install -rm pi@10.0.0.1
```

Runs the install wizard

```
pitsctl
```

### Example Inpsect

Runs an inspector and outputs a summary

```
pitsctl -t inspect -rm pi@10.0.0.1
```

Runs the inspection wizard

```
pitsctl -t inspect
```

### Example Remove

Runs the removal wizard on a pi from a client machine

```
pitsctl -t remove -rm pi@10.0.0.1
```

Runs the removal wizard

```
pitsctl -t remove
```