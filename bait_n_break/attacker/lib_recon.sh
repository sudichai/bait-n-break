#!/usr/bin/env bash
# Reconnaissance: full port/service scan against TARGET_IP. Uses nmap with
# service detection across common ports, or a hand-rolled /dev/tcp probe
# for a wide set of ports as fallback.
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
    target_ensure_set || { echo "[recon] No target set."; return 1; }
    echo ""
    echo "=============================================="
    echo "  RECONNAISSANCE: ${TARGET_IP}"
    echo "=============================================="
    echo ""
    local open=0 total=0
    if command -v nmap >/dev/null 2>&1; then
        echo "[*] Running nmap service scan (top 1000 ports)..."
        echo ""
        local nmap_out
        nmap_out="$(nmap -sV -sC --min-rate 200 --max-rate 500 -T4 "${TARGET_IP}" 2>&1)"
        echo "$nmap_out"
        open="$(echo "$nmap_out" | grep -c '/tcp\s\+open\b' || true)"

        local open_ports
        open_ports="$(echo "$nmap_out" | grep '/tcp\s\+open\b' | awk '{print $1}' | tr '\n' ' ')"
        echo ""
        echo "[*] Open ports discovered: ${open_ports:-none}"
        echo "[*] Total open: ${open}"
    else
        echo "[*] nmap not found, probing ${#BNB_RECON_PORTS[@]} common ports via /dev/tcp..."
        echo ""
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
    fi
    echo ""
    echo "=============================================="
    echo "  RECON COMPLETE"
    echo "=============================================="
    if [ "$open" -gt 0 ]; then
        results_record "recon" "SUCCESS" "quiet" "scan completed: ${open} open port(s) on ${TARGET_IP}"
    else
        results_record "recon" "FAILED" "quiet" "no open ports found on ${TARGET_IP}"
    fi
}
