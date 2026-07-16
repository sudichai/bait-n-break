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

results_cve_summary() {
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        echo "No attack results yet."
        return
    fi
    echo ""
    echo "=============================================="
    echo "  CVE EXPLOIT RESULTS SUMMARY"
    echo "=============================================="
    local cve_count=0 cve_success=0
    while IFS= read -r line; do
        if echo "$line" | grep -q "CVE-"; then
            cve_count=$((cve_count + 1))
            if echo "$line" | grep -q "VULNERABLE\|SUCCESS"; then
                echo "  [VULN] $line"
                cve_success=$((cve_success + 1))
            else
                echo "  [----] $line"
            fi
        fi
    done < "${BNB_ATTACK_RESULTS}"
    echo "  CVE score: ${cve_success}/${cve_count} exploited"
    echo ""
}
