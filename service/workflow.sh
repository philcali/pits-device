#!/usr/bin/env bash

INSPECTION_LOG="pits.inspection.log"
REMOVE_LOG="pits.remove.log"
INSTALL_LOG="pits.install.log"
PITS_ENV="pits.env"

function pits::setup::invoke() {
    local machine
    local cmd=("$@")
    machine=$(wheel::state::get "machineHost")
    [ "$(wheel::state::get "assumeRoot")" = "true" ] && cmd=("sudo" "${cmd[@]}")
    if [ -n "$machine" ]; then
        ssh -o ConnectTimeout=3 "$machine" "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

function pits::setup::inspect::software() {
    local version
    pits::setup::utils::truncate "$INSPECTION_LOG" "$PITS_ENV" || return 254
    {
        version=$(pits::setup::invoke pinthesky --version)
        echo "Found version $version"
        echo "[+] Pinthesky is installed: $version" >> "$INSPECTION_LOG"
    } || {
        echo "[-] Pinthesky is not installed" >> "$INSPECTION_LOG"
    }
}

function pits::setup::inspect::configuration() {
    local log_file=${1:-"$INSPECTION_LOG"}
    pits::setup::invoke cat /etc/pinthesky/pinthesky.env > "$PITS_ENV" 2>> "$log_file"
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
    {
        for test_file in EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT; do
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
    {
        if pits::setup::invoke systemctl status pinthesky.service >/dev/null; then
            echo "[+] Configured systemd pinthesky.service"
        else
            echo "[-] Configured systemd pinthesky.service"
        fi
    } >> "$INSPECTION_LOG"
}

function pits::setup::inspect::device_client() {
    {
        if pits::setup::invoke systemctl status aws-iot-device-client.service >/dev/null; then
            echo "[+] Configured systemd aws-iot-device-client"
        else
            echo "[-] Configured systemd aws-iot-device-client"
        fi
    } >> "$INSPECTION_LOG"
}

function pits::setup::remove::toggle() {
    local selection
    for selection in $(wheel::json::get "$screen" "properties.items[].configures" -c); do
        wheel::state::set "$selection" true argjson
    done
}

function pits::setup::remove::device_client_service() {
    if pits::setup::invoke systemctl status aws-iot-device-client; then
        pits::setup::invoke systemctl disable aws-iot-device-client || return $?
    fi
    echo "[+] Removed AWS IoT Device Client Service" >> "$REMOVE_LOG"
}

function pits::setup::remove::device_client_config() {
    {
        if pits::setup::invoke rm -rf /etc/aws-iot-device-client >/dev/null; then
            echo "[+] Removed AWS IoT Device Client Configuration"
        else
            echo "[-] Failed to remove AWS IoT Device Client Configuration"
        fi
    } >> "$REMOVE_LOG"
}

function pits::setup::remove::device_client_software() {
    {
        if pits::setup::invoke rm -f /sbin/aws-iot-device-client; then
            echo "[+] Removed AWS IoT Device Client Software"
        else
            echo "[-] Failed to remove AWS IoT Device Client Software"
        fi
    } >> "$REMOVE_LOG"
}

function pits::setup::remove::pinthesky_service() {
    if pits::setup::invoke systemctl status pinthesky; then
        pits::setup::invoke systemctl disable pinthesky || return $?
    fi
    echo "[+] Removed Pinthesky Service" >> "$REMOVE_LOG"
}

function pits::setup::remove::cloud_certs() {
    [ ! -f "$PITS_ENV" ] && pits::setup::inspect::configuration "$REMOVE_LOG"
    # shellcheck source=pits.env
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    {
        if [ -n "$THING_NAME" ]; then
            local principal
            local policy
            for principal in $(aws iot list-thing-principals --thing-name "$THING_NAME" | jq -r '.principals[]'); do
                aws iot update-certificate --certificate-id "$(basename "$principal")" --new-status INACTIVE >/dev/null
                aws iot detach-thing-principal --thing-name "$THING_NAME" --principal "$principal" >/dev/null
                for policy in $(aws iot list-attached-policies --target "$principal" | jq -r '.policies[].policyName'); do
                    aws iot detach-policy --policy-name "$policy" --target "$principal" >/dev/null
                done
                aws iot delete-certificate --certificate-id "$(basename "$principal")" >/dev/null
            done
            pits::setup::invoke rm -rf /etc/pinthesky/certs
        else
            echo "Configuration does not have a THING_NAME"
        fi
    } || return $?
    echo "[+] Removed AWS IoT Certificates" >> "$REMOVE_LOG"
}

function pits::setup::remove::cloud_thing() {
    [ ! -f "$PITS_ENV" ] && pits::setup::inspect::configuration "$REMOVE_LOG"
    # shellcheck source=pits.env
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    [ -n "$THING_NAME" ] && aws iot delete-thing --thing-name "$THING_NAME" >/dev/null || return $?
    echo "[+] Removed AWS IoT Thing" >> "$REMOVE_LOG"
}

function pits::setup::remove::pinthesky_config() {
    [ ! -f "$PITS_ENV" ] && pits::setup::inspect::configuration "$REMOVE_LOG"
    # shellcheck source=pits.env
    [ -f "$PITS_ENV" ] && source "$PITS_ENV"
    local config_file
    for config_file in EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT; do
        pits::setup::invoke rm -f "${!config_file}" || return $?
    done
    pits::setup::invoke rm -rf /etc/pinthesky/pinthesky.env || return $?
    echo "[+] Removed Pinthesky Configuration" >> "$REMOVE_LOG"
}

function pits::setup::remove::pinthesky_software() {
    if [ -n "$(pits::setup::invoke which pinthesky)" ]; then
        pits::setup::invoke python3 -m pip uninstall -y pinthesky || return $?
    fi
    echo "[+] Removed Pinthesky Software" >> "$REMOVE_LOG"
}

function pits::setup::remove::device() {
    pits::setup::utils::truncate "$REMOVE_LOG" || return 254
    local removal_tasks
    local task_index
    mapfile -t removal_tasks < <(wheel::state::get "removal | to_entries[] | select(.value) | .key" -r)
    wheel::log::debug "Set for removal: ${removal_tasks[*]}"
    for task_index in "${!removal_tasks[@]}"; do
        local action_name="${removal_tasks[$task_index]}"
        screen="$(wheel::json::set "$screen" "properties.actions[$task_index].label" "Removing ${action_name//_/ }...")"
        screen="$(wheel::json::set "$screen" "properties.actions[$task_index].action" "pits::setup::remove::$action_name")"
        wheel::log::debug "New screen value $screen"
    done
    wheel::screens::gauge
}

function pits::setup::utils::truncate() {
    local file
    for file in "$@"; do
        (rm -f "$file" && touch "$file") || return $?
    done
}

function pits::setup::connection::validate() {
    local attempt
    local machine
    machine=$(wheel::state::get "machineHost")
    for attempt in 25 50 75; do
        echo "XXX"
        echo $attempt
        echo "Testing connection to $machine"
        echo "XXX"
        (ssh -q -o ConnectTimeout=3 "$machine" exit) && return 0
    done
    return 254
}

function pits::setup::connection::result() {
    local machine
    machine=$(wheel::state::get "machineHost")
    screen=$(wheel::json::set "$screen" "properties.text" "Successfully connected to $machine.")
    wheel::screens::msgbox
}

function pits::setup::install::pinthesky_software() {
    if [ -z "$(pits::setup::invoke which pinthesky)" ]; then
        if pits::setup::invoke pip3 install pinthesky; then
            echo "[+] Installed pinthesky" >> "$INSTALL_LOG"
        else
            echo "[-] Failed to install pinthesky" >> "$INSTALL_LOG"
        fi
    else
        echo "[+] Already installed pinthesky" >> "$INSTALL_LOG"
    fi
}

touch "$INSPECTION_LOG"
touch "$REMOVE_LOG"
touch "$INSTALL_LOG"
touch "$PITS_ENV"
wheel::events::add_clean_up "rm $INSPECTION_LOG"
wheel::events::add_clean_up "rm $REMOVE_LOG"
wheel::events::add_clean_up "rm $INSTALL_LOG"
wheel::events::add_clean_up "rm $PITS_ENV"