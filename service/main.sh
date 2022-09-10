#!/bin/bash

VERSION="0.5.0"
DEFAULT_THING_NAME="PinTheSkyThing"
DEFAULT_THING_GROUP="PinTheSkyGroup"
DEFAULT_ROLE_ALIAS_NAME="PinTheSkyRoleAlias"
DEFAULT_ROLE_NAME="PinTheSkyRole"
DEFAULT_THING_POLICY_NAME="PinTheSkyThingPolicy"
DEFAULT_BUCKET_PREFIX="motion_videos"
DEFAULT_BUCKET_IMAGE_PREFIX="capture_images"
DEFAULT_EVENT_INPUT="/usr/share/pinthesky/events/input.json"
DEFAULT_EVENT_OUTPUT="/usr/share/pinthesky/events/output.json"
DEFAULT_CONFIGURE_INPUT="/usr/share/pinthesky/configuration/input.json"
DEFAULT_CONFIGURE_OUTPUT="/usr/share/pinthesky/configuration/output.json"
DEFAULT_COMBINE_DIR="/usr/share/pinthesky/motion_videos"
DEFAULT_CAPTURE_DIR="/usr/share/pinthesky/capture_images"
DEFAULT_BUFFER="15"
DEFAULT_SENSITIVITY="10"
DEFAULT_FRAMERATE="20"
DEFAULT_ROTATION="0"
DEFAULT_RESOLUTION="640x480"
DEFAULT_ENCODING_BITRATE="17000000"
DEFAULT_ENCODING_LEVEL="4"
DEFAULT_ENCODING_PROFILE="high"
DEFAULT_SHADOW_UPDATE="empty"
RAW_CONTENT_URL="https://raw.githubusercontent.com/philcali/pits-device/main"
INSTALL_VERSION=${INSTALL_VERSION:-"pinthesky==$VERSION"}
ROOT_CA_LOCATION="https://www.amazontrust.com/repository/AmazonRootCA1.pem"
CERT_FILE="thing.cert.pem"
PRV_KEY_FILE="thing.key"
PUB_KEY_FILE="thing.pub"
CA_CERT="AmazonRootCA1.pem"

# Prompt color constants, from https://github.com/awslabs/aws-iot-device-client/blob/main/setup.sh
PMPT='\033[95;1m%s\033[0m\n'
GREEN='\033[92m%s\033[0m\n'
RED='\033[91m%s\033[0m\n'

banner() {
    echo "
########################################################

######                                                   
#     # # #    # ##### #    # ######  ####  #    # #   # 
#     # # ##   #   #   #    # #      #      #   #   # #  
######  # # #  #   #   ###### #####   ####  ####     #   
#       # #  # #   #   #    # #           # #  #     #   
#       # #   ##   #   #    # #      #    # #   #    #   
#       # #    #   #   #    # ######  ####  #    #   #   

########################################################

Welcome to the configuration UI for a pinthesky device!
"
}

import_function() {
    local resolve_path=$1
    local import_file=$2
    local self_path=$(realpath $1)
    local self_dir=$(dirname $self_path)
    local script_file="$self_dir/pits/$import_file"
    if [ ! -f "$script_file" ]; then
        download_resource $import_file
        if [ ! -d $(dirname "$script_file") ]; then
            mkdir -p $(dirname "$script_file")
        fi
        mv $PWD/$import_file $script_file
    fi
    . $script_file
}

usage() {
    printf $PMPT "Usage: $(basename $0) - v$VERSION: Install or manage pinthesky software"
    echo "  -h: Prints out this help message"
    echo "  -t: Define the target, applicable values are 'install', 'remove', 'inspect'"
    echo "  -m: Client machine connection details"
    echo "  -r: Assume root permission for management"
    echo "  -v: Prints the version and exists"
}

configure_host_connection() {
    if [ -z "$HOST_MACHINE" ]; then
        printf $PMPT "Are you running the install from a client machine? [y/n]"
        read -r CLIENT_MACHINE
    else
        CLIENT_MACHINE='y'
    fi
    if [ "$CLIENT_MACHINE" = 'y' ]; then
        TEST_OUTPUT=""
        while [ -z "$TEST_OUTPUT" ]; do
            if [ -z "$HOST_MACHINE" ]; then
                printf $PMPT "Machine host, ex: pi@hostname.com"
                read -r HOST_MACHINE
            fi
            COMMAND_PREFIX="ssh -o ConnectTimeout=3 $HOST_MACHINE"
            TEST_OUTPUT=$($COMMAND_PREFIX echo hello world 2>/dev/null)
            if [ $(echo $?) -ne 0 ]; then
                printf $RED "Could not communicate to $HOST_MACHINE, is that correct?"
                HOST_MACHINE=""
            fi
        done
        printf $GREEN "Successfully connected to $HOST_MACHINE"
    fi

    if [ -z "$ASSUME_ROOT" ]; then
        printf $PMPT "Can I assume root privileges to install things? [y/n]"
        read -r ASSUME_ROOT
    fi
    if [ "$ASSUME_ROOT" = 'y' ]; then
        COMMAND_PREFIX="$COMMAND_PREFIX sudo"
        printf $GREEN "Using root permissions for management of $HOST_MACHINE"
    else
        printf $RED "WARNING: Parts of the installation may not succeed."
    fi

    DRYRUN=${DRYRUN:-0}
    if [ $DRYRUN -eq 1 ]; then
        COMMAND_PREFIX="echo $COMMAND_PREFIX"
    fi
}

validate_target() {
    local provided_target=$1
    local valid_target=""
    local found_target=""

    for valid_target in install remove inspect; do
        if [ "$valid_target" = "$provided_target" ]; then
            found_target=valid_target
        fi
    done

    if [ -z "$found_target" ]; then
        printf $RED "Target of $provided_target is not valid"
        usage
        exit 1
    fi
}

download_resource() {
    local RESOURCE_FILE=$1

    if [ -f "service/$RESOURCE_FILE" ]; then
        # Assume we're running locally
        cp service/$RESOURCE_FILE $RESOURCE_FILE
    else
        # Pull from CDN
        wget -O $RESOURCE_FILE $RAW_CONTENT_URL/service/$RESOURCE_FILE
    fi
}

ASSUME_ROOT=""
HOST_MACHINE=""
COMMAND_PREFIX=""
TARGET="install"
while getopts "vhrm:t:" flag
do
    case "${flag}" in
        v) echo $VERSION
            exit 0
            ;;
        m) HOST_MACHINE="${OPTARG}";;
        r) ASSUME_ROOT='y';;
        t) TARGET="${OPTARG}"
            validate_target $TARGET
            ;;
        h) usage
            exit 0
            ;;
        *) usage
            exit 1
            ;;
    esac
done

banner

configure_host_connection

printf $PMPT "Running the $TARGET function on the device."
import_function $0 "$TARGET.sh"
${TARGET}_device "$COMMAND_PREFIX" "$CLIENT_MACHINE" "$HOST_MACHINE"
