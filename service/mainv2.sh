#!/usr/bin/env bash

VERSION=0.7.1
RAW_CONTENT_URL="https://raw.githubusercontent.com/philcali/pits-device/main"
ASSUME_ROOT="false"
MACHINE_HOST=""
PROGRAM=""
LOG="INFO"

download_resource() {
    local RESOURCE_FILE=$1
    local path="service/pits/$RESOURCE_FILE"

    if [ ! -f "$path" ]; then
        # Pull from CDN
        wget -O "$RESOURCE_FILE" "$RAW_CONTENT_URL/$path"
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
    local script_file="$self_dir/pits/$import_file"
    if [ ! -f "$script_file" ] && download_resource "$import_file"; then
        if [ ! -d "$(dirname "$script_file")" ]; then
            mkdir -p "$(dirname "$script_file")"
        fi
        mv "$import_file" "$script_file"
    fi
    echo "$script_file"
}

# TODO: improve this for updating and installing
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
    popd && rm -rf dialog-wheel
}

usage() {
    echo "Usage: $(basename "$0") - v$VERSION: Install or manage pinthesky software"
    echo "  -h,--help:    Prints out this help message"
    echo "  -m,--host:    Client machine connection details"
    echo "  -t,--text:    Enable a no color, text only view of the application"
    echo "  -r,--root:    Assume root permission for management"
    echo "  -l,--level:   Changes the logging verbosity for $(basename "$0")"
    echo "  -v,--version: Prints the version and exists"
}

parse_args() {
    while [ -n "$*" ]; do
        local param=$1
        case "$param" in
        -r|--root)
            ASSUME_ROOT="true";;
        -t|--text)
            PROGRAM='program: wheel::dialog::app';;
        -m|--host)
            shift
            MACHINE_HOST=$1;;
        -l|--level)
            shift
            LOG=$1;;
        -v|--version)
            echo "$VERSION" && return 1;;
        -h|--help)
            usage && return 1;;
        esac
        shift
    done
}

parse_args "$@" || exit 0

cat << EOF > defaults.yaml
cloud:
  thing_name: "PinTheSkyThing"
  thing_group: "PinTheSkyGroup"
  role_alias: "PinTheSkyRoleAlias"
  role_name: "PinTheSkyRole"
  thing_policy: "PinTheSkyThingPolicy"
  create_certificates: true
storage:
  bucket: "$USER-pinthesky-storage"
  policy_name: "$USER-pinthesky-storage-policy"
  video_prefix: "motion_videos"
  image_prefix: "capture_images"
software:
  install: "Current"
  service: "Nothing"
client:
  install_software: true
  install_job_handlers: true
  install_configuration: true
  install_service: true
device:
  paths:
    event_input: "/usr/share/pinthesky/events/input.json"
    event_output: "/usr/share/pinthesky/events/output.json"
    configure_input: "/usr/share/pinthesky/configuration/input.json"
    configure_output: "/usr/share/pinthesky/configuration/output.json"
    jobs_dir: "/usr/share/pinthesky/job/handlers"
    combine_dir: "/usr/share/pinthesky/motion_videos"
    capture_dir: "/usr/share/pinthesky/capture_images"
  health_interval: 3600
  log_level: "INFO"
camera:
  sensitivity: 10
  framerate: 20
  rotation: 0
  buffer: 15
  recording_window:
    start: 0
    end: 23
  resolution:
    width: 640
    height: 480
  encoding:
    level: 4,
    profile: "high"
    bitrate: "17000000"
assume_root: $ASSUME_ROOT
machine_host: "$MACHINE_HOST"
EOF

trap "rm -rf defaults.yaml" EXIT

command -v dialog-wheel > /dev/null || install_dialog_wheel || exit 1
common_script=$(import_function "$0" "_common.sh")
inspect_script=$(import_function "$0" "inspect.sh")
remove_script=$(import_function "$0" "remove.sh")
install_script=$(import_function "$0" "install.sh")

START_SCREEN="Welcome"
[ -n "$MACHINE_HOST" ] && START_SCREEN="Connection Validate"

cat << EOF | dialog-wheel --yaml -d defaults.yaml -l pitsctl.log -L "$LOG" -s "$START_SCREEN"
dialog:
  $PROGRAM
  backtitle: Pi In The Sky - Setup Wizard
  colors: true
error: Error
exit: Exit
handlers:
  esc: wheel::handlers::cancel
includes:
- file: $common_script
- file: $inspect_script
- file: $remove_script
- file: $install_script
properties:
  aspect: 20
screens:
  AWS IoT Configuration:
    capture_into: cloud
    dialog:
      cancel-label: Back
      extra-button: true
      extra-label: Validate
    handlers:
      capture_into: wheel::screens::form::save
      ok: wheel::handlers::cancel
    properties:
      items:
      - configures: thing_name
        length: 60
        name: 'Thing Name:'
      - configures: thing_policy
        length: 60
        name: 'Thing Policy:'
      - configures: thing_group
        length: 60
        name: 'Thing Group:'
      - configures: role_name
        length: 60
        name: 'Role Name:'
      - configures: role_alias
        length: 60
        name: 'Role Alias:'
    type: form
  Assume Root:
    capture_into: assume_root
    handlers:
      cancel:
      - wheel::handlers::flag
      - wheel::handlers::cancel
      capture_into: wheel::handlers::flag
      ok: wheel::handlers::cancel
    next: Command Settings
    properties:
      text: 'Can I assume root privileges?

        Current Value: [\Zb\$state.assume_root\ZB]'
    type: yesno
  Buffer:
    capture_into: camera.buffer
    dialog:
      cancel-label: Back
    handlers:
      capture_into: wheel::handlers::capture_into::argjson
      ok: wheel::handlers::cancel
    properties:
      default: \$state.camera.buffer
      max: 60
      min: 1
      text: 'Seconds for motion recording:'
      width: 70
    type: range
  Camera Configuration:
    dialog:
      cancel-label: Back
    handlers:
      ok: wheel::screens::hub::selection
    properties:
      items:
      - description: Seconds to buffer recorded video
        name: Buffer
      - description: Motion sensitivity
        name: Sensitivity
      - description: The framerate of the recording
        name: Framerate
      - description: Rotation of the camera
        name: Rotation
      - description: The hours when the camera records motion
        name: Recording Window
      - description: The resolution of the camera
        name: Resolution
      - description: Configure the encoding profile
        name: Encoding
    type: hub
  Cloud Configuration:
    back: Install
    clear_history: true
    dialog:
      cancel-label: Back
      ok-label: Configure
    handlers:
      ok: wheel::screens::hub::selection
    properties:
      items:
      - description: Creates and configures AWS IoT Associations
        name: AWS IoT Configuration
      - description: Creates and associates AWS IoT Certificates
        name: Create Certificates
    type: hub
  Command Settings:
    back: Main Menu
    clear_history: true
    dialog:
      cancel-label: Back
    handlers:
      ok: wheel::screens::hub::selection
    properties:
      items:
      - description: Ability to the assume root privileges
        name: Assume Root
      - description: Configure connection details to the RPi device
        name: Connection
    type: hub
  Configuration Paths:
    capture_into: device.paths
    dialog:
      cancel-label: Back
    handlers:
      capture_into: wheel::screens::form::save
      ok: wheel::handlers::cancel
    properties:
      box_height: 8
      items:
      - configures: event_input
        length: 80
        max: 256
        name: 'Event Input:'
      - configures: event_output
        length: 80
        max: 256
        name: 'Event Output:'
      - configures: configure_input
        length: 80
        max: 256
        name: 'Configuration Input:'
      - configures: configure_output
        length: 80
        max: 256
        name: 'Configuration Output:'
      - configures: jobs_dir
        length: 80
        max: 256
        name: 'Job Handlers:'
      - configures: combine_dir
        length: 80
        max: 256
        name: 'Combine Directory:'
      - configures: capture_dir
        length: 80
        max: 256
        name: 'Image Capture Directory:'
    type: form
  Connection:
    capture_into: machine_host
    next: Connection Validate
    properties:
      text: 'Enter SSH host details:

        ie: \Zbpi@hostname\ZB'
    type: input
  Connection Validate:
    dialog:
      title: Connection Test
    next: Connection Validate Result
    properties:
      actions:
      - pits::setup::connection::validate
      width: 70
    type: gauge
  Connection Validate Result:
    capture_into: valid_connection
    dialog:
      title: Connection Test [\Zb\Z2+\Zn]
    entrypoint: pits::setup::connection::result
    handlers:
      capture_into: wheel::handlers::flag
    next: Main Menu
    properties:
      height: 7
      width: 70
    type: custom
  Create Certificates:
    capture_into: cloud.create_certificates
    handlers:
      cancel:
      - wheel::handlers::flag
      - wheel::handlers::cancel
      capture_into: wheel::handlers::flag
      ok: wheel::handlers::cancel
    next: Cloud Configuration
    properties:
      text: 'Create new AWS IoT Certificates?

        Current Value: [\Zb\$state.cloud.create_certificates\ZB]'
    type: yesno
  Device Client:
    capture_into: client
    handlers:
      capture_into: wheel::screens::checklist::field
      ok: wheel::handlers::cancel
    properties:
      items:
      - configures: client.install_software
        description: Installs the device client software
        name: Software
      - configures: client.install_job_handlers
        description: Installs the job handlers
        name: Jobs
      - configures: client.install_configuration
        description: Installs the device client configuration
        name: Configuration
      - configures: client.install_service
        description: Installs the systemd service unit
        name: Service
      text: 'AWS Device Client installation actions:'
    type: checklist
  Device Configuration:
    dialog:
      cancel-label: Back
    handlers:
      ok: wheel::screens::hub::selection
    properties:
      items:
      - description: File and folder locations for pinthesky
        name: Configuration Paths
      - description: Rate in seconds for post health checks
        name: Health Check Interval
      - description: Logging severity on the device 
        name: Log Level
    type: hub
  Device Software:
    capture_into: software.install
    handlers:
      ok: wheel::handlers::cancel
    properties:
      items:
      - description: Only installs if a version is not installed
        name: Current
      - description: Installs or updates to latest version
        name: Latest
      - description: Do not attempt an installation
        name: Nothing
      text: 'Select behavior:'
    type: radiolist
  Log Level:
    capture_into: device.log_level
    handlers:
      ok: wheel::handlers::cancel
    properties:
      text: "Logging severity"
      items:
      - description: Logs fatal messages only
        name: FATAL
      - description: Logs error messages in addition to above
        name: ERROR
      - description: Logs warning messages in addition to above
        name: WARN
      - description: Logs information messages in addition to above
        name: INFO
      - description: Logs debugging messages in addition to above
        name: DEBUG
    type: radiolist
  Encoding:
    capture_into: camera.encoding
    handlers:
      capture_into: wheel::screens::form::save
      ok: wheel::handlers::cancel
    properties:
      items:
      - configures: level
        length: 5
        name: 'Level:'
      - configures: profile
        length: 10
        name: 'Profile:'
      - configures: bitrate
        length: 20
        name: 'Bitrate:'
      text: '\Zb\Z1Warning\Zn: Do not edit unless you understand encoding configuration.'
      width: 70
    type: form
  Error:
    dialog:
      ok-label: Back
      title: Error [\Zb\Z1X\Zn]
    handlers:
      ok: wheel::handlers::cancel
    properties:
      text: 'The application encountered an unexpected error.

        Please see \Zbpitsctl.log\ZB for more details.'
    type: msgbox
  Exit:
    dialog:
      clear: true
    properties:
      height: 6
      text: Are you sure you want to exit?
      width: 48
    type: yesno
  Framerate:
    capture_into: camera.framerate
    dialog:
      cancel-label: Back
    handlers:
      capture_into: wheel::handlers::capture_into::argjson
      ok: wheel::handlers::cancel
    properties:
      default: \$state.camera.framerate
      max: 20
      min: 10
      text: 'Recording framerate:'
      width: 70
    type: range
  Health Check Interval:
    capture_into: device.health_interval
    handlers:
      capture_into: wheel::handlers::capture_into::argjson
      ok: wheel::handlers::cancel
    properties:
      default: \$state.device.health_interval
      max: 86400
      min: 60
      text: 'Rate in seconds:'
      width: 70
    type: range
  Install:
    back: Main Menu
    clear_history: true
    dialog:
      cancel-label: Back
      extra-button: true
      extra-label: Install
      ok-label: Configure
    handlers:
      extra: wheel::handlers::ok
      ok: wheel::screens::hub::selection
    next: Review and Install
    properties:
      items:
      - description: Creates and configures AWS resources
        name: Cloud Configuration
      - description: Manages remote storage of images and videos
        name: Storage Configuration
      - description: Installs pinthesky software
        name: Device Software
      - description: Installs and configures pinthesky
        name: Device Configuration
      - description: Configures camera settings
        name: Camera Configuration
      - description: Installs and configures AWS IoT device client
        name: Device Client
      - description: Installs and configures systemd services
        name: Service Configuration
    type: hub
  Install Gauge:
    entrypoint: pits::setup::install::device
    managed: true
    next: Install Results
    properties:
      actions: []
      width: 70
    type: custom
  Install Results:
    dialog:
      exit-label: Back
    next: Main Menu
    properties:
      text: pits.install.log
    type: textbox
  Main Menu:
    clear_history: true
    dialog:
      cancel-label: Exit
    handlers:
      ok: wheel::screens::hub::selection
    properties:
      items:
      - description: Inspect a pinthesky installation
        name: View
      - description: Install and configures pinthesky
        name: Install
      - description: Removes pinthesky from a device
        name: Remove
      - description: Configure command execution settings
        name: Command Settings
    type: hub
  Recording Window:
    capture_into: camera.recording_window
    handlers:
      capture_into: wheel::screens::form::save
      ok: wheel::handlers::cancel
    properties:
      items:
      - configures: start
        length: 2
        name: 'Starting Hour:'
      - configures: end
        length: 2
        name: 'Ending Hour:'
      text: 'Values ranging from 0-23:'
      width: 70
    type: form
  Removal Confirm:
    next: Removal Gauge
    properties:
      text: Continue removing?
    type: yesno
  Removal Gauge:
    entrypoint: pits::setup::remove::device
    managed: true
    next: Removal Results
    properties:
      actions: []
      width: 70
    type: custom
  Removal Results:
    dialog:
      exit-label: Back
    next: Main Menu
    properties:
      text: pits.remove.log
    type: textbox
  Remove:
    capture_into: removal
    dialog:
      cancel-label: Back
      extra-button: true
      extra-label: Select All
      ok-label: Continue
      title: Removal Options
    handlers:
      capture_into: wheel::screens::checklist::field
      extra: pits::setup::remove::toggle
    next: Removal Confirm
    properties:
      items:
      - configures: removal.device_client_service
        description: Remove the AWS IoT Device Client service
        name: Device Client Service
      - configures: removal.device_client_config
        description: Removes the AWS IoT Device Client configuration
        name: Device Client Configuration
      - configures: removal.device_client_software
        description: Removes the AWS IoT Device Client software
        name: Device Client Software
      - configures: removal.pinthesky_service
        description: Disables and removes the Pinthesky service
        name: Pinthesky Service
      - configures: removal.cloud_certs
        description: Disables and removes AWS IoT Certificates
        name: IoT Certificates
      - configures: removal.cloud_thing
        description: Removes AWS IoT Thing
        name: IoT Thing
      - configures: removal.pinthesky_config
        description: Removes pinthesky configuration and content
        name: Pinthesky Configuration
      - configures: removal.pinthesky_software
        description: Removes pinthesky software
        name: Pinthesky Software
      text: 'Select actions to perform:'
    type: checklist
  Resolution:
    capture_into: camera.resolution
    handlers:
      capture_into: wheel::screens::form::save
      ok: wheel::handlers::cancel
    properties:
      items:
      - configures: width
        length: 5
        name: 'Width:'
      - configures: height
        length: 5
        name: 'Height:'
      text: 'Value in pixels:'
      width: 70
    type: form
  Review and Install:
    next: Install Gauge
    properties:
      text: Are you ready to begin the install?
    type: yesno
  Rotation:
    capture_into: camera.rotation
    handlers:
      capture_into: wheel::handlers::capture_into::argjson
      ok: wheel::handlers::cancel
    properties:
      items:
      - description: No rotation
        name: '0'
      - description: Rotating 90 degrees
        name: '90'
      - description: Rotating 180 degrees
        name: '180'
      - description: Rotating 270 degrees
        name: '270'
      text: 'Select the rotation degrees:'
    type: radiolist
  Sensitivity:
    capture_into: camera.sensitivity
    dialog:
      cancel-label: Back
    handlers:
      capture_into: wheel::handlers::capture_into::argjson
      ok: wheel::handlers::cancel
    properties:
      default: \$state.camera.sensitivity
      max: 50
      min: 1
      text: 'Motion sensitivity (higher the value, more aggressive the motion):'
      width: 70
    type: range
  Service Configuration:
    capture_into: software.service
    handlers:
      ok: wheel::handlers::cancel
    properties:
      items:
      - description: Installs and enables the pinthesky systemd service
        name: Enable
      - description: Installs the pinthesky systemd service
        name: Install
      - description: Does not install the pinthesky systemd service
        name: Nothing
      text: 'Configure pinthesky service action:'
    type: radiolist
  Storage Configuration:
    capture_into: storage
    dialog:
      cancel-label: Back
    handlers:
      capture_into: wheel::screens::form::save
      ok: wheel::handlers::cancel
    properties:
      items:
      - configures: bucket
        length: 64
        name: 'Bucket:'
      - configures: policy_name
        length: 60
        name: 'Role Policy:'
      - configures: video_prefix
        length: 64
        name: 'Motion Video Prefix:'
      - configures: image_prefix
        length: 64
        name: 'Image Capture Prefix:'
    type: form
  View:
    managed: true
    next: View Results
    properties:
      actions:
      - action: pits::setup::inspect::software
        label: Checking software installation...
      - action: pits::setup::inspect::configuration
        label: Checking software configuration...
      - action: pits::setup::inspect::cloud
        label: Checking cloud configuration...
      - action: pits::setup::inspect::files
        label: Checking file configuration...
      - action: pits::setup::inspect::storage
        label: Checking remote storage configuration...
      - action: pits::setup::inspect::service
        label: Checking pinthesky service...
      - action: pits::setup::inspect::device_client
        label: Checking AWS device client service...
      width: 70
    type: gauge
  View Results:
    dialog:
      exit-label: Back
    next: Main Menu
    properties:
      text: pits.inspection.log
    type: textbox
  Welcome:
    next: Main Menu
    properties:
      height: 6
      text: 'Welcome to the \ZbPi in the Sky\ZB Setup Wizard.

        Let''s get started.'
      width: 48
    type: msgbox
start: Welcome
version: 1.0.0
EOF
