#!/usr/bin/env bash
# Sole reader/writer of .state/attack_results.txt. Other attacker modules
# must not touch that file directly - they call these functions instead.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

results_init() {
    touch "${BNB_ATTACK_RESULTS}"
}

results_record() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [$1] [$2] [OPSEC:$3] $4" >> "${BNB_ATTACK_RESULTS}"
}

results_summary() {
    [ -f "${BNB_ATTACK_RESULTS}" ] && cat "${BNB_ATTACK_RESULTS}"
}

results_clear() {
    : > "${BNB_ATTACK_RESULTS}"
}
