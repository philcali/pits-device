#!/usr/bin/env bash

VERSION=0.5.1
RAW_CONTENT_URL="https://raw.githubusercontent.com/philcali/pits-device/main"
ASSUME_ROOT="false"
MACHINE_HOST=""
PROGRAM=""
LOG_LEVEL="INFO"

download_resource() {
    local RESOURCE_FILE=$1

    if [ ! -f "service/pitsctl/$RESOURCE_FILE" ]; then
        # Pull from CDN
        wget -O "$RESOURCE_FILE" "$RAW_CONTENT_URL/service/pitsctl/$RESOURCE_FILE"
        return 0
    fi
    return 1
}

import_function() {
    local resolve_path=$1
    local import_file=$2
    local self_path 
    self_path=$(realpath "$resolve_path")
    local self_dir
    self_dir=$(dirname "$self_path")
    local script_file="$self_dir/pitsctl/$import_file"
    if [ ! -f "$script_file" ] && download_resource "$import_file"; then
        if [ ! -d "$(dirname "$script_file")" ]; then
            mkdir -p "$(dirname "$script_file")"
        fi
        mv "$import_file" "$script_file"
    fi
    echo "$script_file"
}

install_dialog_wheel() {
    git clone https://github.com/philcali/dialog-wheel.git
    pushd dialog-wheel || return 1
    ./dev.build.sh || return 1

    local paths
    IFS=':' read -r -a paths <<< "$PATH"
    for path in "${paths[@]}"
    do  
        mv dialog-wheel "$path/" && echo "Installed dialog-wheel in $path" && break
    done
    popd && rmdir dialog-wheel
}

usage() {
    echo "Usage: $(basename "$0") - v$VERSION: Install or manage pinthesky software"
    echo "  -h,--help:    Prints out this help message"
    echo "  -m,--host:    Client machine connection details"
    echo "  -t,--text:    Enable a no color, text only view of the application"
    echo "  -r,--root:    Assume root permission for management"
    echo "  -v,--version: Prints the version and exists"
}

parse_args() {
    while [ -n "$*" ]; do
        local param=$1
        case "$param" in
        -r|--root)
            ASSUME_ROOT="true";;
        -t|--text)
            PROGRAM='"program": "wheel::dialog::app",';;
        -m|--host)
            shift
            MACHINE_HOST=$1;;
        -l|--level)
            shift
            LOG_LEVEL=$1;;
        -v|--version)
            echo "$VERSION" && return 1;;
        -h|--help)
            usage && return 1;;
        esac
        shift
    done
}

parse_args "$@" || exit 0

cat << EOF > defaults.json
{
    "cloud": {
        "thing_name": "PinTheSkyThing",
        "thing_group": "PinTheSkyGroup",
        "role_alias": "PinTheSkyRoleAlias",
        "role_name": "PinTheSkyRole",
        "thing_policy": "PinTheSkyThingPolicy",
        "create_certificates": true
    },
    "storage": {
        "bucket": "$USER-pinthesky-storage",
        "policy_name": "$USER-pinthesky-storage-policy",
        "video_prefix": "motion_videos",
        "image_prefix": "capture_images"
    },
    "software": {
        "install": "Current",
        "service": "Nothing"
    },
    "client": {
        "install_software": true,
        "install_job_handlers": true,
        "install_configuration": true,
        "install_service": true
    },
    "device": {
        "paths": {
            "event_input": "/usr/share/pinthesky/events/input.json",
            "event_output": "/usr/share/pinthesky/events/output.json",
            "configure_input": "/usr/share/pinthesky/configuration/input.json",
            "configure_output": "/usr/share/pinthesky/configuration/output.json",
            "jobs_dir": "/usr/share/pinthesky/job/handlers",
            "combine_dir": "/usr/share/pinthesky/motion_videos",
            "capture_dir": "/usr/share/pinthesky/capture_images"
        },
        "health_interval": 3600
    },
    "camera": {
        "sensitivity": 10,
        "framerate": 20,
        "rotation": 0,
        "buffer": 15,
        "recording_window": {
            "start": 0,
            "end": 23
        },
        "resolution": {
            "width": 640,
            "height": 480
        },
        "encoding": {
            "level": 4,
            "profile": "high",
            "bitrate": "17000000"
        }
    },
    "assume_root": $ASSUME_ROOT,
    "machine_host": "$MACHINE_HOST"
}
EOF

trap "rm -rf defaults.json" EXIT

command -v dialog-wheel > /dev/null || install_dialog_wheel || exit 1
common_script=$(import_function "$0" "_common.sh")
inspect_script=$(import_function "$0" "inspect.sh")
remove_script=$(import_function "$0" "remove.sh")
install_script=$(import_function "$0" "install.sh")

START_SCREEN="Welcome"
[ -n "$MACHINE_HOST" ] && START_SCREEN="Connection Validate"

cat << EOF | dialog-wheel -d defaults.json -l pitsctl.log -L "$LOG_LEVEL" -s "$START_SCREEN"
{
    "version": "1.0.0",
    "dialog": {
        $PROGRAM
        "colors": true,
        "backtitle": "Pi In The Sky - Setup Wizard"
    },
    "handlers": {
        "esc": "wheel::handlers::cancel"
    },
    "properties": {
        "aspect": 20
    },
    "includes": [
        {
            "file": "$common_script"
        },
        {
            "file": "$inspect_script"
        },
        {
            "file": "$remove_script"
        },
        {
            "file": "$install_script"
        }
    ],
    "start": "Welcome",
    "exit": "Exit",
    "error": "Error",
    "screens": {
        "Welcome": {
            "type": "msgbox",
            "properties": {
                "width": 48,
                "height": 6,
                "text": "Welcome to the \\\ZbPi in the Sky\\\ZB Setup Wizard.\\nLet's get started."
            },
            "next": "Main Menu"
        },
        "Main Menu": {
            "type": "hub",
            "clear_history": true,
            "dialog": {
                "cancel-label": "Exit"
            },
            "properties": {
                "items": [
                    {
                        "name": "View",
                        "description": "Inspect a pinthesky installation"
                    },
                    {
                        "name": "Install",
                        "description": "Install and configures pinthesky"
                    },
                    {
                        "name": "Remove",
                        "description": "Removes pinthesky from a device"
                    },
                    {
                        "name": "Command Settings",
                        "description": "Configure command execution settings"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::screens::hub::selection"
            }
        },
        "Install": {
            "type": "hub",
            "clear_history": true,
            "dialog": {
                "ok-label": "Configure",
                "cancel-label": "Back",
                "extra-button": true,
                "extra-label": "Install"
            },
            "properties": {
                "items": [
                    {
                        "name": "Cloud Configuration",
                        "description": "Creates and configures AWS resources"
                    },
                    {
                        "name": "Storage Configuration",
                        "description": "Manages remote storage of images and videos"
                    },
                    {
                        "name": "Device Software",
                        "description": "Installs pinthesky software"
                    },
                    {
                        "name": "Device Configuration",
                        "description": "Installs and configures pinthesky"
                    },
                    {
                        "name": "Camera Configuration",
                        "description": "Configures camera settings"
                    },
                    {
                        "name": "Device Client",
                        "description": "Installs and configures AWS IoT device client"
                    },
                    {
                        "name": "Service Configuration",
                        "description": "Installs and configures systemd services"
                    }
                ]
            },
            "next": "Review and Install",
            "handlers": {
                "ok": "wheel::screens::hub::selection",
                "extra": "wheel::handlers::ok"
            },
            "back": "Main Menu"
        },
        "Review and Install": {
            "type": "yesno",
            "properties": {
                "text": "Are you ready to begin the install?"
            },
            "next": "Install Gauge"
        },
        "Install Gauge": {
            "type": "custom",
            "entrypoint": "pits::setup::install::device",
            "managed": true,
            "properties": {
                "width": 70,
                "actions": []
            },
            "next": "Install Results"
        },
        "Install Results": {
            "type": "textbox",
            "dialog": {
                "exit-label": "Back"
            },
            "properties": {
                "text": "pits.install.log"
            },
            "next": "Main Menu"
        },
        "Cloud Configuration": {
            "type": "hub",
            "clear_history": true,
            "dialog": {
                "ok-label": "Configure",
                "cancel-label": "Back"
            },
            "properties": {
                "items": [
                    {
                        "name": "AWS IoT Configuration",
                        "description": "Creates and configures AWS IoT Associations"
                    },
                    {
                        "name": "Create Certificates",
                        "description": "Creates and associates AWS IoT Certificates"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::screens::hub::selection"
            },
            "back": "Install"
        },
        "Create Certificates": {
            "type": "yesno",
            "capture_into": "cloud.create_certificates",
            "properties": {
                "text": "Create new AWS IoT Certificates?\nCurrent Value: [\\\Zb\$state.cloud.create_certificates\\\ZB]"
            },
            "handlers": {
                "capture_into": "wheel::handlers::flag",
                "ok": "wheel::handlers::cancel",
                "cancel": [
                    "wheel::handlers::flag",
                    "wheel::handlers::cancel"
                ]
            },
            "next": "Cloud Configuration"
        },
        "Storage Configuration": {
            "type": "form",
            "capture_into": "storage",
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "items": [
                    {
                        "name": "Bucket:",
                        "length": 64,
                        "configures": "bucket"
                    },
                    {
                        "name": "Role Policy:",
                        "length": 60,
                        "configures": "policy_name"
                    },
                    {
                        "name": "Motion Video Prefix:",
                        "length": 64,
                        "configures": "video_prefix"
                    },
                    {
                        "name": "Image Capture Prefix:",
                        "length": 64,
                        "configures": "image_prefix"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::screens::form::save",
                "ok": "wheel::handlers::cancel"
            }
        },
        "AWS IoT Configuration": {
            "type": "form",
            "capture_into": "cloud",
            "dialog": {
                "cancel-label": "Back",
                "extra-button": true,
                "extra-label": "Validate"
            },
            "properties": {
                "items": [
                    {
                        "name": "Thing Name:",
                        "length": 60,
                        "configures": "thing_name"
                    },
                    {
                        "name": "Thing Policy:",
                        "length": 60,
                        "configures": "thing_policy"
                    },
                    {
                        "name": "Thing Group:",
                        "length": 60,
                        "configures": "thing_group"
                    },
                    {
                        "name": "Role Name:",
                        "length": 60,
                        "configures": "role_name"
                    },
                    {
                        "name": "Role Alias:",
                        "length": 60,
                        "configures": "role_alias"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::screens::form::save",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Device Software": {
            "type": "radiolist",
            "capture_into": "software.install",
            "properties": {
                "text": "Select behavior:",
                "items": [
                    {
                        "name": "Current",
                        "description": "Only installs if a version is not installed"
                    },
                    {
                        "name": "Latest",
                        "description": "Installs or updates to latest version"
                    },
                    {
                        "name": "Nothing",
                        "description": "Do not attempt an installation"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::handlers::cancel"
            }
        },
        "Device Configuration": {
            "type": "hub",
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "items": [
                    {
                        "name": "Configuration Paths",
                        "description": "File and folder locations for pinthesky"
                    },
                    {
                        "name": "Health Check Interval",
                        "description": "Rate in seconds for post health checks"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::screens::hub::selection"
            }
        },
        "Configuration Paths": {
            "type": "form",
            "capture_into": "device.paths",
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "box_height": 8,
                "items": [
                    {
                        "name": "Event Input:",
                        "length": 80,
                        "max": 256,
                        "configures": "event_input"
                    },
                    {
                        "name": "Event Output:",
                        "length": 80,
                        "max": 256,
                        "configures": "event_output"
                    },
                    {
                        "name": "Configuration Input:",
                        "length": 80,
                        "max": 256,
                        "configures": "configure_input"
                    },
                    {
                        "name": "Configuration Output:",
                        "length": 80,
                        "max": 256,
                        "configures": "configure_output"
                    },
                    {
                        "name": "Job Handlers:",
                        "length": 80,
                        "max": 256,
                        "configures": "jobs_dir"
                    },
                    {
                        "name": "Combine Directory:",
                        "length": 80,
                        "max": 256,
                        "configures": "combine_dir"
                    },
                    {
                        "name": "Image Capture Directory:",
                        "length": 80,
                        "max": 256,
                        "configures": "capture_dir"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::screens::form::save",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Health Check Interval": {
            "type": "range",
            "capture_into": "device.health_interval",
            "properties": {
                "min": 60,
                "max": 86400,
                "default": "\$state.device.health_interval",
                "text": "Rate in seconds:",
                "width": 70
            },
            "handlers": {
                "capture_into": "wheel::handlers::capture_into::argjson",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Device Client": {
            "type": "checklist",
            "capture_into": "client",
            "properties": {
                "text": "AWS Device Client installation actions:",
                "items": [
                    {
                        "name": "Software",
                        "description": "Installs the device client software",
                        "configures": "client.install_software"
                    },
                    {
                        "name": "Jobs",
                        "description": "Installs the job handlers",
                        "configures": "client.install_job_handlers"
                    },
                    {
                        "name": "Configuration",
                        "description": "Installs the device client configuration",
                        "configures": "client.install_configuration"
                    },
                    {
                        "name": "Service",
                        "description": "Installs the systemd service unit",
                        "configures": "client.install_service"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::screens::checklist::field",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Service Configuration": {
            "type": "radiolist",
            "capture_into": "software.service",
            "properties": {
                "text": "Configure pinthesky service action:",
                "items": [
                    {
                        "name": "Enable",
                        "description": "Installs and enables the pinthesky systemd service"
                    },
                    {
                        "name": "Install",
                        "description": "Installs the pinthesky systemd service"
                    },
                    {
                        "name": "Nothing",
                        "description": "Does not install the pinthesky systemd service"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::handlers::cancel"
            }
        },
        "Camera Configuration": {
            "type": "hub",
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "items": [
                    {
                        "name": "Buffer",
                        "description": "Seconds to buffer recorded video"
                    },
                    {
                        "name": "Sensitivity",
                        "description": "Motion sensitivity"
                    },
                    {
                        "name": "Framerate",
                        "description": "The framerate of the recording"
                    },
                    {
                        "name": "Rotation",
                        "description": "Rotation of the camera"
                    },
                    {
                        "name": "Recording Window",
                        "description": "The hours when the camera records motion"
                    },
                    {
                        "name": "Resolution",
                        "description": "The resolution of the camera"
                    },
                    {
                        "name": "Encoding",
                        "description": "Configure the encoding profile"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::screens::hub::selection"
            }
        },
        "Buffer": {
            "type": "range",
            "capture_into": "camera.buffer",
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "max": 60,
                "min": 1,
                "default": "\$state.camera.buffer",
                "text": "Seconds for motion recording:",
                "width": 70
            },
            "handlers": {
                "capture_into": "wheel::handlers::capture_into::argjson",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Sensitivity": {
            "type": "range",
            "capture_into": "camera.sensitivity",
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "max": 50,
                "min": 1,
                "default": "\$state.camera.sensitivity",
                "text": "Motion sensitivity (higher the value, more aggressive the motion):",
                "width": 70
            },
            "handlers": {
                "capture_into": "wheel::handlers::capture_into::argjson",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Framerate": {
            "type": "range",
            "capture_into": "camera.framerate",
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "max": 20,
                "min": 10,
                "default": "\$state.camera.framerate",
                "text": "Recording framerate:",
                "width": 70
            },
            "handlers": {
                "capture_into": "wheel::handlers::capture_into::argjson",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Rotation": {
            "type": "radiolist",
            "capture_into": "camera.rotation",
            "properties": {
                "text": "Select the rotation degrees:",
                "items": [
                    {
                        "name": "0",
                        "description": "No rotation"
                    },
                    {
                        "name": "90",
                        "description": "Rotating 90 degrees"
                    },
                    {
                        "name": "180",
                        "description": "Rotating 180 degrees"
                    },
                    {
                        "name": "270",
                        "description": "Rotating 270 degrees"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::handlers::capture_into::argjson",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Recording Window": {
            "type": "form",
            "capture_into": "camera.recording_window",
            "properties": {
                "text": "Values ranging from 0-23:",
                "width": 70,
                "items": [
                    {
                        "name": "Starting Hour:",
                        "length": 2,
                        "configures": "start"
                    },
                    {
                        "name": "Ending Hour:",
                        "length": 2,
                        "configures": "end"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::screens::form::save",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Resolution": {
            "type": "form",
            "capture_into": "camera.resolution",
            "properties": {
                "width": 70,
                "text": "Value in pixels:",
                "items": [
                    {
                        "name": "Width:",
                        "length": 5,
                        "configures": "width"
                    },
                    {
                        "name": "Height:",
                        "length": 5,
                        "configures": "height"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::screens::form::save",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Encoding": {
            "type": "form",
            "capture_into": "camera.encoding",
            "properties": {
                "width": 70,
                "text": "\\\Zb\\\Z1Warning\\\Zn: Do not edit unless you understand encoding configuration.",
                "items": [
                    {
                        "name": "Level:",
                        "length": 5,
                        "configures": "level"
                    },
                    {
                        "name": "Profile:",
                        "length": 10,
                        "configures": "profile"
                    },
                    {
                        "name": "Bitrate:",
                        "length": 20,
                        "configures": "bitrate"
                    }
                ]
            },
            "handlers": {
                "capture_into": "wheel::screens::form::save",
                "ok": "wheel::handlers::cancel"
            }
        },
        "Remove": {
            "type": "checklist",
            "capture_into": "removal",
            "dialog": {
                "title": "Removal Options",
                "cancel-label": "Back",
                "extra-button": true,
                "extra-label": "Select All",
                "ok-label": "Continue"
            },
            "properties": {
                "text": "Select actions to perform:",
                "items": [
                    {
                        "name": "Device Client Service",
                        "description": "Remove the AWS IoT Device Client service",
                        "configures": "removal.device_client_service"
                    },
                    {
                        "name": "Device Client Configuration",
                        "description": "Removes the AWS IoT Device Client configuration",
                        "configures": "removal.device_client_config"
                    },
                    {
                        "name": "Device Client Software",
                        "description": "Removes the AWS IoT Device Client software",
                        "configures": "removal.device_client_software"
                    },
                    {
                        "name": "Pinthesky Service",
                        "description": "Disables and removes the Pinthesky service",
                        "configures": "removal.pinthesky_service"
                    },
                    {
                        "name": "IoT Certificates",
                        "description": "Disables and removes AWS IoT Certificates",
                        "configures": "removal.cloud_certs"
                    },
                    {
                        "name": "IoT Thing",
                        "description": "Removes AWS IoT Thing",
                        "configures": "removal.cloud_thing"
                    },
                    {
                        "name": "Pinthesky Configuration",
                        "description": "Removes pinthesky configuration and content",
                        "configures": "removal.pinthesky_config"
                    },
                    {
                        "name": "Pinthesky Software",
                        "description": "Removes pinthesky software",
                        "configures": "removal.pinthesky_software"
                    }
                ]
            },
            "next": "Removal Confirm",
            "handlers": {
                "capture_into": "wheel::screens::checklist::field",
                "extra": "pits::setup::remove::toggle"
            }
        },
        "Removal Confirm": {
            "type": "yesno",
            "properties": {
                "text": "Continue removing?"
            },
            "next": "Removal Gauge"
        },
        "Removal Gauge": {
            "type": "custom",
            "entrypoint": "pits::setup::remove::device",
            "managed": true,
            "properties": {
                "width": 70,
                "actions": []
            },
            "next": "Removal Results"
        },
        "Removal Results": {
            "type": "textbox",
            "dialog": {
                "exit-label": "Back"
            },
            "properties": {
                "text": "pits.remove.log"
            },
            "next": "Main Menu"
        },
        "Command Settings": {
            "type": "hub",
            "clear_history": true,
            "dialog": {
                "cancel-label": "Back"
            },
            "properties": {
                "items": [
                    {
                        "name": "Assume Root",
                        "description": "Ability to the assume root privileges"
                    },
                    {
                        "name": "Connection",
                        "description": "Configure connection details to the RPi device"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::screens::hub::selection"
            },
            "back": "Main Menu"
        },
        "View": {
            "type": "gauge",
            "managed": true,
            "properties": {
                "width": 70,
                "actions": [
                    {
                        "label": "Checking software installation...",
                        "action": "pits::setup::inspect::software"
                    },
                    {
                        "label": "Checking software configuration...",
                        "action": "pits::setup::inspect::configuration"
                    },
                    {
                        "label": "Checking cloud configuration...",
                        "action": "pits::setup::inspect::cloud"
                    },
                    {
                        "label": "Checking file configuration...",
                        "action": "pits::setup::inspect::files"
                    },
                    {
                        "label": "Checking remote storage configuration...",
                        "action": "pits::setup::inspect::storage"
                    },
                    {
                        "label": "Checking pinthesky service...",
                        "action": "pits::setup::inspect::service"
                    },
                    {
                        "label": "Checking AWS device client service...",
                        "action": "pits::setup::inspect::device_client"
                    }
                ]
            },
            "next": "View Results"
        },
        "View Results": {
            "type": "textbox",
            "dialog": {
                "exit-label": "Back"
            },
            "properties": {
                "text": "pits.inspection.log"
            },
            "next": "Main Menu"
        },
        "Assume Root": {
            "type": "yesno",
            "capture_into": "assume_root",
            "properties": {
                "text": "Can I assume root privileges?\nCurrent Value: [\\\Zb\$state.assume_root\\\ZB]"
            },
            "handlers": {
                "capture_into": "wheel::handlers::flag",
                "ok": "wheel::handlers::cancel",
                "cancel": [
                    "wheel::handlers::flag",
                    "wheel::handlers::cancel"
                ]
            },
            "next": "Command Settings"
        },
        "Connection": {
            "type": "input",
            "capture_into": "machine_host",
            "properties": {
                "text": "Enter SSH host details:\\nie: \\\Zbpi@hostname\\\ZB"
            },
            "next": "Connection Validate"
        },
        "Connection Validate": {
            "type": "gauge",
            "dialog": {
                "title": "Connection Test"
            },
            "properties": {
                "width": 70,
                "actions": [
                    "pits::setup::connection::validate"
                ]
            },
            "next": "Connection Validate Result"
        },
        "Connection Validate Result": {
            "type": "custom",
            "capture_into": "valid_connection",
            "dialog": {
                "title": "Connection Test [\\\Zb\\\Z2+\\\Zn]"
            },
            "properties": {
                "width": 70,
                "height": 7
            },
            "entrypoint": "pits::setup::connection::result",
            "next": "Main Menu",
            "handlers": {
                "capture_into": "wheel::handlers::flag"
            }
        },
        "Error": {
            "type": "msgbox",
            "dialog": {
                "title": "Error [\\\Zb\\\Z1X\\\Zn]",
                "ok-label": "Back"
            },
            "properties": {
                "text": "The application encountered an unexpected error.\\nPlease see \\\Zbpitsctl.log\\\ZB for more details."
            },
            "handlers": {
                "ok": "wheel::handlers::cancel"
            }
        },
        "Exit": {
            "type": "yesno",
            "dialog": {
                "clear": true
            },
            "properties": {
                "width": 48,
                "height": 6,
                "text": "Are you sure you want to exit?"
            }
        }
    }
}
EOF