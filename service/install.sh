#!/bin/bash

AWS_CLI=$(which aws)
DEFAULT_THING_NAME="PinTheSkyThing"
DEFAULT_THING_GROUP="PinTheSkyGroup"
DEFAULT_ROLE_ALIAS_NAME="PinTheSkyRoleAlias"
DEFAULT_ROLE_NAME="PinTheSkyRole"
DEFAULT_THING_POLICY_NAME="PinTheSkyThingPolicy"
DEFAULT_BUCKET_PREFIX="motion_videos"
DEFAULT_EVENT_INPUT="/usr/share/pinthesky/events/input.json"
DEFAULT_EVENT_OUTPUT="/usr/share/pinthesky/events/output.json"
DEFAULT_CONFIGURE_INPUT="/usr/share/pinthesky/configuration/input.json"
DEFAULT_CONFIGURE_OUTPUT="/usr/share/pinthesky/configuration/output.json"
DEFAULT_COMBINE_DIR="/usr/share/pinthesky/motion_videos"
DEFAULT_BUFFER="15"
DEFAULT_SENSITIVITY="10"
DEFAULT_FRAMERATE="20"
DEFAULT_ROTATION="0"
DEFAULT_RESOLUTION="640x480"
RAW_CONTENT_URL="https://raw.githubusercontent.com/philcali/pits-device/main"
INSTALL_VERSION="git+https://github.com/philcali/pits-device.git"
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

Welcome to the guided install of the pinthesky device!
"
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

associate_thing() {
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
        wget -O $CA_CERT $ROOT_CA_LOCATION
        CERT_OUTPUT=$(aws iot create-keys-and-certificate --set-as-active --public-key-outfile $PUB_KEY_FILE --private-key-outfile $PRV_KEY_FILE --certificate-pem-outfile $CERT_FILE)
        printf $GREEN "Created AWS IoT Thing Certificates for $THING_NAME"

        CERT_ARN=$(echo $CERT_OUTPUT | jq '.certificateArn' | tr -d '"')
        aws iot attach-thing-principal --thing-name $THING_NAME --principal $CERT_ARN
        printf $GREEN "Attached certificate to $THING_NAME"
        aws iot attach-policy --policy-name $THING_POLICY --target $CERT_ARN
        printf $GREEN "Attached $THING_POLICY to $CERT_ARN"
        if [ "$CLIENT_MACHINE" = 'y' ]; then    
            mkdir certs
            for FILE in "$CERT_FILE $PRV_KEY_FILE $PUB_KEY_FILE $CA_CERT"; do
                mv $FILE certs/
            done
            scp -r certs $HOST_MACHINE:~/certs
            $COMMAND_PREFIX mv certs /etc/pinthesky/certs
            printf $GREEN "Sent $CERT_FILE, $PRV_KEY_FILE, and $CA_CERT to /etc/pinthesky/certs"
            rm -rf certs
            set_env_val "$COMMAND_PREFIX" "CA_CERT" "/etc/pinthesky/certs/$CA_CERT"
            set_env_val "$COMMAND_PREFIX" "THING_CERT" "/etc/pinthesky/certs/$CERT_FILE"
            set_env_val "$COMMAND_PREFIX" "THING_KEY" "/etc/pinthesky/certs/$PRV_KEY_FILE"
        fi
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

install_pinthesky() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3

    PINTHESKY_VERSION=$($COMMAND_PREFIX which pinthesky)
    if [ -z $PINTHESKY_VERSION ]; then
        $($COMMAND_PREFIX pip3 install $INSTALL_VERSION)
        printf $GREEN "Successfully installed pinthesky."
    else
        echo "A version of pinthesky is already installed at $PINTHESKY_VERSION. To upgrade run:"
        printf $PMPT "python3 -m pip install --upgrade pinthesky"
    fi

    $COMMAND_PREFIX mkdir -p /etc/pinthesky
    printf $GREEN "Created /etc/pinthesky"

    download_resource pinthesky.env
    local env_location="/etc/pinthesky/pinthesky.env"
    if [ $CLIENT_MACHINE = 'y' ]; then
        scp pinthesky.env $HOST_MACHINE:~/
    fi
    $COMMAND_PREFIX mv pinthesky.env $env_location
    printf $GREEN "Copied pinthesky.env to ${env_location}"
    rm pinthesky.env
    printf $GREEN "Successfully installed pinthesky software"
}

configure_storage() {
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
        set_env_val "$COMMAND_PREFIX" "BUCKET_NAME" "$BUCKET_NAME"
        set_env_val "$COMMAND_PREFIX" "BUCKET_PREFIX" "$BUCKET_PREFIX"

        ACCOUNT=$(aws sts get-caller-identity | jq '.Account' | tr -d '"')
        POLICY_NAME="$BUCKET_NAME-policy"
        POLICY_ARN="arn:aws:iam::$ACCOUNT:policy/$POLICY_NAME"
        IAM_POLICY_OUTPUT=$(aws iam get-policy --policy-arn $POLICY_ARN 2>/dev/null)
        if [ $(echo $?) -ne 0 ]; then
            download_resource default.iam.policy.json
            sed -i "s|BUCKET_NAME|$BUCKET_NAME|" default.iam.policy.json        
            sed -i "s|BUCKET_PREFIX|$BUCKET_PREFIX|" default.iam.policy.json        

            IAM_POLICY_OUTPUT=$(aws iam create-policy --policy-name $POLICY_NAME --policy-document file://default.iam.policy.json)
            rm default.iam.policy.json 
        fi
        IAM_POLCY_ARN=$(echo $IAM_POLICY_OUTPUT | jq '.Policy.Arn' | tr -d '"')
    fi
}

configure_events() {
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

configure_camera() {
    local COMMAND_PREFIX=$1

    printf $PMPT "Set the camera combination directory [$DEFAULT_COMBINE_DIR]:"
    read -r COMBINE_DIR
    COMBINE_DIR=${COMBINE_DIR:-$DEFAULT_COMBINE_DIR}
    $COMMAND_PREFIX mkdir -p ${COMBINE_DIR}
    printf $GREEN "Created $COMBINE_DIR"
    set_env_val "$COMMAND_PREFIX" "COMBINE_DIR" "${COMBINE_DIR}"
    for CAMERA_FIELD in buffer sensitivity framerate rotation resolution; do
        VAR_NME="DEFAULT_${CAMERA_FIELD^^}"
        VAR_VAL=${!VAR_NME}
        printf $PMPT "Set the camera $CAMERA_FIELD field [$VAR_VAL]:"
        read -r USER_INPUT
        USER_INPUT=${USER_INPUT:-$VAR_VAL}
        set_env_val "$COMMAND_PREFIX" "${CAMERA_FIELD^^}" "$VAR_VAL"
    done
    printf $PMPT "Would you like to set a recording window? [y/n]"
    read -r SET_WINDOW
    if [ "$SET_WINDOW" = 'y' ]; then
        START_HOUR=0
        END_HOUR=0
        while [ $START_HOUR -ge $END_HOUR ] || [ $END_HOUR -gt 23 ] || [ $START_HOUR -lt 0 ]; do
            echo "The valid range must be between 0-23 and the ending hour must be greater than the starting hour."
            printf $PMPT "When should the camera start recording? [0-23]"
            read -r START_HOUR
            printf $PMPT "When should the camera end the recording? [0-23]"
            read -r END_HOUR
        done
        RECORDING_WINDOW="$START_HOUR-$END_HOUR"
        set_env_val "$COMMAND_PREFIX" "RECORDING_WINDOW" "$RECORDING_WINDOW"
    fi
}

configure_service() {
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

configure_cloud_connection() {
    local AWS_CLI=$1
    local CLIENT_MACHINE=$2
    local HOST_MACHINE=$3
    local COMMAND_PREFIX=$4

    if [ -z $AWS_CLI ]; then
        echo "The AWS CLI is not installed. Skipping storage and AWS IoT Thing association."
    else
        printf $PMPT "Associate to an AWS IoT Thing? [y/n]"
        read -r ASSOCIATE_THING
        if [ $ASSOCIATE_THING = 'y' ]; then
            configure_storage
            printf $GREEN "Successfully configured storage"
            associate_thing "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX" "$IAM_POLCY_ARN"
        fi
    fi
}

configure_device_client() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3
    # TODO: move the device client as an arch build and import it
    printf $RED "WARNING: Building the AWS IoT Device Client may take a very long time to complete on smaller devices!"
    printf $PMPT "Install the AWS IoT Device Client? [y/n] "
    read -r INSTALL_DEVICE_CLIENT
    if [ "$INSTALL_DEVICE_CLIENT" = 'y' ]; then
        download_resource install_device_client.sh
        download_resource aws-iot-device-client.json
        chmod +x install_device_client.sh
        if [ $CLIENT_MACHINE = 'y' ]; then
            scp install_device_client.sh $HOST_MACHINE:~/install_device_client.sh
            scp aws-iot-device-client.json $HOST_MACHINE:~/aws-iot-device-client.json
        fi
        $COMMAND_PREFIX ./install_device_client.sh
        $COMMAND_PREFIX rm install_device_client.sh aws-iot-device-client.json
        printf $GREEN "Installed aws-iot-device-client as a service"
    fi
}

banner

printf $PMPT "Are you running the install from a client machine? [y/n]"
read -r CLIENT_MACHINE
HOST_MACHINE=""
COMMAND_PREFIX=""
if [ "$CLIENT_MACHINE" = 'y' ]; then
    TEST_OUTPUT=""
    while [ -z "$TEST_OUTPUT" ]; do
        printf $PMPT "Machine host, ex: pi@hostname.com"
        read -r HOST_MACHINE
        COMMAND_PREFIX="ssh -o ConnectTimeout=3 $HOST_MACHINE"
        TEST_OUTPUT=$($COMMAND_PREFIX echo hello world 2>/dev/null)
        if [ $(echo $?) -ne 0 ]; then
            printf $RED "Could not communicate to $HOST_MACHINE, is that correct?"
        fi
    done
    printf $GREEN "Successfully connected to $HOST_MACHINE"
fi

printf $PMPT "Can I assume root privileges to install things? [y/n]"
read -r ASSUME_ROOT
if [ "$ASSUME_ROOT" = 'y' ]; then
    COMMAND_PREFIX="$COMMAND_PREFIX sudo"
fi

DRYRUN=${DRYRUN:-0}
if [ $DRYRUN -eq 1 ]; then
    COMMAND_PREFIX="echo $COMMAND_PREFIX"
fi

# TODO: add commands for a manage script, post install
install_pinthesky "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
configure_cloud_connection "$AWS_CLI" "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
configure_events "$COMMAND_PREFIX"
echo "Alomst done! Let's take a look at the camera configuration itself."
configure_camera "$COMMAND_PREFIX"
configure_device_client "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
configure_service "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
printf $GREEN "Finished configuring pinthesky! Enjoy!"