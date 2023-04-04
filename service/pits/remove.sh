#!/usr/bin/env bash

REMOVE_LOG="pits.remove.log"


function pits::setup::remove::toggle() {
    local selection
    for selection in $(wheel::json::get "$screen" "properties.items[].configures" -c); do
        wheel::state::set "$selection" true argjson
    done
}

function pits::setup::remove::device_client_service() {
    if pits::setup::invoke test -f /etc/systemd/system/aws-iot-device-client.service > /dev/null; then
        pits::setup::invoke systemctl disable aws-iot-device-client || return $?
        pits::setup::invoke rm /etc/systemd/system/aws-iot-device-client.service
    fi
    echo "[+] Removed AWS IoT Device Client Service" >> "$REMOVE_LOG"
}

function pits::setup::remove::device_client_config() {
    {
        if pits::setup::invoke rm -rf /etc/aws-iot-device-client; then
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
    if pits::setup::invoke test -f /etc/systemd/system/pinthesky.service > /dev/null; then
        pits::setup::invoke systemctl disable pinthesky || return $?
        pits::setup::invoke rm /etc/systemd/system/pinthesky.service
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
            for principal in $(aws iot list-thing-principals --thing-name "$THING_NAME" --query principals --output text); do
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
    pits::setup::truncate "$REMOVE_LOG" || return 254
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

touch "$REMOVE_LOG"
wheel::events::add_clean_up "rm $REMOVE_LOG"