#!/usr/bin/env bash

cat << EOF > defaults.json
{
    "cloud": {
        "thingName": "PinTheSkyThing",
        "thingGroup": "PinTheSkyGroup",
        "roleAlias": "PinTheSkyRoleAlias",
        "roleName": "PinTheSkyRole",
        "thingPolicy": "PinTheSkyThingPolicy"
    },
    "bucket": {
        "videoPrefix": "motion_videos",
        "imagePrefix": "capture_images"
    },
    "device": {
        "paths": {
            "eventInput": "/usr/share/pinthesky/events/input.json",
            "eventOutput": "/usr/share/pinthesky/events/output.json",
            "configurationInput": "/usr/share/pinthesky/configuration/input.json",
            "configurationOutput": "/usr/share/pinthesky/configuration/output.json",
            "jobHandlers": "/usr/share/pinthesky/job/handlers",
            "combine": "/usr/share/pinthesky/motion_videos",
            "capture": "/usr/share/pinthesky/capture_images"
        },
        "healthInterval": 3600
    },
    "camera": {
        "sensitivity": 10,
        "framerate": 20,
        "rotation": 0,
        "buffer": 15,
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
    "assumeRoot": true,
    "machineHost": "pi@192.168.1.237"
}
EOF

trap "rm -rf defaults.json" EXIT

cat << EOF | dialog-wheel -d defaults.json -l pitsctl.log -L DEBUG
{
    "version": "1.0.0",
    "dialog": {
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
            "directory": "$PWD",
            "file": "workflow.sh"
        }
    ],
    "start": "Welcome",
    "exit": "Exit",
    "error": "Error",
    "screens": {
        "Welcome": {
            "type": "msgbox",
            "properties": {
                "text": "\\nWelcome to the \\\ZbPi in the Sky\\\ZB Setup Wizard.\\nLet's get started."
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
            "handlers": {
                "ok": "wheel::screens::hub::selection"
            },
            "back": "Main Menu"
        },
        "Cloud Configuration": {
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
                        "configures": "thingName"
                    },
                    {
                        "name": "Thing Policy:",
                        "length": 60,
                        "configures": "thingPolicy"
                    },
                    {
                        "name": "Thing Group:",
                        "length": 60,
                        "configures": "thingGroup"
                    },
                    {
                        "name": "Role Name:",
                        "length": 60,
                        "configures": "roleName"
                    },
                    {
                        "name": "Role Alias:",
                        "length": 60,
                        "configures": "roleAlias"
                    }
                ]
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
                        "configures": "eventInput"
                    },
                    {
                        "name": "Event Output:",
                        "length": 80,
                        "max": 256,
                        "configures": "eventOutput"
                    },
                    {
                        "name": "Configuration Input:",
                        "length": 80,
                        "max": 256,
                        "configures": "configurationInput"
                    },
                    {
                        "name": "Configuration Output:",
                        "length": 80,
                        "max": 256,
                        "configures": "configurationOutput"
                    },
                    {
                        "name": "Job Handlers:",
                        "length": 80,
                        "max": 256,
                        "configures": "jobHandlers"
                    },
                    {
                        "name": "Combine Directory:",
                        "length": 80,
                        "max": 256,
                        "configures": "combine"
                    },
                    {
                        "name": "Image Capture Directory:",
                        "length": 80,
                        "max": 256,
                        "configures": "capture"
                    }
                ]
            },
            "handlers": {
                "ok": "wheel::handlers::cancel"
            }
        },
        "Health Check Interval": {
            "type": "range",
            "capture_into": "device.healthInterval",
            "properties": {
                "min": 60,
                "max": 86400,
                "default": "\$state.device.healthInterval",
                "text": "Rate in seconds:",
                "width": 70
            },
            "handlers": {
                "capture_into": "wheel::handlers::capture_into::argjson",
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
        "Resolution": {
            "type": "form",
            "capture_into": "camera.resolution",
            "properties": {
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
            "capture_into": "assumeRoot",
            "properties": {
                "text": "Can I assume root privileges?"
            },
            "handlers": {
                "capture_into": "wheel::handlers::flag"
            },
            "next": "Command Settings"
        },
        "Connection": {
            "type": "input",
            "capture_into": "machineHost",
            "properties": {
                "text": "Enter SSH host details:\\nie \\\Zbpi@hostname\\\ZB"
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
            "dialog": {
                "title": "Connection Test [\\\Zb\\\Z2+\\\Zn]"
            },
            "properties": {
                "width": 70,
                "height": 7
            },
            "entrypoint": "pits::setup::connection::result",
            "next": "Command Settings"
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
                "text": "Are you sure you want to exit?"
            }
        }
    }
}
EOF