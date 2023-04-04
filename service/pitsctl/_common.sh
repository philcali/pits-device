#!/usr/bin/env bash

PITS_ENV="pits.env"

function pits::setup::invoke() {
    local machine
    local cmd=("$@")
    machine=$(wheel::state::get "machine_host")
    [ "$(wheel::state::get "assume_root")" = "true" ] && cmd=("sudo" "${cmd[@]}")
    if [ -n "$machine" ]; then
        ssh -o ConnectTimeout=3 "$machine" "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

function pits::setup::cp() {
    local machine
    machine=$(wheel::state::get "machine_host")
    if [ -n "$machine" ]; then
        local scp_cmd=("scp")
        [ -d "$1" ] && scp_cmd+=("-r")
        scp_cmd+=("$1" "$machine:~/")
        "${scp_cmd[@]}"
        pits::setup::invoke mv "$1" "$2"
    fi
}

function pits::setup::truncate() {
    local file
    for file in "$@"; do
        (rm -f "$file" && touch "$file") || return $?
    done
}

function pits::setup::connection::result() {
    local machine
    machine=$(wheel::state::get "machine_host")
    screen=$(wheel::json::set "$screen" "properties.text" "Successfully connected to $machine.")
    wheel::screens::msgbox
}

function pits::setup::connection::validate() {
    local attempt
    local machine
    machine=$(wheel::state::get "machine_host")
    for attempt in 25 50 75; do
        echo "XXX"
        echo $attempt
        echo "Testing connection to $machine"
        echo "XXX"
        (ssh -q -o ConnectTimeout=3 "$machine" exit) && return 0
    done
    return 254
}

function pits::setup::connection::finish() {
    local key=$1
    [ "$key" = 'valid_connection' ] &&
    json_source=$(wheel::json::set "$json_source" 'dialog.backtitle' "Pi In the Sky - Setup Wizard [Connected to $(wheel::state::get "machine_host")]")
}

wheel::events::add_clean_up "rm -f $PITS_ENV"
wheel::events::add_state_change "pits::setup::connection::finish"