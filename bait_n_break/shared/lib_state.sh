#!/usr/bin/env bash
# Sole reader/writer of .state/* runtime files. Other modules must not
# touch .state/* directly - they call these functions instead.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

state_init() {
    mkdir -p "${BNB_STATE_DIR}" "${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}"
    touch "${BNB_STATE_FILE}" "${BNB_BAIT_MANIFEST}" "${BNB_INCIDENT_LOG}" "${BNB_BAIT_ACCESS_LOG}" "${BNB_ATTACK_RESULTS}" "${BNB_TARGET_FILE}"
}

state_set_status() {
    echo "$1" > "${BNB_STATE_FILE}"
}

state_get_status() {
    if [ -s "${BNB_STATE_FILE}" ]; then
        cat "${BNB_STATE_FILE}"
    else
        echo "not_deployed"
    fi
}

state_manifest_add() {
    echo "$1" >> "${BNB_BAIT_MANIFEST}"
}

state_manifest_list() {
    [ -f "${BNB_BAIT_MANIFEST}" ] && cat "${BNB_BAIT_MANIFEST}"
}

state_manifest_clear() {
    : > "${BNB_BAIT_MANIFEST}"
}

state_incident_append() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [$1] $2" >> "${BNB_INCIDENT_LOG}"
}

state_incident_tail() {
    local n="${1:-50}"
    [ -f "${BNB_INCIDENT_LOG}" ] && tail -n "$n" "${BNB_INCIDENT_LOG}"
}

state_bait_marker_touch() {
    touch "${BNB_BAIT_ACCESS_LOG}"
}

state_bait_marker_files_since() {
    local dir="$1"
    find "$dir" -type f -newer "${BNB_BAIT_ACCESS_LOG}" -printf '%p accessed\n' 2>/dev/null
}

state_set_target() {
    printf '%s %s\n' "$1" "$2" > "${BNB_TARGET_FILE}"
}

state_get_target() {
    [ -f "${BNB_TARGET_FILE}" ] && cat "${BNB_TARGET_FILE}"
}

state_reset() {
    rm -f "${BNB_STATE_FILE}" "${BNB_BAIT_MANIFEST}" "${BNB_INCIDENT_LOG}" "${BNB_BAIT_ACCESS_LOG}" "${BNB_ATTACK_RESULTS}" "${BNB_TARGET_FILE}"
    rm -rf "${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}"
    state_init
}
