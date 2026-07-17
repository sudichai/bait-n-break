#!/usr/bin/env bash
# Leaked-file crawler: iterates candidate paths from payloads_crawler_paths
# against the target. Uses engine integration for mission briefing, TOTAL tracking,
# progress bar, OPSEC, and debrief cards.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

crawl_leaked_files() {
    target_ensure_set || return 1
    _engine_reset_tracker

    local base="http://${TARGET_IP}:${TARGET_PORT}"
    local total="${#payloads_crawler_paths[@]}"
    local found=0 scanned=0
    local GREEN='\033[1;32m'
    local RESET='\033[0m'

    mission_brief "Bait File Crawler" "T1083" "TA0009 -- COLLECTION" "quiet"
    phase_banner "COLLECTION" "TA0009"
    fake_shell "gobuster dir -u http://\${TARGET_IP}:\${TARGET_PORT} -w /usr/share/wordlists/dirb/common.txt 2>/dev/null || true"

    for path in "${payloads_crawler_paths[@]}"; do
        [ -z "$path" ] && continue
        scanned=$((scanned + 1))
        local url="${base}${path}"
        local code

        code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "$url")"

        http_result "$code" "${path}"

        bar "$scanned" "$total"

        if [ "$code" = "200" ]; then
            printf "  ${GREEN}FOUND:${RESET} %s\n" "$path"
            found=$((found + 1))
        fi

        sleep 0.3
    done

    printf '\n'

    if [ "$found" -gt 0 ]; then
        results_record_simple "crawler" "SUCCESS" "quiet" "${found} paths found"
    else
        results_record_simple "crawler" "FAILED" "quiet" "0 paths found"
    fi

    ops "quiet"
    debrief_card "BAIT CRAWLER" "T1083" "quiet"
}
