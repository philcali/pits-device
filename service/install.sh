#!/bin/bash

set_env_val() {
    local COMMAND_PREFIX=$1
    local VAR_NME=$2
    local VAR_VAL=$3
    local prompt_message=""

    SED_INPUT="'s|${VAR_NME}=\"\"|${VAR_NME}=\"${VAR_VAL}\"|'"
    $COMMAND_PREFIX sed -i $SED_INPUT /etc/pinthesky/pinthesky.env
    printf -v prompt_message $GREEN "Updated pinthesky.env $VAR_NME to $VAR_VAL"
    echo "$prompt_message"
}

__install_pinthesky() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3
    local env_location="/etc/pinthesky/pinthesky.env"

    PINTHESKY_VERSION=$($COMMAND_PREFIX which pinthesky)
    if [ -z "$PINTHESKY_VERSION" ]; then
        echo "Could not detect a version of pinthesky, installing..."
        $COMMAND_PREFIX pip3 install $INSTALL_VERSION
        printf $GREEN "Successfully installed pinthesky."
    else
        echo "A version of pinthesky is already installed at $PINTHESKY_VERSION. To upgrade run:"
        printf $PMPT "python3 -m pip install --upgrade pinthesky"
    fi

    printf $PMPT "Copy with a clean $env_location? [y/n]"
    read -r CLEAN_ENV
    if [ "$CLEAN_ENV" = 'y' ]; then
        $COMMAND_PREFIX mkdir -p /etc/pinthesky
        printf $GREEN "Created /etc/pinthesky"
        download_resource pinthesky.env
        if [ "$CLIENT_MACHINE" = 'y' ]; then
            scp pinthesky.env $HOST_MACHINE:~/
        fi
        $COMMAND_PREFIX mv pinthesky.env $env_location
        printf $GREEN "Copied pinthesky.env to ${env_location}"
        rm pinthesky.env
    fi
    printf $GREEN "Successfully installed pinthesky software"
}

__configure_storage() {
    local prompt_message=""
    local local_var=""
    local result=""
    local last_result=0
    IAM_POLCY_ARN=""
    printf -v prompt_message $PMPT "Assign an S3 bucket to store motion video capture? [y/n]"
    read -p "$prompt_message" ASSIGN_BUCKET
    if [ "$ASSIGN_BUCKET" = 'y' ]; then
        while [ -z "$result" ] || [ $last_result -ne 0 ]; do
            printf -v prompt_message $PMPT "Bucket name [$USER-pinthesky-storage]:"
            read -p "$prompt_message" local_var
            local_var=${local_var:-"$USER-pinthesky-storage"}
            result=$(aws s3api create-bucket --bucket $local_var 2>&1)
            last_result=$(echo $?)
            if [ $last_result -ne 0 ]; then
                printf -v prompt_message $RED $result
                echo "$prompt_message"
            fi
        done
        BUCKET_NAME=$local_var
        printf -v prompt_message $PMPT "Bucket storage prefix [$DEFAULT_BUCKET_PREFIX]:"
        read -p "$prompt_message" BUCKET_PREFIX
        BUCKET_PREFIX=${BUCKET_PREFIX:-$DEFAULT_BUCKET_PREFIX}

        printf -v prompt_message $PMPT "Bucket image storage prefix [$DEFAULT_BUCKET_IMAGE_PREFIX]:"
        read -p "$prompt_message" BUCKET_IMAGE_PREFIX
        BUCKET_IMAGE_PREFIX=${BUCKET_IMAGE_PREFIX:-$DEFAULT_BUCKET_IMAGE_PREFIX}

        set_env_val "$COMMAND_PREFIX" "BUCKET_NAME" "$BUCKET_NAME"
        set_env_val "$COMMAND_PREFIX" "BUCKET_PREFIX" "$BUCKET_PREFIX"
        set_env_val "$COMMAND_PREFIX" "BUCKET_IMAGE_PREFIX" "$BUCKET_IMAGE_PREFIX"

        ACCOUNT=$(aws sts get-caller-identity | jq '.Account' | tr -d '"')
        POLICY_NAME="$BUCKET_NAME-policy"
        POLICY_ARN="arn:aws:iam::$ACCOUNT:policy/$POLICY_NAME"
        IAM_POLICY_OUTPUT=$(aws iam get-policy --policy-arn $POLICY_ARN 2>/dev/null)
        if [ $(echo $?) -ne 0 ]; then
            download_resource default.iam.policy.json
            sed -i "s|BUCKET_NAME|$BUCKET_NAME|" default.iam.policy.json
            sed -i "s|BUCKET_PREFIX|$BUCKET_PREFIX|" default.iam.policy.json 
            sed -i "s|BUCKET_IMAGE_PREFIX|$BUCKET_IMAGE_PREFIX|" default.iam.policy.json 

            IAM_POLICY_OUTPUT=$(aws iam create-policy --policy-name $POLICY_NAME --policy-document file://default.iam.policy.json)
            rm default.iam.policy.json
        fi
        IAM_POLCY_ARN=$(echo $IAM_POLICY_OUTPUT | jq '.Policy.Arn' | tr -d '"')
        printf $GREEN "Successfully configured storage"
    fi
}

__associate_thing() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3
    local IAM_POLCY_ARN=$4

    printf $PMPT "Enter the Thing name [$DEFAULT_THING_NAME]: "
    read -r THING_NAME
    THING_NAME=${THING_NAME:-$DEFAULT_THING_NAME}
    THING_OUTPUT=$(aws iot describe-thing --thing-name $THING_NAME 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        THING_OUTPUT=$(aws iot create-thing --thing-name $THING_NAME)
        printf $GREEN "Created AWS IoT Thing $THING_NAME"
    else
        printf $GREEN "$THING_NAME already exists. Configuring for this device."
    fi

    set_env_val "$COMMAND_PREFIX" "THING_NAME" "$THING_NAME"
    printf $PMPT "Enter the IAM Role name [$DEFAULT_ROLE_NAME]: "
    read -r ROLE_NAME
    ROLE_NAME=${ROLE_NAME:-$DEFAULT_ROLE_NAME}
    ROLE_OUTPUT=$(aws iam get-role --role-name $ROLE_NAME 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        download_resource default.iam.role.json
        ROLE_OUTPUT=$(aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://default.iam.role.json)
        rm default.iam.role.json
        printf $GREEN "Created IAM role $ROLE_NAME"
    else 
        printf $GREEN "$ROLE_NAME already exists. Configuring for this device."
    fi

    if [ ! -z "$IAM_POLCY_ARN" ]; then
        EXISTING_ATTACHMENT=$(aws iam list-attached-role-policies --role-name $ROLE_NAME | jq '.AttachedPolicies[]' | tr -d '"' | grep "$IAM_POLCY_ARN")
        if [ -z "$EXISTING_ATTACHMENT" ]; then
            aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn ${IAM_POLCY_ARN}
            printf $GREEN "Attached $IAM_POLCY_ARN to $ROLE_NAME"
        else
            printf $GREEN "Policy $IAM_POLCY_ARN was already attached to $ROLE_NAME"
        fi
    fi

    ROLE_ARN=$(echo $ROLE_OUTPUT | jq '.Role.Arn' | tr -d '"')
    printf $PMPT "Enter the Role Alias name [$DEFAULT_ROLE_ALIAS_NAME]: "
    read -r ROLE_ALIAS
    ROLE_ALIAS=${ROLE_ALIAS:-$DEFAULT_ROLE_ALIAS_NAME}
    ROLE_ALIAS_OUTPUT=$(aws iot describe-role-alias --role-alias $ROLE_ALIAS 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        ROLE_ALIAS_OUTPUT=$(aws iot create-role-alias --role-alias $ROLE_ALIAS --role-arn $ROLE_ARN)
        ROLE_ALIAS_ARN=$(echo $ROLE_ALIAS_OUTPUT | jq '.roleAliasArn' | tr -d '"')
        printf $GREEN "Created role alias $ROLE_ALIAS associated to $ROLE_ARN"
    else
        ROLE_ALIAS_ARN=$(echo $ROLE_ALIAS_OUTPUT | jq '.roleAliasDescription.roleAliasArn' | tr -d '"')
        printf $GREEN "$ROLE_ALIAS already exists. Configuring for this device."
    fi

    set_env_val "$COMMAND_PREFIX" "ROLE_ALIAS" "$ROLE_ALIAS"
    printf $PMPT "Enter the Thing policy name [$DEFAULT_THING_POLICY_NAME]:"
    read -r THING_POLICY
    THING_POLICY=${THING_POLICY:-$DEFAULT_THING_POLICY_NAME}
    POLICY_OUTPUT=$(aws iot get-policy --policy-name $THING_POLICY 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        download_resource default.policy.json
        PARTITION=$(aws ssm get-paramter --name /aws/service/global-infrastructure/current-region/partition | jq '.Parameter.Value' | tr -d '"')
        REGION=$(aws ssm get-parameter --name /aws/service/global-infrastracture/current-region | jq '.Parameter.Value' | tr -d '"')
        ACCOUNT=$(aws sts get-caller-identity | jq '.Account' | tr -d '"')
        for replacement in PARTITION REGION ACCOUNT; do
            sed -i "s|$replacement|${!replacement}|" default.policy.json
        done
        sed -i "s|\"ROLE_ALIAS\"|\"$ROLE_ALIAS_ARN\"|" default.policy.json
        POLICY_OUTPUT=$(aws iot create-policy --policy-name $THING_POLICY --policy-document file://default.policy.json)
        rm default.policy.json
        printf $GREEN "Created AWS IoT Thing Policy $THING_POLICY"
    else
        printf $GREEN "$THING_POLICY already exists. Configuring for this device."
    fi

    printf $PMPT 'Create certificates? [y/n]'
    read -r CREATE_CERTS
    if [ "$CREATE_CERTS" = 'y' ]; then
        mkdir certs
        wget -O certs/$CA_CERT $ROOT_CA_LOCATION
        CERT_OUTPUT=$(aws iot create-keys-and-certificate --set-as-active --public-key-outfile certs/$PUB_KEY_FILE --private-key-outfile certs/$PRV_KEY_FILE --certificate-pem-outfile certs/$CERT_FILE)
        printf $GREEN "Created AWS IoT Thing Certificates for $THING_NAME"

        CERT_ARN=$(echo $CERT_OUTPUT | jq '.certificateArn' | tr -d '"')
        aws iot attach-thing-principal --thing-name $THING_NAME --principal $CERT_ARN
        printf $GREEN "Attached certificate to $THING_NAME"
        aws iot attach-policy --policy-name $THING_POLICY --target $CERT_ARN
        printf $GREEN "Attached $THING_POLICY to $CERT_ARN"
        if [ "$CLIENT_MACHINE" = 'y' ]; then    
            scp -r certs $HOST_MACHINE:~/certs
            rm -rf certs
        fi
        $COMMAND_PREFIX rm -rf /etc/pinthesky/certs
        $COMMAND_PREFIX mv certs /etc/pinthesky/certs
        printf $GREEN "Sent $CERT_FILE, $PRV_KEY_FILE, and $CA_CERT to /etc/pinthesky/certs"
        set_env_val "$COMMAND_PREFIX" "CA_CERT" "/etc/pinthesky/certs/$CA_CERT"
        set_env_val "$COMMAND_PREFIX" "THING_CERT" "/etc/pinthesky/certs/$CERT_FILE"
        set_env_val "$COMMAND_PREFIX" "THING_KEY" "/etc/pinthesky/certs/$PRV_KEY_FILE"
    fi

    printf $PMPT "Add to AWS IoT ThingGroup? [y/n]"
    read -r ADD_TO_GROUP
    if [ "$ADD_TO_GROUP" = 'y' ]; then
        printf $PMPT "ThingGroup to add to [$DEFAULT_THING_GROUP]:"
        read -r THING_GROUP
        THING_GROUP=${THING_GROUP:-$DEFAULT_THING_GROUP}
        THING_GROUP_RESULT=$(aws iot describe-thing-name --thing-group-name $THING_GROUP 2>/dev/null)
        if [ $(echo $?) -ne 0 ]; then
            THING_GROUP_RESULT=$(aws iot create-thing-group --thing-group-name $THING_GROUP)
            printf $GREEN "Created $THING_GROUP"
        fi
        aws iot add-thing-to-thing-group --thing-group-name $THING_GROUP --thing-name $THING_NAME
        printf $GREEN "Associated $THING_NAME to $THING_GROUP"
    fi

    CREDENTIALS_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:CredentialProvider | jq '.endpointAddress' | tr -d '"')
    set_env_val "$COMMAND_PREFIX" "CREDENTIALS_ENDPOINT" "$CREDENTIALS_ENDPOINT"
    DATA_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:data-ats | jq '.endpointAddress' | tr -d '"')
    set_env_val "$COMMAND_PREFIX" "DATA_ENDPOINT" "$DATA_ENDPOINT"
    printf $GREEN "Finishing provisiong $THING_NAME"
}

__configure_cloud_connection() {
    local AWS_CLI=$1
    local CLIENT_MACHINE=$2
    local HOST_MACHINE=$3
    local COMMAND_PREFIX=$4

    if [ -z "$AWS_CLI" ]; then
        echo "The AWS CLI is not installed. Skipping storage and AWS IoT Thing association."
    else
        printf $PMPT "Associate to an AWS IoT Thing? [y/n]"
        read -r ASSOCIATE_THING
        if [ "$ASSOCIATE_THING" = 'y' ]; then
            __configure_storage
            __associate_thing "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX" "$IAM_POLCY_ARN"
        fi
    fi
}

__configure_events() {
    local COMMAND_PREFIX=$1

    for IO_OPTION in event configure; do
        printf $PMPT "The pinthesky service supports file $IO_OPTION handling. Do you want to configure that now? [y/n]"
        read -r CONFIGURE_OPTION
        if [ "$CONFIGURE_OPTION" = 'y' ]; then
            WHAT=${IO_OPTION^^}
            for EVENT_TYPE in input output; do
                VAR_NME="DEFAULT_${WHAT}_${EVENT_TYPE^^}"
                VAR_VAL=${!VAR_NME}
                printf $PMPT "${IO_OPTION^} $EVENT_TYPE location [$VAR_VAL]: "
                read -r EVENT_USER_INPUT
                EVENT_USER_INPUT=${EVENT_USER_INPUT:-$VAR_VAL}
                EVENT_USER_BASE=$(dirname $EVENT_USER_INPUT)
                $COMMAND_PREFIX mkdir -p ${EVENT_USER_BASE}
                printf $GREEN "Created $EVENT_USER_BASE"
                $COMMAND_PREFIX touch ${EVENT_USER_INPUT}
                printf $GREEN "Created empty $EVENT_USER_INPUT"
                set_env_val "$COMMAND_PREFIX" "${WHAT}_${EVENT_TYPE^^}" "$EVENT_USER_INPUT"
            done
        fi
    done
}

__configure_camera() {
    local COMMAND_PREFIX=$1

    printf $PMPT "Configure other camera properties? [y/n]"
    read -r CONFIGURE_CAMERA
    if [ "$CONFIGURE_CAMERA" = 'y' ]; then
        for CAMERA_FIELD in capture combine; do
            VAR_NME="DEFAULT_${CAMERA_FIELD^^}_DIR"
            VAR_VAL=${!VAR_NME}
            printf $PMPT "Set the camera $CAMERA_FIELD directory [$VAR_VAL]:"
            read -r USER_INPUT
            USER_INPUT=${USER_INPUT:-$VAR_VAL}
            $COMMAND_PREFIX mkdir -p $USER_INPUT
            printf $GREEN "Created $USER_INPUT"
            set_env_val "$COMMAND_PREFIX" "${CAMERA_FIELD^^}_DIR" "$USER_INPUT"
        done
        for CAMERA_FIELD in buffer sensitivity framerate rotation resolution encoding_bitrate encoding_level encoding_profile shadow_update; do
            VAR_NME="DEFAULT_${CAMERA_FIELD^^}"
            VAR_VAL=${!VAR_NME}
            printf $PMPT "Set the camera $CAMERA_FIELD field [$VAR_VAL]:"
            read -r USER_INPUT
            USER_INPUT=${USER_INPUT:-$VAR_VAL}
            set_env_val "$COMMAND_PREFIX" "${CAMERA_FIELD^^}" "$USER_INPUT"
        done
        printf $PMPT "Would you like to set a recording window? [y/n]"
        read -r SET_WINDOW
        RECORDING_WINDOW="0-23"
        if [ "$SET_WINDOW" = 'y' ]; then
            START_HOUR=0
            END_HOUR=0
            while [ $START_HOUR -ge $END_HOUR ] || [ $END_HOUR -gt 23 ] || [ $START_HOUR -lt 0 ]; do
                echo "The valid range must be between 0-23 and the ending hour must be greater than the starting hour."
                printf $PMPT "When should the camera start recording? [0]"
                read -r START_HOUR
                printf $PMPT "When should the camera end the recording? [23]"
                read -r END_HOUR
            done
            RECORDING_WINDOW="$START_HOUR-$END_HOUR"
        fi
        set_env_val "$COMMAND_PREFIX" "RECORDING_WINDOW" "$RECORDING_WINDOW"
    fi
}

__configure_device_client() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3
    # TODO: move the device client as an arch build and import it
    printf $PMPT "Install the AWS IoT Device Client? [y/n]"
    read -r INSTALL_DEVICE_CLIENT
    if [ "$INSTALL_DEVICE_CLIENT" = 'y' ]; then
        download_resource install_device_client.sh
        download_resource aws-iot-device-client.json
        chmod +x install_device_client.sh
        if [ "$CLIENT_MACHINE" = 'y' ]; then
            scp install_device_client.sh $HOST_MACHINE:~/install_device_client.sh
            scp aws-iot-device-client.json $HOST_MACHINE:~/aws-iot-device-client.json
            rm install_device_client.sh aws-iot-device-client.json
        fi
        if [ -z "$($COMMAND_PREFIX ls -1 /sbin/aws-iot-device-client)" ]; then
            $COMMAND_PREFIX ./install_device_client.sh -t install_client
        else
            printf $GREEN "The AWS IoT Device Client is already installed."
        fi
        printf $PMPT "Configure AWS IoT Device Client? [y/n]"
        read -r CONFIGURE_DEVICE_CLIENT
        if [ "$CONFIGURE_DEVICE_CLIENT" = 'y' ]; then
            $COMMAND_PREFIX ./install_device_client.sh -t configure_device_client
        fi
        printf $PMPT "Configure Shadow Document update? [empty*/always/never]"
        read -r CONFIGURE_SHADOW_UPDATE
        if [ ! -z "$CONFIGURE_SHADOW_UPDATE" ]; then
            set_env_val "$COMMAND_PREFIX" "SHADOW_UPDATE" "$CONFIGURE_SHADOW_UPDATE"
        else
            set_env_val "$COMMAND_PREFIX" "SHADOW_UPDATE" "$DEFAULT_SHADOW_UPDATE"
        fi
        printf $PMPT "Install the AWS IoT Device Client as a service? [y/n]"
        read -r INSTALL_DEVICE_CLIENT_SERVICE
        if [ "$INSTALL_DEVICE_CLIENT_SERVICE" = 'y' ]; then
            $COMMAND_PREFIX ./install_device_client.sh -t install_service
        fi
        $COMMAND_PREFIX rm install_device_client.sh
        printf $GREEN "Installed aws-iot-device-client as a service"
    fi
}

__configure_service() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3

    printf $PMPT "Install pinthesky as a system service? [y/n]"
    read -r INSTALL_SERVICE
    if [ "$INSTALL_SERVICE" = 'y' ]; then
        download_resource pinthesky.service
        if [ $CLIENT_MACHINE = 'y' ]; then
            scp pinthesky.service $HOST_MACHINE:~/
        fi
        $COMMAND_PREFIX mv pinthesky.service /etc/systemd/system/
        $COMMAND_PREFIX systemctl start pinthesky.service
        $COMMAND_PREFIX systemctl status pinthesky.service
        rm pinthesky.service
        printf $GREEN "Installed and activated pinthesky.service"
    fi
}

install_device() {
    local COMMAND_PREFIX=$1
    local CLIENT_MACHINE=$2
    local HOST_MACHINE=$3
    local AWS_CLI=$(which aws)

    __install_pinthesky "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    __configure_cloud_connection "$AWS_CLI" "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    __configure_events "$COMMAND_PREFIX"
    __configure_camera "$COMMAND_PREFIX"
    __configure_device_client "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    __configure_service "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"

    printf $GREEN "Finished configuring pinthesky! Enjoy!"
}
