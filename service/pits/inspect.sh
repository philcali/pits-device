#!/usr/bin/env bash

INSPECTION_LOG="pits.inspection.log"


function pits::setup::inspect::software() {
    local version
    pits::setup::truncate "$INSPECTION_LOG" "$PITS_ENV" || return 254
    echo "Validating basic dependencies"
    pits::setup::invoke which pip3 || {
        echo "[-] pip is not installed" >> "$INSPECTION_LOG"
    }
    echo "Validating software installation for device"
    version=$(pits::setup::invoke pinthesky --version) || {
        echo "[-] Pinthesky is not installed" >> "$INSPECTION_LOG"
    }
    [ -n "$version" ] && {
        echo "Found version $version"
        echo "[+] Pinthesky is installed: $version" >> "$INSPECTION_LOG"
    }
    return 0
}

function pits::setup::inspect::configuration() {
    local log_file=${1:-"$INSPECTION_LOG"}
    echo "Inspecting pits.env configuration"
    pits::setup::invoke cat /etc/pinthesky/pinthesky.env > "$PITS_ENV" 2>/dev/null || {
        echo "[-] No pinthesky.env found" >> "$log_file"
    }
}

function pits::setup::inspect::cloud() {
    local role_alias_arn
    local thing_output
    local principal
    local principals
    local policy
    local policies
    # shellcheck source=pits.env
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    echo "Invoking cloud configuration tests for $THING_NAME"
    {
        if [ -z "$THING_NAME" ]; then
            echo "[-] Cloud connection: THING_NAME is not configured"
        elif [ -z "$ROLE_ALIAS" ]; then
            echo "[-] Cloud connection: ROLE_ALIAS is not configured"
        else
            role_alias_arn=$(aws iot describe-role-alias --role-alias "$ROLE_ALIAS") ||
            echo "[-] Cloud connection: ROLE_ALIAS $ROLE_ALIAS does not exist"
            thing_output=$(aws iot describe-thing --thing-name "$THING_NAME") ||
            echo "[-] Cloud connection: THING_NAME $THING_NAME does not exist"
            if [ -n "$thing_output" ]; then
                aws iot list-thing-groups-for-thing --thing-name "$THING_NAME" >/dev/null ||
                echo "[-] Cloud connection: $THING_NAME does not belong to a group"
                principals=$(aws iot list-thing-principals --thing-name "$THING_NAME" | jq -r '.principals[]') ||
                echo "[-] Cloud connection: $THING_NAME has no principals attached"
                for principal in $principals; do
                    policies=$(aws iot list-attached-policies --target "$principal" | jq -r '.policies[].policyName') ||
                    echo "[-] Cloud connection: $THING_NAME principal $principal is without policies"
                    for policy in $policies; do
                        local can_assume
                        can_assume=$(aws iot get-policy --policy-name "$policy" |
                            jq -r '.policyDocument' |
                            jq '.Statement[] | (.Action[0], "," + .Resource[0])' |
                            grep "iot:AssumeRoleWithCertificate,$role_alias_arn")
                        if [ -z "$can_assume" ]; then
                            echo "[-] Cloud connection: Thing $THING_NAME attached to $policy cannot assume a role"
                        else
                            echo "[+] Cloud connection: Thing $THING_NAME attached to $policy assuming $ROLE_ALIAS"
                        fi
                    done
                done
            fi
        fi
    } >> "$INSPECTION_LOG"
}

function pits::setup::inspect::files() {
    local test_file
    # shellcheck source=pits.env
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    local paths=(EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT)
    echo "Invoking configuration paths ${paths[*]}"
    {
        for test_file in "${paths[@]}"; do
            if [ -z "${!test_file}" ]; then
                echo "[-] Configuration $test_file is not set"
            else
                if pits::setup::invoke cat "${!test_file}" > /dev/null; then
                    echo "[+] Configuration $test_file is valid"
                else
                    echo "[-] Configuration $test_file is not valid"
                fi
            fi
        done
    } >> "$INSPECTION_LOG"
}

function pits::setup::inspect::storage() {
    # shellcheck source=pits.env
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    echo "Invoking storage tests for $BUCKET_NAME"
    {
        if [ -z "$BUCKET_NAME" ]; then
            echo "[-] Configured remote storage"
        else
            if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null;then
                echo "[+] Configured bucket $BUCKET_NAME exists"
            else
                echo "[-] Configured bucket $BUCKET_NAME does not exist"
            fi
        fi
    } >> "$INSPECTION_LOG"
}

function pits::setup::inspect::service() {
    echo "Invoking pinthesky service validation"
    {
        if pits::setup::invoke systemctl status pinthesky.service >/dev/null; then
            echo "[+] Configured systemd pinthesky.service"
        else
            echo "[-] Configured systemd pinthesky.service"
        fi
    } >> "$INSPECTION_LOG"
}

function pits::setup::inspect::device_client() {
    echo "Invoking AWS IoT Device Client validation"
    {
        if pits::setup::invoke systemctl status aws-iot-device-client.service >/dev/null; then
            echo "[+] Configured systemd aws-iot-device-client"
        else
            echo "[-] Configured systemd aws-iot-device-client"
        fi
    } >> "$INSPECTION_LOG"
}

touch "$INSPECTION_LOG"
wheel::events::add_clean_up "rm $INSPECTION_LOG"