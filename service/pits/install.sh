#!/usr/bin/env bash

INSTALL_LOG="pits.install.log"
CONFIGURED_IAM_POLICY="configured.iam.policy.arn"
IOT_DEVICE_CLIENT_REPO="https://github.com/philcali/aws-iot-device-client"

ROOT_CA_LOCATION="https://www.amazontrust.com/repository/AmazonRootCA1.pem"
CERT_FILE="thing.cert.pem"
PRV_KEY_FILE="thing.key"
PUB_KEY_FILE="thing.pub"
CA_CERT="AmazonRootCA1.pem"


function pits::setup::install::device() {
    pits::setup::truncate "$INSTALL_LOG" || return 254
    pits::setup::truncate "$PITS_ENV" || return 254
    local task_index
    local entry
    local name
    local install_tasks=()
    [ "$(wheel::state::get "software.install")" != "Nothing" ] && install_tasks+=(pinthesky_software)
    install_tasks+=(pinthesky_camera)
    install_tasks+=(pinthesky_storage)
    install_tasks+=(pinthesky_cloud)
    install_tasks+=(pinthesky_config)
    for entry in $(wheel::state::get "client | to_entries | .[]" -c); do
        name=$(wheel::json::get "$entry" 'key')
        [ "$(wheel::json::get "$entry" 'value')" = 'false' ] && continue
        install_tasks+=("device_client::${name/install_/}")
    done
    [ "$(wheel::state::get "software.service")" != "Nothing" ] && install_tasks+=(pinthesky_service)
    for task_index in "${!install_tasks[@]}"; do
        local action_name="${install_tasks[$task_index]}"
        screen="$(wheel::json::set "$screen" "properties.actions[$task_index].label" "Installing ${action_name//_/ }...")"
        screen="$(wheel::json::set "$screen" "properties.actions[$task_index].action" "pits::setup::install::$action_name")"
    done
    wheel::screens::gauge
}

function pits::setup::install::pinthesky_config() {
    local entry
    local name
    local path
    for entry in $(wheel::state::get "device.paths | to_entries | .[]" -c); do
        name=$(wheel::json::get "$entry" 'key')
        path=$(wheel::json::get "$entry" 'value')
        local basedir="$path"
        [[ "$path" = *".json" ]] && basedir=$(dirname "$path")
        pits::setup::invoke "mkdir -p $basedir"
        [[ "$path" = *".json" ]] && pits::setup::invoke "touch $path"
        echo "Manifested ${name^^}: $path"
        echo "${name^^}=$path" >> "$PITS_ENV"
    done
    echo "HEALTH_INTERVAL=$(wheel::state::get "device.health_interval")" >> "$PITS_ENV"
    # TODO: make a form for this
    echo "SHADOW_UPDATE=empty" >> "$PITS_ENV"
    pits::setup::invoke mkdir -p /etc/pinthesky
    pits::setup::cp "$PITS_ENV" /etc/pinthesky/pinthesky.env
    echo "[+] Installed pinthesky.env" >> "$INSTALL_LOG"
}

function pits::setup::install::device_client::software() {
    if pits::setup::invoke which aws-iot-device-client > /dev/null; then
        echo "[+] AWS IoT Device Client Software is already installed" >> "$INSTALL_LOG"
        return 0
    fi
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    cat << EOF > install_device_client.sh
#!/usr/bin/env bash
echo "Installing Dependencies"
apt-get update -q
apt-get install -yq \
    git \
    cmake \
    g++ \
    cpp \
    libssl-dev

echo "Building AWS IoT Device Client"
# START HACK: temporary until this feature on mainline
git clone $IOT_DEVICE_CLIENT_REPO
pushd aws-iot-device-client
git remote add awslabs https://github.com/awslabs/aws-iot-device-client
git pull --tags awslabs
# END HACK
mkdir build
pushd build
cmake ../
cmake --build . --target aws-iot-device-client

mv aws-iot-device-client /sbin/aws-iot-device-client

popd
popd
mkdir -p $JOBS_DIR
cp aws-iot-device-client/sample-job-handlers/*.sh "$JOBS_DIR/"
rm -rf aws-iot-device-client
EOF
    chmod +x install_device_client.sh
    pits::setup::cp install_device_client.sh
    pits::setup::invoke ./install_device_client.sh
    echo "[+] Installed AWS IoT Device Client Software" >> "$INSTALL_LOG"
}

function pits::setup::install::device_client::configuration() {
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"

    local job_handlers
    job_handlers=$(wheel::state::get 'client.install_job_handlers')
    cat << EOF > aws-iot-device-client.conf
{
    "endpoint": "$DATA_ENDPOINT",
    "cert": "$THING_CERT",
    "key": "$THING_KEY",
    "root-ca": "$CA_CERT",
    "thing-name": "$THING_NAME",
    "logging": {
        "level": "INFO",
        "type": "STDOUT"
    },
    "jobs": {
        "enabled": $job_handlers,
        "handler-directory": "$JOBS_DIR"
    },
    "tunneling": {
        "enabled": false
    },
    "samples": {
        "pub-sub": {
            "enabled": true,
            "publish-topic": "pinthesky/events/output",
            "publish-file": "$EVENT_OUTPUT",
            "subscribe-topic": "pinthesky/events/$THING_NAME/input",
            "subscribe-file": "$EVENT_INPUT",
            "publish-on-change": true
        }
    },
    "sample-shadow": {
        "enabled": true,
        "shadow-name": "pinthesky",
        "shadow-input-file": "$CONFIGURE_INPUT",
        "shadow-output-file": "$CONFIGURE_OUTPUT"
    }
}
EOF

    pits::setup::invoke mkdir -p /etc/aws-iot-device-client
    pits::setup::cp aws-iot-device-client.conf /etc/aws-iot-device-client/

    for replacement in THING_CERT EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT JOBS_DIR; do
        if [ $replacement = 'CONFIGURE_INPUT' ] || [ $replacement = 'CONFIGURE_OUTPUT' ]; then
            pits::setup::invoke chmod 600 "${!replacement}"
        fi
        if [ $replacement = 'EVENT_INPUT' ] || [ $replacement = 'EVENT_OUTPUT' ]; then
            pits::setup::invoke chmod 745 "$(dirname "${!replacement}")"
            pits::setup::invoke chmod 600 "${!replacement}"
        fi
        if [ $replacement = 'THING_CERT' ]; then
            pits::setup::invoke chmod 644 "${!replacement}"
        fi
        echo "Adjusted AWS IoT Device Client config: ${!replacement}"
    done

    pits::setup::invoke chmod 700 /etc/pinthesky/certs
    pits::setup::invoke chmod 745 /etc/aws-iot-device-client
    pits::setup::invoke chmod 640 /etc/aws-iot-device-client/aws-iot-device-client.conf
    echo "[+] Installed AWS IoT Device Client Configuration" >> "$INSTALL_LOG"
}

function pits::setup::install::device_client::job_handlers() {
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    cat << EOF > upgrade-pinthesky.sh
#!/bin/bash

USER=\$1
shift 1
VERSION=\${1:-""}

echo "Upgrading pinthesky software"
if [ -z "\$VERSION" ] || [ "\$VERSION" = "\\\$version" ]; then
    python3 -m pip install --upgrade pinthesky
else
    python3 -m pip uninstall -y pinthesky
    python3 -m pip install "pinthesky\$VERSION"
fi
EOF
    pits::setup::invoke mkdir -p "$JOBS_DIR"
    pits::setup::cp upgrade-pinthesky.sh "$JOBS_DIR/"
    pits::setup::invoke chmod 700 "$JOBS_DIR/*.sh"
    echo "[+] Installed AWS IoT Device Client Job Handlers" >> "$INSTALL_LOG"
}

function pits::setup::install::device_client::service() {
    cat << EOF > aws-iot-device-client.service
[Unit]
Description=AWS IoT Device Client
Wants=network-online.target
After=network.target network-online.target

[Service]
ExecStart=/sbin/aws-iot-device-client --config-file /etc/aws-iot-device-client/aws-iot-device-client.conf

[Install]
WantedBy=multi-user.target
EOF
    pits::setup::cp aws-iot-device-client.service /etc/systemd/system/
    pits::setup::invoke systemctl enable aws-iot-device-client
    pits::setup::invoke systemctl restart aws-iot-device-client
    echo "[+] Installed AWS IoT Device Client Service" >> "$INSTALL_LOG"
}

function pits::setup::install::pinthesky_software() {
    {
        if ! pits::setup::invoke which pip3 > /dev/null; then
            pits::setup::invoke apt-get -yq install python3-pip > /dev/null && echo "[+] Installed pip"
        fi
        if ! pits::setup::invoke which pinthesky > /dev/null; then
            if pits::setup::invoke pip3 install pinthesky > /dev/null; then
                echo "[+] Installed pinthesky"
            else
                echo "[-] Failed to install pinthesky"
            fi
        else
            echo "[+] Already installed pinthesky"
        fi
    } >> "$INSTALL_LOG"
}

function pits::setup::install::create_policy() {
    local policy_name=$1
    local image_prefix=$2
    local video_prefix=$3
    local bucket_name=$4
    cat << EOF > default.iam.policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject*",
                "s3:Abort*"
            ],
            "Resource": [
                "arn:aws:s3:::$bucket_name/$video_prefix/*",
                "arn:aws:s3:::$bucket_name/$image_prefix/*"
            ]
        }
    ]
}
EOF
    aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document file://default.iam.policy.json \
        --query Role.Arn \
        --output text
}

function pits::setup::install::pinthesky_storage() {
    local bucket_name
    local image_prefix
    local video_prefix
    local policy_name
    local account
    local partition
    partition=$(aws ssm get-parameter \
        --name /aws/service/global-infrastructure/current-region/partition \
        --query Parameter.Value \
        --output text)
    account=$(aws sts get-caller-identity --query Account --output text)
    bucket_name=$(wheel::state::get 'storage.bucket')
    policy_name=$(wheel::state::get 'storage.policy_name')
    image_prefix=$(wheel::state::get 'storage.image_prefix')
    video_prefix=$(wheel::state::get 'storage.video_prefix')
    if ! aws s3api create-bucket --bucket "$bucket_name"; then
        echo "[-] Failed to create storage bucket $bucket_name" >> "$INSTALL_LOG"
        return 254
    fi
    {
        echo "BUCKET_NAME=$bucket_name"
        echo "BUCKET_PREFIX=$video_prefix"
        echo "BUCKET_IMAGE_PREFIX=$image_prefix"
    } >> "$PITS_ENV"
    {
        aws iam get-policy \
            --policy-arn "arn:$partition:iam::$account:policy/$policy_name" \
            --query Policy.Arn \
            --output text 2>/dev/null || \
        pits::setup::install::create_policy \
            "$policy_name" \
            "$image_prefix" \
            "$video_prefix" \
            "$bucket_name" || return 254
    } >> "$CONFIGURED_IAM_POLICY"
}

function pits::setup::install::create_role() {
    cat << EOF > defauly.iam.role.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "credentials.iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]   
}
EOF
    aws iam create-role \
        --role-name "$1" \
        --assume-role-policy-document file://default.iam.role.json 2>/dev/null
}

function pits::setup::install::create_role_alias() {
    local alias_name=$1
    local role_arn=$2
    aws iot create-role-alias \
        --role-alias "$alias_name" \
        --role-arn "$role_arn" \
        --output text \
        --query roleAliasArn
}

function pits::setup::install::create_thing_policy() {
    local policy_name=$1
    local role_alias_arn=$2
    local partition
    local region
    local account
    partition=$(aws ssm get-parameter \
        --name /aws/service/global-infrastructure/current-region/partition \
        --query Parameter.Value \
        --output text)
    region=$(aws ssm get-parameter \
        --name /aws/service/global-infrastructure/current-region \
        --query Parameter.Value \
        --output text)
    account=$(aws sts get-caller-identity --query Account --output text)
    cat << EOF > default.policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iot:Connect",
            "Resource": "arn:$partition:iot:$region:$account:client/\${iot:Connection.Thing.ThingName}"
        },
        {
            "Effect": "Allow",
            "Action": "iot:Publish",
            "Resource": [
                "arn:$partition:iot:$region:$account:topic/pinthesky/events/output",
                "arn:$partition:iot:$region:$account:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/shadow/name/pinthesky/*",
                "arn:$partition:iot:$region:$account:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iot:Subscribe",
            "Resource": [
                "arn:$partition:iot:$region:$account:topicfilter/pinthesky/events/\${iot:Connection.Thing.ThingName}/input",
                "arn:$partition:iot:$region:$account:topicfilter/\$aws/things/\${iot:Connection.Thing.ThingName}/shadow/name/pinthesky*",
                "arn:$partition:iot:$region:$account:topicfilter/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iot:Receive",
            "Resource": [
                "arn:$partition:iot:$region:$account:topic/pinthesky/events/\${iot:Connection.Thing.ThingName}/input",
                "arn:$partition:iot:$region:$account:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/shadow/name/pinthesky/*",
                "arn:$partition:iot:$region:$account:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iot:AssumeRoleWithCertificate",
            "Resource": "$role_alias_arn"
        }
    ]
}
EOF
    aws iot create-policy \
        --policy-name "$policy_name" \
        --policy-document file://default.policy.json && \
    echo "[+] Created ThingPolicy $policy_name" >> "$INSTALL_LOG"
}

function pits::setup::install::pinthesky_cloud() {
    local thing_name
    local thing_policy
    local thing_group
    local role_alias
    local role_name
    local role_arn
    local aws_output
    local create_certs
    thing_name=$(wheel::state::get 'cloud.thing_name')
    thing_group=$(wheel::state::get 'cloud.thing_group')
    thing_policy=$(wheel::state::get 'cloud.thing_policy')
    role_alias=$(wheel::state::get 'cloud.role_alias')
    role_name=$(wheel::state::get 'cloud.role_name')
    create_certs=$(wheel::state::get 'cloud.create_certificates')
    if aws iot describe-thing --thing-name "$thing_name" >/dev/null 2>&1; then
        echo "[+] $thing_name already exists." >> "$INSTALL_LOG"
    else
        aws iot create-thing --thing-name "$thing_name" >/dev/null 2>&1 || {
            echo "[-] Failed to create $thing_name" >> "$INSTALL_LOG"
            return 254
        }
        echo "[+] Created $thing_name" >> "$INSTALL_LOG"
    fi
    echo "Assocaited thing $thing_name"
    echo "THING_NAME=$thing_name" >> "$PITS_ENV"
    aws_output=$(aws iam get-role --role-name "$role_name" 2>/dev/null) || \
        aws_output=$(pits::setup::install::create_role "$role_name") || \
        { 
            echo "[-] Failed to create role $role_name" >> "$INSTALL_LOG"
            return 254
        }
    role_arn=$(wheel::json::get "$aws_output" 'Role.Arn')
    echo "Associated role $role_arn"
    # Attach IAM policy
    [ -f "$CONFIGURED_IAM_POLICY" ] && \
        {
            aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query AttachedPolicies[].PolicyArn \
                --output text | grep "$(<"$CONFIGURED_IAM_POLICY")" || \
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$(<"$CONFIGURED_IAM_POLICY")" && \
            echo "[+] Attached role policy $(<"$CONFIGURED_IAM_POLICY")" >> "$INSTALL_LOG"
        } >/dev/null
    aws_output=$(aws iot describe-role-alias \
        --role-alias "$role_alias" \
        --query roleAliasDescription.roleAliasArn \
        --output text 2>/dev/null) || \
        aws_output=$(pits::setup::install::create_role_alias "$role_alias" "$role_arn") || \
        {
            echo "[-] Failed to create role alias $role_alias" >> "$INSTALL_LOG"
            return 254
        }
    echo "ROLE_ALIAS=$role_alias" >> "$PITS_ENV"
    echo "Associated role alias $role_alias"
    # Attach thing policy
    aws_output=$(aws iot get-policy --policy-name "$thing_policy" 2>/dev/null) || \
        aws_output=$(pit::setup::install::create_thing_policy "$thing_policy" "$aws_output") || \
        {
            echo "[-] Failed to create ThingPolicy $thing_policy" >> "$INSTALL_LOG"
            return 254
        }
    if [ "$create_certs"  == 'true' ]; then
        mkdir certs
        curl -q -o "certs/$CA_CERT" "$ROOT_CA_LOCATION" 2>/dev/null
        aws_output=$(aws iot create-keys-and-certificate \
            --set-as-active \
            --public-key-outfile "certs/$PUB_KEY_FILE" \
            --private-key-outfile "certs/$PRV_KEY_FILE" \
            --certificate-pem-outfile "certs/$CERT_FILE" \
            --output text \
            --query 'certificateArn') || return 254
        pits::setup::invoke mkdir -p /etc/pinthesky
        pits::setup::cp certs /etc/pinthesky/certs
        {
            echo "CA_CERT=/etc/pinthesky/certs/$CA_CERT"
            echo "THING_CERT=/etc/pinthesky/certs/$CERT_FILE"
            echo "THING_KEY=/etc/pinthesky/certs/$PRV_KEY_FILE"
        } >> "$PITS_ENV"
        echo "Created $thing_name certificates"
        aws iot attach-thing-principal \
            --thing-name "$thing_name" \
            --principal "$aws_output" || return 254
        aws iot attach-policy \
            --policy-name "$thing_policy" \
            --target "$aws_output" || return 254
        echo "Associated $aws_output to $thing_name"
    fi
    if ! aws iot describe-thing-group --thing-group-name "$thing_group" >/dev/null 2>&1; then
        aws iot create-thing-group --thing-group-name "$thing_group"
        echo "[+] Created ThingGroup $thing_group" >> "$INSTALL_LOG"
    fi
    aws iot add-thing-to-thing-group --thing-group-name "$thing_group" --thing-name "$thing_name" || {
        echo "[-] Failed to add $thing_name to ThingGroup $thing_group" >> "$INSTALL_LOG"
    }
    echo "CREDENTIALS_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:CredentialProvider --query endpointAddress --output text)" >> "$PITS_ENV"
    echo "DATA_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:data-ats --query endpointAddress --output text)" >> "$PITS_ENV"
}

function pits::setup::install::pinthesky_camera() {
    local entry
    for entry in $(wheel::state::get "camera | to_entries | .[]" -c); do
        local name
        local value
        local enc_elem
        local enc_name
        name=$(wheel::json::get "$entry" "key")
        case "$name" in
        resolution)
            value=$(wheel::json::get "$entry" 'value | (.width | tostring) + "x" + (.height | tostring)')
            echo "RESOLUTION=$value" >> "$PITS_ENV"
            ;;
        recording_window)
            value=$(wheel::json::get "$entry" 'value | (.start | tostring) + "-" + (.end | tostring)')
            echo "RECORDING_WINDOW=$value" >> "$PITS_ENV"
            ;;
        encoding)
            for enc_elem in $(wheel::json::get "$entry" 'value | to_entries | .[]' -c); do
                enc_name=$(wheel::json::get "$enc_elem" 'key')
                value=$(wheel::json::get "$enc_elem" 'value')
                echo "ENCODING_${enc_name^^}=$value" >> "$PITS_ENV"
            done
            ;;
        *)
            value=$(wheel::json::get "$entry" 'value')
            echo "${name^^}=$value" >> "$PITS_ENV";;
        esac
    done
    echo "[+] Written pinthesky camera config" >> "$INSTALL_LOG"
}

function pits::setup::install::pinthesky_service() {
    cat << EOF > pinthesky.service
[Unit]
Description=Pi In the Sky Device Service

[Install]
WantedBy=multi-user.target
Alias=pinthesky.service

[Service]
EnvironmentFile=/etc/pinthesky/pinthesky.env
ExecStart=/usr/local/bin/pinthesky \
    --buffer \$BUFFER \
    --sensitivity \$SENSITIVITY \
    --combine-dir \$COMBINE_DIR \
    --rotation \$ROTATION \
    --resolution \$RESOLUTION \
    --framerate \$FRAMERATE \
    --event-input \$EVENT_INPUT \
    --event-output \$EVENT_OUTPUT \
    --configure-input \$CONFIGURE_INPUT \
    --configure-output \$CONFIGURE_OUTPUT \
    --bucket-name \$BUCKET_NAME \
    --bucket-prefix \$BUCKET_PREFIX \
    --bucket-image-prefix \$BUCKET_IMAGE_PREFIX \
    --capture-dir \$CAPTURE_DIR \
    --role-alias \$ROLE_ALIAS \
    --thing-name \$THING_NAME \
    --thing-cert \$THING_CERT \
    --thing-key \$THING_KEY \
    --ca-cert \$CA_CERT \
    --credentials-endpoint \$CREDENTIALS_ENDPOINT \
    --recording-window \$RECORDING_WINDOW \
    --encoding-bitrate \$ENCODING_BITRATE \
    --encoding-level \$ENCODING_LEVEL \
    --encoding-profile \$ENCODING_PROFILE \
    --shadow-update \$SHADOW_UPDATE \
    --health-interval \$HEALTH_INTERVAL
Restart=always
EOF

    pits::setup::cp pinthesky.service /etc/systemd/system/ || {
        echo "[-] Failed to install service" >> "$INSTALL_LOG"
        return 1
    }
    pits::setup::invoke systemctl enable pinthesky || {
        echo "[-] Already enabled pinthesky service" >> "$INSTALL_LOG"
    }
    pits::setup::invoke systemctl restart pinthesky || {
        echo "[-] Failed to start pinthesky service" >> "$INSTALL_LOG"
    }

    echo "[+] Enabled pinthesky service" >> "$INSTALL_LOG"
}

touch "$INSTALL_LOG"
wheel::events::add_clean_up "rm $INSTALL_LOG"
wheel::events::add_clean_up "rm -f install_device_client.sh"
wheel::events::add_clean_up "rm -f default.policy.json"
wheel::events::add_clean_up "rm -f default.iam.policy.json"
wheel::events::add_clean_up "rm -f upgrade-pinthesky.sh"
wheel::events::add_clean_up "rm -f pinthesky.service"
wheel::events::add_clean_up "rm -f aws-iot-device-client.conf"
wheel::events::add_clean_up "rm -f aws-iot-device-client.service"
wheel::events::add_clean_up "rm -f default.iam.role.json"
wheel::events::add_clean_up "rm -rf certs"
wheel::events::add_clean_up "rm -f $CONFIGURED_IAM_POLICY"