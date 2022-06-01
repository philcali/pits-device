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

Welcome to the configuration UI for a pinthesky device!
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

install_pinthesky() {
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

    printf $PMPT "Overwrite with a clean $env_location? [y/n]"
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
        printf $GREEN "Successfully configured storage"
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

    printf $PMPT "Configure other camera properties? [y/n]"
    read -r CONFIGURE_CAMERA
    if [ "$CONFIGURE_CAMERA" = 'y' ]; then
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
            associate_thing "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX" "$IAM_POLCY_ARN"
        fi
    fi
}

configure_device_client() {
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
        read -r INSTALL_DEVICE_CLIENT
        if [ "$INSTALL_DEVICE_CLIENT" = 'y' ]; then
            $COMMAND_PREFIX ./install_device_client.sh -t configure_device_client
        fi
        printf $PMPT "Install the AWS IoT Device Client as a service? [y/n]"
        read -r INSTALL_DEVICE_CLIENT
        if [ "$INSTALL_DEVICE_CLIENT" = 'y' ]; then
            $COMMAND_PREFIX ./install_device_client.sh -t install_service
        fi
        $COMMAND_PREFIX rm install_device_client.sh
        printf $GREEN "Installed aws-iot-device-client as a service"
    fi
}

banner

usage() {
    printf $PMPT "Usage: $(basename $0): Install or manage pinthesky software"
    echo "  -h: Prints out this help message"
    echo "  -t: Define the target, applicable values are 'install', 'remove', 'inspect'"
    echo "  -m: Client machine connection details"
    echo "  -r: Assume root permission for management"
    exit 1
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
    fi
}

install_device() {
    local CLIENT_MACHINE=$1;
    local HOST_MACHINE=$2;
    local COMMAND_PREFIX=$3;

    install_pinthesky "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    configure_cloud_connection "$AWS_CLI" "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    configure_events "$COMMAND_PREFIX"
    configure_camera "$COMMAND_PREFIX"
    configure_device_client "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    configure_service "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    printf $GREEN "Finished configuring pinthesky! Enjoy!"
}

inspect_device() {
    local COMMAND_PREFIX=$1
    local installed_version=""
    local configured_env=""
    local thing_groups=""
    local principals=""
    local role_alias_arn=""
    local pintthesky_service=""
    local device_client_service=""
    local summary=()

    printf $PMPT "Checking the latest version of pinthesky. Please wait a moment..."
    installed_version=$($COMMAND_PREFIX python3 -m pip list | grep "pinthesky")
    if [ -z "$installed_version" ]; then
        printf $RED "Could not find a target version for pinthesky."
        summary+=("$(printf $RED "[-] Installed pinthesky software")")
    else
        printf $GREEN "Found $installed_version"
        summary+=("$(printf $GREEN "[x] Installed pinthesky software")")
    fi

    printf $PMPT "Checking pinthesky configuration. Please wait a moment..."
    configured_env=$($COMMAND_PREFIX cat /etc/pinthesky/pinthesky.env 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        printf $RED "Could not find pre-configured information."
        summary+=("$(printf $RED "[-] Configured pinthesky software")")
    else
        printf $GREEN "Found the following configuration:"
        for line in $configured_env; do
            echo $line
        done
        # Set the values locally for what is found on the device
        eval $configured_env
        summary+=("$(printf $GREEN "[x] Configured pinthesky software")")
    fi

    printf $PMPT "Checking cloud connection. Please wait a moment..."
    if [ -z "$THING_NAME" ]; then
        printf $RED "Device does not appear to be connected to an AWS IoT Thing. Please reconfigure."
        summary+=("$(printf $RED "[-] Cloud connection")")
    else
        if [ -z "$ROLE_ALIAS" ]; then
            printf $RED "Device does not appear to have a role alias. Please reconfigure."
        else
            role_alias_arn=$(aws iot describe-role-alias --role-alias $ROLE_ALIAS | jq '.roleAliasDescription.roleAliasArn' | tr -d '"')
            printf $GREEN "Role alias $ROLE_ALIAS exists."
        fi
        THING_OUTPUT=$(aws iot describe-thing --thing-name $THING_NAME 2>/dev/null)
        if [ $(echo $?) -ne 0 ]; then
            printf $RED "Configured for $THING_NAME, but it does not exist."
        else
            printf $GREEN "Device is configured to $THING_NAME"
            thing_groups=$(aws iot list-thing-groups-for-thing --thing-name $THING_NAME | jq '.thingGroups[].groupName' | tr -d '"')
            for thing_group in $thing_groups; do
                printf $GREEN "$THING_NAME belongs to $thing_group"
            done
            printf $PMPT "Checking for authentication principals. Please wait a moment..."
            principals=$(aws iot list-thing-principals --thing-name $THING_NAME | jq '.principals[]' | tr -d '"')
            if [ -z "$principals" ]; then
                printf $RED "WARNING: there are not attached principals to $THING_NAME. Please reconfigure."
                summary+=("$(printf $RED "[-] Cloud connection, $THING_NAME with no principals")")
            else
                for principal in $principals; do
                    printf $PMPT "Checking cert principal $principal. Please wait a moment..."
                    policies=$(aws iot list-attached-policies --target $principal | jq '.policies[].policyName' | tr -d '"')
                    if [ -z "$policies" ]; then
                        printf $RED "WARNING: there are no policies attached to $principal. Please reconfigure."
                        summary+=("$(printf $RED "[-] Cloud connection, $THING_NAME principal without policies")")
                    else
                        for policy in $policies; do
                            printf $GREEN "Policy $policy is attached to $principal"
                            can_assume=$(aws iot get-policy --policy-name $policy \
                                | jq -r '.policyDocument' \
                                | jq '.Statement[] | (.Action[0] + "," + .Resource[0])' \
                                | grep "iot:AssumeRoleWithCertificate,$role_alias_arn")
                            if [ -z "$can_assume" ]; then
                                printf $RED "WARNING: Policy $policy cannot assume role alias $ROLE_ALIAS."
                                summary+=("$(printf $RED "[-] Cloud connection, $THING_NAME principal without role alias")")
                            else
                                printf $GREEN "Policy $policy can assume role alias $ROLE_ALIAS."
                                summary+=("$(printf $GREEN "[x] Cloud connection")")
                            fi
                        done
                    fi
                done
            fi
        fi
    fi

    printf $PMPT "Checking pinthesky configuration validity. Please wait a moment..."
    for test_file in EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT; do
        $COMMAND_PREFIX cat ${!test_file} > /dev/null
        if [ $(echo $?) -ne 0 ]; then
            printf $RED "WARNING: configuration path ${!test_file} is not valid. Please reconfigure."
        else
            printf $GREEN "Configuration path ${!test_file} is valid and present."
        fi
    done

    printf $PMPT "Checking storage location. Please wait a moment..."
    if [ -z "$BUCKET_NAME" ]; then
        printf $RED "WARNING: Device is not configured to flush to S3. Please reconfigure."
        summary+=("$(printf $RED "[-] Configured remote storage")")
    else
        aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null
        if [ $(echo $?) -ne 0 ]; then
            printf $RED "WARNING: bucket $BUCKET_NAME does not appear to exist."
            summary+=("$(printf $RED "[-] Configured remote storage, does not exist.")")
        else
            printf $GREEN "Bucket $BUCKET_NAME exists."
            summary+=("$(printf $GREEN "[x] Configured remote storage")")
        fi
    fi

    printf $PMPT "Checking pinthesky.service configuration. Please wait a moment..."
    pintthesky_service=$($COMMAND_PREFIX systemctl status pinthesky.service)
    if [ $(echo $?) -eq 4 ]; then
        printf $RED "WARNING: pinthesky.service is not installed. Please reconfigure."
        summary+=("$(printf $RED "[-] Configured systemd pinthesky.service")")
    else
        printf $GREEN "$pintthesky_service"
        summary+=("$(printf $GREEN "[x] Configured systemd pinthesky.service")")
    fi

    printf $PMPT "Checking aws-iot-device-client.service configuration. Please wait a moment..."
    device_client_service=$($COMMAND_PREFIX systemctl status aws-iot-device-client.service)
    if [ $(echo $?) -eq 4 ]; then
        printf $RED "WARNING: aws-iot-device-client.service is not installed. Please reconfigure."
        summary+=("$(printf $RED "[-] Configured systemd aws-iot-device-client.service")")
    else
        printf $GREEN "$device_client_service"
        device_client_service=$($COMMAND_PREFIX cat /etc/aws-iot-device-client/aws-iot-device-client.conf | jq)
        echo "$device_client_service"
        summary+=("$(printf $GREEN "[x] Configured systemd aws-iot-device-client.service")")
    fi

    printf $PMPT "Printing overall configuration summary..."
    for line in "${summary[@]}"; do
        echo $line
    done
}

remove_device() {
    local COMMAND_PREFIX=$1
    local action;
    local affirmative;
    local result;

    action=$($COMMAND_PREFIX systemctl status aws-iot-device-client.service)
    if [ $(echo $?) -ne 4 ]; then
        printf $PMPT "Remove aws-iot-device-client service? [y/n]"
        read -r affirmative
        if [ "$affirmative" = 'y' ]; then
            result=$($COMMAND_PREFIX systemctl disable aws-iot-device-client.service)
            printf $GREEN "$result"
        fi
        printf $PMPT "Remove aws-iot-device-client configuration? [y/n]"
        read -r affirmative
        if [ "$affirmative" = 'y' ]; then
            $COMMAND_PREFIX rm -rf /etc/aws-iot-device-client
            printf $GREEN "Removed /etc/aws-iot-device-client"
        fi
        printf $PMPT "Remove aws-iot-device-client binary? [y/n]"
        read -r affirmative
        if [ "$affirmative" = 'y' ]; then
            $COMMAND_PREFIX rm -f /sbin/aws-iot-device-client
            printf $GREEN "Removed aws-iot-device-client"
        fi
    fi

    action=$($COMMAND_PREFIX systemctl status pinthesky.service)
    if [ $(echo $?) -ne 4 ]; then
        printf $PMPT "Remove pinthesky systemd service? [y/n]"
        read -r affirmative
        if [ "$affirmative" = 'y' ]; then
            result=$($COMMAND_PREFIX systemctl disable pinthesky.service)
            printf $GREEN "$result"
        fi
    fi

    action=$($COMMAND_PREFIX cat /etc/pinthesky/pinthesky.env 2>/dev/null)
    if [ $(echo $?) -eq 0 ]; then
        eval $action
        if [ ! -z "$THING_NAME" ]; then
            printf $PMPT "Remove associated certificate? [y/n]"
            read -r affirmative
            if [ "$affirmative" = 'y' ]; then
                action=$(aws iot list-thing-principals --thing-name $THING_NAME | jq '.principals[]' | tr -d '"')
                aws iot update-certificate --certificate-id $(basename $action) --new-status INACTIVE >/dev/null
                aws iot detach-thing-principal --thing-name $THING_NAME --principal $action >/dev/null
                result=$(aws iot list-attached-policies --target $action | jq '.policies[].policyName' | tr -d '"')
                for policy in $result; do
                    aws iot detach-policy --policy-name $policy --target $action >/dev/null
                done
                aws iot delete-certificate --certificate-id $(basename $action) >/dev/null
                $COMMAND_PREFIX rm -rf /etc/pinthesky/certs
                printf $GREEN "Removed configured certificate and cloud associations."
            fi
            printf $PMPT "Remove the AWS IoT Thing $THING_NAME? [y/n]"
            read -r affirmative
            if [ "$affirmative" = 'y' ]; then
                aws iot delete-thing --thing-name $THING_NAME >/dev/null
                printf $GREEN "Removed $THING_NAME and associations."
            fi
        fi
        for config_file in EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT; do
            printf $PMPT "Remove ${!config_file}? [y/n]"
            read -r affirmative
            if [ "$affirmative" = 'y' ]; then
                $COMMAND_PREFIX rm -f ${!config_file}
                printf $GREEN "Successfully removed ${!config_file}."
            fi
        done
        printf $PMPT "Remove pinthesky.env configuration? [y/n]"
        read -r affirmative
        if [ "$affirmative" = 'y' ]; then
            $COMMAND_PREFIX rm -rf /etc/pinthesky
            printf $GREEN "Removed pinthesky.env"
        fi
    fi

    action=$($COMMAND_PREFIX which pinthesky)
    if [ ! -z "$action" ]; then
        printf $PMPT "Remove the pinthesky software? [y/n]"
        read -r affirmative
        if [ "$affirmative" = 'y' ]; then
            printf $PMPT "Removing $action"
            $COMMAND_PREFIX python3 -m pip uninstall -y pinthesky
            printf $GREEN "Removed $action software"
        fi
    fi

    printf $GREEN "Successfully removed pinthesky from the device."
}

ASSUME_ROOT=""
HOST_MACHINE=""
COMMAND_PREFIX=""
TARGET="install"
while getopts "hrm:t:" flag
do
    case "${flag}" in
        m) HOST_MACHINE="${OPTARG}";;
        r) ASSUME_ROOT='y';;
        t) TARGET="${OPTARG}"
            validate_target $TARGET
            ;;
        *) usage;;
    esac
done

configure_host_connection

printf $PMPT "Running the $TARGET function on the device."
if [ "$TARGET" = 'inspect' ]; then
    inspect_device "$COMMAND_PREFIX"
elif [ "$TARGET" = 'remove' ]; then
    remove_device "$COMMAND_PREFIX"
elif [ "$TARGET" = 'install' ]; then
    install_device "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
fi