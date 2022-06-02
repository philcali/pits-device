#!/bin/bash

__check_software_version() {
    local COMMAND_PREFIX=$1
    local installed_version=""
    installed_version=$($COMMAND_PREFIX python3 -m pip list | grep "pinthesky")
    if [ -z "$installed_version" ]; then
        summary+=("$(printf $RED "[-] Installed pinthesky software")")
    else
        summary+=("$(printf $GREEN "[+] Installed pinthesky software: $installed_version")")
    fi
}

__pull_env_values() {
    local COMMAND_PREFIX=$1
    $COMMAND_PREFIX cat /etc/pinthesky/pinthesky.env 2>/dev/null
}

__check_software_configuration() {
    local COMMAND_PREFIX=$1
    local configured_env=""
    configured_env=$(__pull_env_values "$COMMAND_PREFIX")
    if [ $(echo $?) -ne 0 ]; then
        summary+=("$(printf $RED "[-] Configured pinthesky software")")
    else
        summary+=("$(printf $GREEN "[+] Configured pinthesky software")")
    fi
}

__check_cloud_configuration() {
    local COMMAND_PREFIX=$1
    local thing_groups=""
    local principals=""
    local role_alias_arn=""
    local role_alias_output=""
    if [ -z "$THING_NAME" ]; then
        summary+=("$(printf $RED "[-] Cloud connection: THING_NAME is not configured.")")
    else
        if [ -z "$ROLE_ALIAS" ]; then
            summary+=("$(printf $RED "[-] Cloud connection: ROLE_ALIAS is not configured.")")
        else
            role_alias_output=$(aws iot describe-role-alias --role-alias $ROLE_ALIAS)
            if [ $(echo $?) -ne 0 ]; then
                summary+=("$(printf $RED "[-] Cloud connection: ROLE_ALIAS $ROLE_ALIAS does not exists.")")
            else
                role_alias_arn=$(echo "$role_alias_output" | jq '.roleAliasDescription.roleAliasArn' | tr -d '"')
            fi
        fi
        THING_OUTPUT=$(aws iot describe-thing --thing-name $THING_NAME 2>/dev/null)
        if [ $(echo $?) -ne 0 ]; then
            summary+=("$(printf $RED "[-] Cloud connection: THING_NAME $THING_NAME does not exists")")
        else
            thing_groups=$(aws iot list-thing-groups-for-thing --thing-name $THING_NAME | jq '.thingGroups[].groupName' | tr -d '"')
            if [ -z "$thing_groups" ]; then
                summary+=("$(printf $RED "[-] Cloud connection: $THING_NAME does not belong to a Thing Group.")")
            fi
            principals=$(aws iot list-thing-principals --thing-name $THING_NAME | jq '.principals[]' | tr -d '"')
            if [ -z "$principals" ]; then
                summary+=("$(printf $RED "[-] Cloud connection: $THING_NAME has with no principals attached")")
            else
                for principal in $principals; do
                    policies=$(aws iot list-attached-policies --target $principal | jq '.policies[].policyName' | tr -d '"')
                    if [ -z "$policies" ]; then
                        summary+=("$(printf $RED "[-] Cloud connection: $THING_NAME principal $principal is without policies.")")
                    else
                        for policy in $policies; do
                            can_assume=$(aws iot get-policy --policy-name $policy \
                                | jq -r '.policyDocument' \
                                | jq '.Statement[] | (.Action[0] + "," + .Resource[0])' \
                                | grep "iot:AssumeRoleWithCertificate,$role_alias_arn")
                            if [ -z "$can_assume" ]; then
                                summary+=("$(printf $RED "[-] Cloud connection: Thing $THING_NAME attached to $policy cannot assume a role alias.")")
                            else
                                summary+=("$(printf $GREEN "[+] Cloud connection: Thing $THING_NAME attached to $policy assuming $ROLE_ALIAS")")
                            fi
                        done
                    fi
                done
            fi
        fi
    fi
}

__check_file_configuration() {
    local COMMAND_PREFIX=$1
    for test_file in EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT; do
        if [ -z "${!test_file}" ]; then
            summary+=("$(printf $RED "[-] Configuration $test_file is not configured.")")
        else
            $COMMAND_PREFIX cat ${!test_file} > /dev/null
            if [ $(echo $?) -ne 0 ]; then
                summary+=("$(printf $RED "[-] Configuration ${!test_file} is valid.")")
            else
                summary+=("$(printf $GREEN "[+] Configuration ${!test_file} is valid.")")
            fi
        fi
    done
}

__check_remote_storage() {
    local COMMAND_PREFIX=$1
    if [ -z "$BUCKET_NAME" ]; then
        summary+=("$(printf $RED "[-] Configured remote storage")")
    else
        aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null
        if [ $(echo $?) -ne 0 ]; then
            summary+=("$(printf $RED "[-] Configured remote storage: $BUCKET_NAME does not exist.")")
        else
            summary+=("$(printf $GREEN "[+] Configured remote storage")")
        fi
    fi
}

__check_software_service() {
    local COMMAND_PREFIX=$1
    local pintthesky_service=""
    pintthesky_service=$($COMMAND_PREFIX systemctl status pinthesky.service)
    if [ $(echo $?) -eq 4 ]; then
        summary+=("$(printf $RED "[-] Configured systemd pinthesky.service")")
    else
        summary+=("$(printf $GREEN "[+] Configured systemd pinthesky.service")")
    fi
}

__check_device_client() {
    local COMMAND_PREFIX=$1
    local device_client_service=""
    device_client_service=$($COMMAND_PREFIX systemctl status aws-iot-device-client.service)
    if [ $(echo $?) -eq 4 ]; then
        summary+=("$(printf $RED "[-] Configured systemd aws-iot-device-client.service")")
    else
        summary+=("$(printf $GREEN "[+] Configured systemd aws-iot-device-client.service")")
    fi
}

inspect_device() {
    local COMMAND_PREFIX=$1
    local summary=()

    printf $PMPT "Checking the latest version of pinthesky. Please wait a moment..."
    __check_software_version "$COMMAND_PREFIX"

    printf $PMPT "Checking pinthesky configuration. Please wait a moment..."
    __check_software_configuration "$COMMAND_PREFIX"

    for value in $(__pull_env_values "$COMMAND_PREFIX"); do
        eval $value
    done

    printf $PMPT "Checking cloud connection. Please wait a moment..."
    __check_cloud_configuration "$COMMAND_PREFIX"

    printf $PMPT "Checking pinthesky configuration validity. Please wait a moment..."
    __check_file_configuration "$COMMAND_PREFIX"

    printf $PMPT "Checking storage location. Please wait a moment..."
    __check_remote_storage "$COMMAND_PREFIX"

    printf $PMPT "Checking pinthesky.service configuration. Please wait a moment..."
    __check_software_service "$COMMAND_PREFIX"

    printf $PMPT "Checking aws-iot-device-client.service configuration. Please wait a moment..."
    __check_device_client "$COMMAND_PREFIX"

    printf $PMPT "Printing overall configuration summary..."
    for line in "${summary[@]}"; do
        echo $line
    done
}