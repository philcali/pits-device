#!/bin/bash

AWS_CLI=$(which aws)
DEFAULT_THING_NAME="PinTheSkyThing"
DEFAULT_ROLE_ALIAS_NAME="PinTheSkyRoleAlias"
DEFAULT_ROLE_NAME="PinTheSkyRole"
DEFAULT_THING_POLICY_NAME="PinTheSkyThingPolicy"
RAW_CONTENT_URL="https://raw.githubusercontent.com/philcali/pits-device/main"
INSTALL_VERSION="git+https://github.com/philcali/pits-device.git"
ROOT_CA_LOCATION="https://www.amazontrust.com/repository/AmazonRootCA1.pem"

function banner() {
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

"
    echo "Welcome to the guided install of the pinthesky device!"
}

function download_resource() {
    local RESOURCE_FILE=$1

    if [ -f "service/$RESOURCE_FILE" ]; then
        cp service/$RESOURCE_FILE $RESOURCE_FILE
    else
        wget -O $RESOURCE_FILE $RAW_CONTENT_URL/service/$RESOURCE_FILE
    fi
}

function associate_thing() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3
    read -p "Enter the Thing name [$DEFAULT_THING_NAME]: " THING_NAME
    THING_NAME=${THING_NAME:-$DEFAULT_THING_NAME}
    THING_OUTPUT=$(aws iot describe-thing --thing-name $THING_NAME 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        THING_OUTPUT=$(aws iot create-thing --thing-name $THING_NAME)
        echo "Created AWS IoT Thing $THING_NAME"
    fi
    read -p "Enter the IAM Role name [$DEFAULT_ROLE_NAME]: " ROLE_NAME
    ROLE_NAME=${ROLE_NAME:-$DEFAULT_ROLE_NAME}
    ROLE_OUTPUT=$(aws iam get-role --role-name $ROLE_NAME 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        download_resource default.iam.role.json
        ROLE_OUTPUT=$(aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://default.iam.role.json)
        rm default.iam.role.json
        echo "Created IAM role $ROLE_NAME"
    fi
    ROLE_ARN=$(echo $ROLE_OUTPUT | jq '.Role.Arn' | tr -d '"')
    read -p "Enter the Role Alias name [$DEFAULT_ROLE_ALIAS_NAME]: " ROLE_ALIAS
    ROLE_ALIAS=${ROLE_ALIAS:-$DEFAULT_ROLE_ALIAS_NAME}
    ROLE_ALIAS_OUTPUT=$(aws iot describe-role-alias --role-alias $ROLE_ALIAS 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        ROLE_ALIAS_OUTPUT=$(aws iot create-role-alias --role-alias $ROLE_ALIAS --role-arn $ROLE_ARN)
        ROLE_ALIAS_ARN=$(echo $ROLE_ALIAS_OUTPUT | jq '.roleAliasArn' | tr -d '"')
        echo "Created role alias $ROLE_ALIAS associated to $ROLE_ARN"
    else
        ROLE_ALIAS_ARN=$(echo $ROLE_ALIAS_OUTPUT | jq '.roleAliasDescription.roleAliasArn' | tr -d '"')
    fi
    read -p "Enter the Thing policy name [$DEFAULT_THING_POLICY_NAME]: " THING_POLICY
    THING_POLICY=${THING_POLICY:-$DEFAULT_THING_POLICY_NAME}
    POLICY_OUTPUT=$(aws iot get-policy --policy-name $THING_POLICY 2>/dev/null)
    if [ $(echo $?) -ne 0 ]; then
        download_resource default.policy.json
        sed -i "s|\"ROLE_ALIAS\"|\"$ROLE_ALIAS_ARN\"|" default.policy.json
        POLICY_OUTPUT=$(aws iot create-policy --policy-name $THING_POLICY --policy-document file://default.policy.json)
        rm default.policy.json
        echo "Created AWS IoT Thing Policy $THING_POLICY"
    fi
    read -p 'Create certificates? [y/n] ' CREATE_CERTS
    if [ $CREATE_CERTS = 'y' ]; then
        CERT_FILE="thing.cert.pem"
        PRV_KEY_FILE="thing.key"
        PUB_KEY_FILE="thing.pub"
        CA_CERT="AmazonRootCA1.pem"
        wget -O $CA_CERT $ROOT_CA_LOCATION
        CERT_OUTPUT=$(aws iot create-keys-and-certificate --set-as-active --public-key-outfile $PUB_KEY_FILE --private-key-outfile $PRV_KEY_FILE --certificate-pem-outfile $CERT_FILE)
        echo "Created AWS IoT Thing Certificates for $THING_NAME"

        CERT_ARN=$(echo $CERT_OUTPUT | jq '.certificateArn' | tr -d '"')
        $(aws iot attach-thing-principal --thing-name $THING_NAME --principal $CERT_ARN)
        echo "Attached certificate to $THING_NAME"
        $(aws iot attach-policy --policy-name $THING_POLICY --target $CERT_ARN)
        echo "Attached $THING_POLICY to $CERT_ARN"
        if [ $CLIENT_MACHINE = 'y' ]; then    
            mkdir certs
            for FILE in "$CERT_FILE $PRV_KEY_FILE $PUB_KEY_FILE $CA_CERT"; do
                mv $FILE certs/
            done
            scp -r certs $HOST_MACHINE:~/certs
            $($COMMAND_PREFIX mv certs /etc/pinthesky/certs)
            echo "Sent $CERT_FILE, $PRV_KEY_FILE, and $CA_CERT to /etc/pinthesky/certs"
            rm -rf certs
        fi
    fi
    echo Finishing provisiong $THING_NAME
}

function install_pinthesky() {
    local CLIENT_MACHINE=$1
    local HOST_MACHINE=$2
    local COMMAND_PREFIX=$3

    PINTHESKY_VERSION=$($COMMAND_PREFIX which pinthesky)
    if [ -z $PINTHESKY_VERSION ]; then
        echo Installing pinthesky
        $($COMMAND_PREFIX pip3 install $INSTALL_VERSION)
    else
        echo "A version of pinthesky is already installed at $PINTHESKY_VERSION"
    fi

    echo "Creating /etc/pinthesky"
    $($COMMAND_PREFIX mkdir -p /etc/pinthesky)

    echo "Copying pinthesky.env"
    download_resource pinthesky.env
    if [ $CLIENT_MACHINE = 'y' ]; then
        scp pinthesky.env $HOST_MACHINE:~/
    fi
    $($COMMAND_PREFIX mv pinthesky.env /etc/pinthesky/pinthesky.env)
    rm pinthesky.env
    echo Successfully installed pinthesky software
}

banner

read -p 'Are you running the install from a client machine? [y/n] ' CLIENT_MACHINE
HOST_MACHINE=""
COMMAND_PREFIX=""
if [ $CLIENT_MACHINE = 'y' ]; then
    read -p 'Machine host: ' HOST_MACHINE
    COMMAND_PREFIX="ssh $HOST_MACHINE"
fi

read -p 'Can I assume root privileges to install things? [y/n] ' ASSUME_ROOT
if [ $ASSUME_ROOT = 'y' ]; then
    COMMAND_PREFIX="$COMMAND_PREFIX sudo"
fi

# install_pinthesky "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"

if [ -z $AWS_CLI ]; then
    echo "The AWS CLI is not installed. Finished"
else
    read -p 'Associate to an AWS IoT Thing? [y/n] ' ASSOCIATE_THING
    if [ $ASSOCIATE_THING = 'y' ]; then
        associate_thing "$CLIENT_MACHINE" "$HOST_MACHINE" "$COMMAND_PREFIX"
    fi
fi