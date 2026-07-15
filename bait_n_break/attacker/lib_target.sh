#!/usr/bin/env bash
# Prompts for and validates TARGET_IP, persists via lib_state.sh,
# and exposes $TARGET_IP/$TARGET_PORT to all attacker scripts.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

target_is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    local -a octets=($ip)
    local o
    for o in "${octets[@]}"; do
        [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
    done
    return 0
}

target_prompt() {
    local ip
    read -r -p "Target IP [${TARGET_IP:-required}]: " ip
    ip="${ip:-${TARGET_IP:-}}"
    if ! target_is_valid_ip "$ip"; then
        ui_error "Invalid Target" "\"$ip\" is not a valid IPv4 address."
        return 1
    fi
    TARGET_IP="$ip"
    TARGET_PORT="${TARGET_PORT:-8080}"
    state_set_target "$TARGET_IP" "${TARGET_PORT:-8080}"
    ui_msgbox "Target Set" "Target: ${TARGET_IP}
Web port: ${TARGET_PORT:-8080} (recon will discover all open ports)"
}

target_ensure_set() {
    if [ -z "${TARGET_IP:-}" ]; then
        local saved
        saved="$(state_get_target)"
        if [ -n "$saved" ]; then
            TARGET_IP="$(echo "$saved" | cut -d' ' -f1)"
            TARGET_PORT="$(echo "$saved" | cut -d' ' -f2)"
        fi
    fi
    if [ -z "${TARGET_IP:-}" ]; then
        target_prompt
    fi
    [ -n "${TARGET_IP:-}" ]
}
