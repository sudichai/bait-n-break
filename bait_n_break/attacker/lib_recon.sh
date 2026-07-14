#!/usr/bin/env bash
# Reconnaissance: port/service scan against TARGET_IP. Uses nmap if
# available, else a hand-rolled /dev/tcp probe + curl banner grab.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

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
    echo "=== Recon scan against ${TARGET_IP} ==="
    local open=0
    if command -v nmap >/dev/null 2>&1; then
        local nmap_out
        nmap_out="$(nmap -sV -p "22,21,${TARGET_PORT}" "${TARGET_IP}" 2>&1)"
        echo "$nmap_out"
        open="$(echo "$nmap_out" | grep -c '/tcp\s\+open\b')"
    else
        echo "(nmap not found, using fallback port probe)"
        local port
        for port in 22 21 "${TARGET_PORT}"; do
            if recon_probe_port "${TARGET_IP}" "${port}"; then
                echo "[OPEN] ${TARGET_IP}:${port}"
                open=$((open + 1))
            else
                echo "[CLOSED] ${TARGET_IP}:${port}"
            fi
        done
        echo "--- HTTP banner ---"
        curl -s -I "http://${TARGET_IP}:${TARGET_PORT}/" 2>/dev/null | head -5
    fi
    if [ "$open" -gt 0 ]; then
        results_record "recon" "SUCCESS" "quiet" "scan completed against ${TARGET_IP}"
    else
        results_record "recon" "FAILED" "quiet" "no open ports found against ${TARGET_IP}"
    fi
}
