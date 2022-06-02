#!/bin/bash

__remove_device_client_service() {
    local COMMAND_PREFIX=$1

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
}

__remove_software_service() {
    local COMMAND_PREFIX=$1

    action=$($COMMAND_PREFIX systemctl status pinthesky.service)
    if [ $(echo $?) -ne 4 ]; then
        printf $PMPT "Remove pinthesky systemd service? [y/n]"
        read -r affirmative
        if [ "$affirmative" = 'y' ]; then
            result=$($COMMAND_PREFIX systemctl disable pinthesky.service)
            printf $GREEN "$result"
        fi
    fi

}

__remove_connection_configuration() {
    local COMMAND_PREFIX=$1

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
}

__remove_software_installation() {
    local COMMAND_PREFIX=$1
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
}

remove_device() {
    local COMMAND_PREFIX=$1
    local action;
    local affirmative;
    local result;

    __remove_device_client_service "$COMMAND_PREFIX"
    __remove_software_service "$COMMAND_PREFIX"
    __remove_connection_configuration "$COMMAND_PREFIX"
    __remove_software_installation "$COMMAND_PREFIX"

    printf $GREEN "Successfully removed pinthesky from the device."
}