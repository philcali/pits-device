#!/usr/bin/env bash

cat << EOF > defaults.json
{
    "thingName": "PinTheSkyThing",
    "thingGRoup": "PinTheSkyGroup",
    "roleAlias": "PinTheSkyRoleAlias",
    "roleName": "PinTheSkyRole",
    "thingPolicy": "PinTheSkyThingPolicy",
    "bucket": {
        "videoPrefix": "motion_videos",
        "imagePrefix": "capture_images"
    },
    "paths": {
        "eventInput": "/usr/share/pinthesky/events/input.json",
        "eventOoutput": "/usr/share/pinthesky/events/output.json",
        "configurationInput": "/usr/share/pinthesky/configuration/input.json",
        "configurationOutput": "/usr/share/pinthesky/configuration/output.json",
        "jobHandlers": "/usr/share/pinthesky/job/handlers",
        "combinePath": "/usr/share/pinthesky/motion_videos",
        "capturePath": "/usr/share/pinthesky/capture_images"
    },
    "camera": {
        "sensitivity": 10,
        "framerate": 20,
        "rotation": 0,
        "buffer": 15,
        "resolution": "640x480",
        "encodingLevel": 4,
        "encodingProfile": "high",
        "healthInterval": 3600
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
                "capture_into": "pits::setup::connection::root"
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