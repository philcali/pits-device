# Pi In The Sky - Device

This is the Pi In The Sky (pits) device-side software.

## Installation

To install the device software directly from GitHub, or build against it:

```
pip3 install git+https://github.com/philcali/pits-device.git
```

You can also use the guided install from your work station to remotely configure a RPi via ssh. Some pre-requisites are:

1. Need to be able to `sudo` if selected to assume root
1. Make your life easier with `ssh-copy-id user@ip` for pub key auth
1. Have the `aws` CLI on your workstation with permission to create things, roles, S3 buckets, and policies
1. Run `sh` locally to enter the guide:

```
wget https://raw.githubusercontent.com/philcali/pits-device/main/service/install.sh && sh install.sh && rm install.sh
```