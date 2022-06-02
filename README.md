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
mkdir -p $HOME/bin \
    && wget -O $HOME/bin/pitsctl https://raw.githubusercontent.com/philcali/pits-device/main/service/main.sh \
    && chmod +x $HOME/bin/pitsctl \
    && pitsctl -h
```

## Usage

The `pitsctl` entry point can handle three targets:

- `install`: Installs or updates software and agents for running the camera control
- `remove`: Removes all configuration, cloud resources, software and agents
- `inspect`: Inpects the installation on the device

```
Usage: pitsctl - v0.1.1: Install or manage pinthesky software
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