# Pi In The Sky - Device

[![Python package](https://github.com/philcali/pits-device/actions/workflows/python-package.yml/badge.svg)](https://github.com/philcali/pits-device/actions/workflows/python-package.yml)
[![CodeQL](https://github.com/philcali/pits-device/actions/workflows/codeql-analysis.yml/badge.svg)](https://github.com/philcali/pits-device/actions/workflows/codeql-analysis.yml)
[![codecov](https://codecov.io/gh/philcali/pits-device/branch/main/graph/badge.svg?token=WV9HZSP462)](https://codecov.io/gh/philcali/pits-device)

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
    && wget -O $HOME/bin/pitsctl https://raw.githubusercontent.com/philcali/pits-device/main/service/mainv2.sh \
    && chmod +x $HOME/bin/pitsctl \
    && pitsctl -h
```

## Important Note

The current `pinthesky` application is still using the legacy camera module and is only compatible with:

- raspbian OS < 12 (bookworm)
- ArduCam 1.1 and 1.2 (< 1.3)

Until https://github.com/philcali/pits-device/issues/46 is fixed, you must stick to the legacy OS and camera modules.

## Architecture

![pinthesky.png](https://raw.githubusercontent.com/philcali/pits-device/main/images/pinthesky.png)

The `pinthesky` daemon is very light-weight. The entirety of the application runs on 3 threads (optionally 4 with cloudwatch):

- Single thread to manage the camera
- Single thread to poll an event queue
- Single thread to poll inotify
- (Optional) Single thread to upload logs to CloudWatch

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

An entirely optional integration exists with CloudWatch, where device
logs and metrics are uploaded to a desired `LogGroup`. The integration
works in conjuction with a connection to AWS. By turning on the
integration with `--cloudwatch` specify the `LogGroup` with:
`--cloudwatch-log-group <GroupName>`. It will, by default, flush
logs to CloudWatch serially. To background buffer these entries, use
the `--cloudwatch-thread` which reserves a thread for flushing the
log events. By default, the application will use `logs` for
`--cloudwatch-event-type` which matches how logs are normally written
for the daemon. To enable EMF style metrics, use 
`--cloudwatch-event-type emf`. The daemon will manage the `LogStream`
associated to the `LogGroup`, by "{year}/{month}/{day}". It will
delineate the stream by `thing_name`. To disable this behavior, use
`--disable-cloudwatch-stream-split`.

```
  --cloudwatch          enable the cloudwatch upload, default false
  --cloudwatch-thread   enable cloudwatch logs to upload in background, default false
  --cloudwatch-event-type CLOUDWATCH_EVENT_TYPE
                        event type to upload: logs,emf,all
  --cloudwatch-metric-namespace CLOUDWATCH_METRIC_NAMESPACE
                        metric namespace when using emf event type, default Pits/Device
  --cloudwatch-log-group CLOUDWATCH_LOG_GROUP
                        uploads to this cloudwatch log group
  --disable-cloudwatch-stream-split
                        disables splitting the log stream by thing name
```

__Note__: These can be configured correctly for you if you follow the guided `pitsctl` installation
wizard.

## Usage

The `pitsctl` entry point can handle three targets:

- `install`: Installs or updates software and agents for running the camera control
- `remove`: Removes all configuration, cloud resources, software and agents
- `view`: Inpects the installation on the device

```
Usage: pitsctl - v0.8.0: Install or manage pinthesky software
  -h,--help:    Prints out this help message
  -m,--host:    Client machine connection details
  -t,--text:    Enable a no color, text only view of the application
  -r,--root:    Assume root permission for management
  -l,--level:   Changes the logging verbosity for pitsctl
  -v,--version: Prints the version and exists
```

## Control Plane and Infrastructure

The [pits-infra][1] package can be used to deploy a complete and working 
AWS cloud infrastructure to support the device configuration and integration.
The infrastructure contains the following:

- Storage configuration
- Policy and device authorization
- Control Plane deployment
- Console deployment
- Console authorization through Cognito

Follow the [re-use][2] section in the README to deploy it for at no charge
or 50 cents a month if a custom domain is included.

[1]: https://github.com/philcali/pits-infra
[2]: https://github.com/philcali/pits-infra?tab=readme-ov-file#re-use

## Optimal Settings

Adjusting the bitrate, buffer, resolution, framerate, etc... It's a lot to take in.

The default values work, but you will find the buffer doesn't quite mesh with a zero.

1. resolution=640x480
2. framerate=20
3. bitrate=17000000 (17Mbps)
4. profile=high
5. level=4

For a first gen PiZero, these settings might be too high. I've seen success with

1. resolution=640x480
2. framerate=15
3. bitrate=5000000 (5Mbps)
4. profile=high
5. level=2.2

This reduces the file size by 60% and aligns buffering to clock time a little more accurately.
