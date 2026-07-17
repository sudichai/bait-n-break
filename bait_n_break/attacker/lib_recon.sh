#!/usr/bin/env bash
# Reconnaissance: full port/service scan against TARGET_IP. Uses traffic_nmap_scan
# with service detection across ports 1-10000, or a hand-rolled /dev/tcp probe
# for a wide set of common ports as fallback.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

BNB_RECON_PORTS=(20 21 22 23 25 53 80 110 111 135 139 143 443 445 993 995 1723 3306 3389 5432 5900 8080 8443 2121 2222 9000 9090 4444)

recon_probe_port() {
    local host="$1" port="$2"
    (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null
    local rc=$?
    exec 3<&- 2>/dev/null
    exec 3>&- 2>/dev/null
    return "$rc"
}

recon_scan() {
    target_ensure_set || return 1

    mission_brief "Reconnaissance" "TA0043" "TA0043 -- RECONNAISSANCE" "quiet"

    phase_banner "RECONNAISSANCE" "TA0043"

    local GREEN='\033[1;32m'
    local BOLD='\033[1m'
    local RESET='\033[0m'

    if command -v nmap >/dev/null 2>&1; then
        printf "${GREEN}root@kali:~#${RESET} ${BOLD}nmap -sV -sC -p 1-10000 --min-rate 200 %s${RESET}\n" "${TARGET_IP}"
        echo ""

        local scan_output
        scan_output="$(traffic_nmap_scan "${TARGET_IP}" "1-10000" 2>&1)"
        echo "$scan_output"

        local open
        open="$(echo "$scan_output" | grep -c '/tcp\s\+open\b' || true)"

        local open_ports
        open_ports="$(echo "$scan_output" | grep '/tcp\s\+open\b' | awk '{print $1}' | tr '\n' ' ')"
        echo ""
        echo "[*] Open ports discovered: ${open_ports:-none}"
        echo "[*] Total open: ${open}"

        if [ "$open" -gt 0 ]; then
            results_record_simple "recon" "SUCCESS" "quiet" "${open} open port(s) on ${TARGET_IP}"
        else
            results_record_simple "recon" "FAILED" "quiet" "no open ports found on ${TARGET_IP}"
        fi
    else
        printf "${GREEN}root@kali:~#${RESET} ${BOLD}nmap -sV -sC -p 1-10000 --min-rate 200 %s${RESET}\n" "${TARGET_IP}"
        echo ""
        echo "[*] nmap not found, probing ${#BNB_RECON_PORTS[@]} common ports via /dev/tcp..."
        echo ""

        local open=0
        local total=0
        local p
        for p in "${BNB_RECON_PORTS[@]}"; do
            total=$((total + 1))
            if recon_probe_port "${TARGET_IP}" "${p}"; then
                echo "    [OPEN]   ${TARGET_IP}:${p}"
                open=$((open + 1))
            fi
        done
        echo ""
        echo "[*] Scanned ${total} ports, ${open} open"

        if recon_probe_port "${TARGET_IP}" 8080 2>/dev/null || \
           recon_probe_port "${TARGET_IP}" 80 2>/dev/null || \
           recon_probe_port "${TARGET_IP}" 443 2>/dev/null; then
            echo ""
            echo "--- HTTP banner grab ---"
            local web_port=8080
            recon_probe_port "${TARGET_IP}" 8080 2>/dev/null || web_port=80
            curl -s -I "http://${TARGET_IP}:${web_port}/" 2>/dev/null | head -10 || true
        fi

        if [ "$open" -gt 0 ]; then
            results_record_simple "recon" "SUCCESS" "quiet" "${open} open port(s) on ${TARGET_IP}"
        else
            results_record_simple "recon" "FAILED" "quiet" "no open ports found on ${TARGET_IP}"
        fi
    fi

    ops "quiet"
    debrief_card "RECONNAISSANCE" "TA0043" "quiet"
}
