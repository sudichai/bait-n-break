#!/usr/bin/env bash
# Attacker console — full-screen attack table in idle mode, 2-panel during attacks.
# Arrow-key navigation with highlight, IP input modal on entry.
# Falls back to whiptail/dialog if terminal is too small.
# Sourced, not executed.

attacker_console() {
    # shellcheck source=bait_n_break/attacker/lib_target.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_target.sh"

    # --- IP Target Input (before TUI) ---
    if [ -z "${TARGET_IP:-}" ]; then
        local saved
        saved="$(state_get_target 2>/dev/null)"
        if [ -n "$saved" ]; then
            TARGET_IP="$(echo "$saved" | cut -d' ' -f1)"
            TARGET_PORT="$(echo "$saved" | cut -d' ' -f2)"
        fi
    fi

    if [ -z "${TARGET_IP:-}" ]; then
        clear
        echo ""
        echo "  +-------------------------------------------+"
        echo "  |         bait-n-break Attacker Console      |"
        echo "  +-------------------------------------------+"
        echo ""
        echo "  No target configured."
        echo ""
        local target_ip
        while true; do
            printf "  Enter Target IP: "
            read -r target_ip
            if target_is_valid_ip "$target_ip"; then
                TARGET_IP="$target_ip"
                TARGET_PORT="${TARGET_PORT:-8080}"
                state_set_target "$TARGET_IP" "${TARGET_PORT:-8080}"
                break
            else
                echo "  Invalid IPv4 address. Try again."
                echo ""
            fi
        done
        echo ""
        echo "  Target set: ${TARGET_IP}:${TARGET_PORT:-8080}"
    fi

    echo ""
    read -r -p "  Press any key to enter attack console..." _

    # --- TUI Init ---
    # shellcheck source=bait_n_break/tui/ansi_tui.sh
    source "${BNB_ROOT}/bait_n_break/tui/ansi_tui.sh"

    if ! tui_init; then
        source "${BNB_ROOT}/bait_n_break/tui/attacker_console_fallback.sh"
        _attacker_console_fallback
        return
    fi
    trap 'tui_cleanup' EXIT INT

    source "${BNB_ROOT}/bait_n_break/attacker/lib_recon.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_bruteforce.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_web_exploit.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_cve_exploits.sh" 2>/dev/null
    source "${BNB_ROOT}/bait_n_break/attacker/lib_crawler.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_post_exploit.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_malware_c2.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_results.sh"

    crawl_all() { crawl_leaked_files 2>/dev/null; }
    malware_c2_all() { c2_beacon_check 2>/dev/null; ransomware_trigger 2>/dev/null; }
    post_exploit_all() {
        exploit_lfi 2>/dev/null; exploit_ssrf 2>/dev/null; exploit_xxe 2>/dev/null
        exploit_idor 2>/dev/null; exploit_pickle_deser 2>/dev/null; exploit_docker_escape 2>/dev/null
        exploit_persist_ssh 2>/dev/null; exploit_persist_cron 2>/dev/null
        exploit_cred_harvest 2>/dev/null; exploit_dns_exfil 2>/dev/null
    }

    TUI_HEADER_TITLE="bait-n-break"
    TUI_CURSOR_VECTOR=0

    local _C1=6 _C2=38 _C3=14 _C4=8

    local -a VEC_DESC=()
    local -a VEC_OPSEC=()
    local -a VEC_RESULT=()
    local VEC_COUNT=0

    _init_vectors() {
        VEC_DESC=()
        VEC_OPSEC=()
        VEC_RESULT=()
        local vectors=(
            "Reconnaissance|nmap scan + service detection|quiet"
            "Brute Force|SSH/FTP/HTTP (15 credentials)|loud"
            "SQL Injection|sqlmap + manual payloads|quiet"
            "Command Injection|5 payload variants|medium"
            "Webshell Deploy|upload + execute|loud"
            "XSS PoC|reflected + stored XSS|quiet"
            "CVE-2021-41773 Apache|path traversal -> RCE|medium"
            "CVE-2014-6271 Shellshock|bash CGI injection|loud"
            "CVE-2019-15107 Webmin|password_change.cgi CMDi|medium"
            "CVE-2020-1938 Tomcat Ghostcat|AJP file read -> RCE|medium"
            "Log4Shell Pattern|JNDI injection /api/log|medium"
            "Spring4Shell Pattern|param binding -> file write|medium"
            "Struts2 Pattern Upload|path traversal upload|loud"
            "CVE-2021-4034 Polkit LPE|pkexec arg injection|quiet"
            "Crawler / Bait Exfil|50-path wordlist scan|quiet"
            "Post-Exploitation|LFI/SSRF/XXE/IDOR/chains|loud"
            "Malware / C2|ransomware/beacon/deface|medium"
            "--- RUN ALL SCENARIOS ---|kill-chain ordered Recon->Impact| "
            "--- RUN ALL CVEs ---|all CVE exploits| "
        )
        VEC_COUNT="${#vectors[@]}"
        local i=0
        for v in "${vectors[@]}"; do
            local name="${v%%|*}"; local r="${v#*|}"
            VEC_DESC[$i]="${name} - ${r%%|*}"; VEC_OPSEC[$i]="${r##*|}"
            VEC_RESULT[$i]="---"
            i=$((i + 1))
        done
    }

    _load_result_status() {
        if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
            return
        fi
        local i
        local -a key_map=( recon "bruteforce" "exploit_sqli" "exploit_command" "exploit_webshell" "exploit_xss" "exploit_apache" "exploit_shellshock" "exploit_webmin" "exploit_ghostcat" "exploit_log4shell" "exploit_spring4shell" "exploit_struts" "exploit_polkit" "crawler" "post_exploit" "malware" "runall" "runallcve" )
        for ((i = 0; i < VEC_COUNT; i++)); do
            local key="${key_map[$i]}"
            local found
            found="$(grep -i "$key" "${BNB_ATTACK_RESULTS}" 2>/dev/null | tail -1)"
            if echo "$found" | grep -q "SUCCESS\|VULNERABLE"; then
                VEC_RESULT[$i]="VULN"
            elif echo "$found" | grep -q "FAILED"; then
                VEC_RESULT[$i]="FAIL"
            else
                VEC_RESULT[$i]="---"
            fi
        done
    }

    _probe_cve_ports() {
        [ -z "${TARGET_IP:-}" ] && return
        (exec 3<>/dev/tcp/${TARGET_IP}/8081) 2>/dev/null && VEC_RESULT[6]="[UP]"; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
        (exec 3<>/dev/tcp/${TARGET_IP}/8082) 2>/dev/null && VEC_RESULT[7]="[UP]"; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
        (exec 3<>/dev/tcp/${TARGET_IP}/${BNB_CVE_WEBMIN_PORT:-10000}) 2>/dev/null && VEC_RESULT[8]="[UP]"; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
        (exec 3<>/dev/tcp/${TARGET_IP}/${BNB_CVE_TOMCAT_HTTP_PORT:-8083}) 2>/dev/null && VEC_RESULT[9]="[UP]"; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
        (exec 3<>/dev/tcp/${TARGET_IP}/8080) 2>/dev/null && VEC_RESULT[10]="[UP]" && VEC_RESULT[11]="[UP]" && VEC_RESULT[12]="[UP]"; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    }

    _draw_table() {
        local w="$TUI_TERM_W"
        local h="$TUI_TERM_H"
        local sel="$TUI_CURSOR_VECTOR"

        _draw_target_line

        local table_y=2
        local total_w=$((_C1 + _C2 + _C3 + _C4 + 5))

        # top border
        _table_border "$table_y" 0 "$total_w" "+" "+" "+" "-"

        # header
        tput cup $((table_y + 1)) 0
        printf '| %-*s | %-*s | %-*s | %-*s |' \
            "$_C1" "#" "$_C2" "ATTACK VECTOR" "$_C3" "OPSEC" "$_C4" "RESULT"

        # separator
        _table_border $((table_y + 2)) 0 "$total_w" "+" "+" "+" "-"

        local i line_y
        for ((i = 0; i < VEC_COUNT; i++)); do
            line_y=$((table_y + 3 + i))
            local num="$(printf '%2d' $((i + 1)))"
            local desc="${VEC_DESC[$i]}"
            local ops="${VEC_OPSEC[$i]}"
            local res="${VEC_RESULT[$i]}"

            tput cup "$line_y" 0
            if [ "$i" = "$sel" ]; then
                printf '\033[7m| %s | %-*s | %-*s | %-*s |\033[0m' \
                    "$num" "$((_C2 - 2))" "$desc" "$((_C3 - 2))" "$ops" "$((_C4 - 2))" "$res"
            else
                printf '| %s | %-*s | %-*s | %-*s |' \
                    "$num" "$((_C2 - 2))" "$desc" "$((_C3 - 2))" "$ops" "$((_C4 - 2))" "$res"
            fi
        done

        tui_draw_footer
    }

    _table_border() {
        local y="$1" x="$2" l="$4" m="$5" r="$6" c="$7"
        tput cup "$y" "$x"
        printf '%s' "$l"
        local i
        for ((i = 0; i < _C1 + 2; i++)); do printf '%s' "$c"; done
        printf '%s' "$m"
        for ((i = 0; i < _C2 + 2; i++)); do printf '%s' "$c"; done
        printf '%s' "$m"
        for ((i = 0; i < _C3 + 2; i++)); do printf '%s' "$c"; done
        printf '%s' "$m"
        for ((i = 0; i < _C4 + 2; i++)); do printf '%s' "$c"; done
        printf '%s' "$r"
    }

    _draw_target_line() {
        local ip="${TUI_TARGET_IP:-}" tp="${TUI_TARGET_TYPE:-Web_Server}" nat="${TUI_TARGET_NAT:-}"
        local w="$TUI_TERM_W"
        local status="${TUI_HEADER_STATUS}"
        local label="[bait-n-break]"
        tput cup 0 0
        printf '\033[7m  %s   TARGET: %-15s [%s]%*s[%s]\033[0m' "$label" "$ip" "$tp" "$((w - ${#label} - ${#ip} - ${#tp} - ${#status} - 30))" "" "$status"
    }

    _run_exploit_with_output() {
        local name="$1"
        shift
        local panel_y=4
        local panel_h=$(( TUI_TERM_H - panel_y - 1 ))
        local panel_w=$(( (TUI_TERM_W - 2) / 3 ))
        local exec_w=$(( panel_w * 2 + 1 ))
        local vuln_w=$panel_w

        TUI_PANEL_MID=("" "[*] Executing: ${name}" "----------------------------------------")
        TUI_HEADER_STATUS="Attacking..."

        local tmpfile
        tmpfile="$(mktemp)"

        while IFS= read -r line; do
            echo "$line" >> "$tmpfile"
            TUI_PANEL_MID+=("${line}")
            if [ "${#TUI_PANEL_MID[@]}" -gt "$((panel_h - 3))" ]; then
                TUI_PANEL_MID=("${TUI_PANEL_MID[@]: -$((panel_h - 3))}")
            fi
            tui_draw_header
            tui_draw_target_bar
            tui_draw_panel 0 "$panel_y" "$exec_w" "$panel_h" "EXECUTE / LOGS" TUI_PANEL_MID
            tui_draw_panel "$((exec_w + 1))" "$panel_y" "$vuln_w" "$panel_h" "VULNERABILITIES FOUND" TUI_PANEL_RIGHT
            tui_draw_footer
        done < <("$@" 2>&1)

        _refresh_results_panel
        _load_result_status
        rm -f "$tmpfile"
        TUI_HEADER_STATUS="Connected"

        # pause so user can review output
        TUI_PANEL_MID+=("" "--- Press any key to continue ---")
        tui_draw_panel 0 4 "$exec_w" "$panel_h" "EXECUTE / LOGS" TUI_PANEL_MID
        tui_draw_panel "$((exec_w + 1))" 4 "$vuln_w" "$panel_h" "VULNERABILITIES FOUND" TUI_PANEL_RIGHT
        tui_draw_footer
        read -r -n1 -s _

        clear
        _draw_table
    }

    _refresh_results_panel() {
        TUI_PANEL_RIGHT=()
        if [ -f "${BNB_ATTACK_RESULTS}" ]; then
            while IFS= read -r line; do
                local display="${line:0:70}"
                display="$(echo "$display" | sed 's/\[[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} /[/')"
                TUI_PANEL_RIGHT+=("  ${display:0:60}")
            done < "${BNB_ATTACK_RESULTS}"
        fi
        if [ "${#TUI_PANEL_RIGHT[@]}" -eq 0 ]; then
            TUI_PANEL_RIGHT=("  No results yet. Run an attack vector.")
        fi
    }

    _execute_vector() {
        local choice="$1"
        case "$choice" in
            1)  _run_exploit_with_output "Reconnaissance" recon_scan ;;
            2)  _run_exploit_with_output "Brute Force" bash -c "bruteforce_ssh; bruteforce_ftp; bruteforce_http" ;;
            3)  _run_exploit_with_output "SQL Injection" exploit_sqli ;;
            4)  _run_exploit_with_output "Command Injection" exploit_command_injection ;;
            5)  _run_exploit_with_output "Webshell Deploy" exploit_webshell_deploy ;;
            6)  _run_exploit_with_output "XSS PoC" exploit_xss_poc ;;
            7)  _run_exploit_with_output "CVE-2021-41773" exploit_apache_41773 2>/dev/null || true ;;
            8)  _run_exploit_with_output "CVE-2014-6271" exploit_shellshock_6271 2>/dev/null || true ;;
            9)  _run_exploit_with_output "CVE-2019-15107" exploit_webmin_15107 2>/dev/null || true ;;
            10) _run_exploit_with_output "CVE-2020-1938" exploit_ghostcat_1938 2>/dev/null || true ;;
            11) _run_exploit_with_output "Log4Shell Pattern" exploit_log4shell_pattern 2>/dev/null || true ;;
            12) _run_exploit_with_output "Spring4Shell" exploit_spring4shell_pattern 2>/dev/null || true ;;
            13) _run_exploit_with_output "Struts2 Upload" exploit_struts_upload_pattern 2>/dev/null || true ;;
            14) _run_exploit_with_output "Polkit LPE" exploit_polkit_4034 2>/dev/null || true ;;
            15) _run_exploit_with_output "Crawler" crawl_all 2>/dev/null || true ;;
            16) _run_exploit_with_output "Post-Exploit" post_exploit_all 2>/dev/null || true ;;
            17) _run_exploit_with_output "Malware/C2" malware_c2_all 2>/dev/null || true ;;
            18) _execute_vector "A" ;;
            19) _execute_vector "C" ;;
            A|a)
                _run_exploit_with_output "Reconnaissance" recon_scan
                TUI_PANEL_MID=("" "[*] Phase: CVE Init Access" "")
                tui_draw_panel 0 4 "$(( (TUI_TERM_W - 2) / 3 * 2 + 1 ))" "$(( TUI_TERM_H - 5 ))" "EXECUTE / LOGS" TUI_PANEL_MID
                timeout 15 exploit_ghostcat_1938 >/dev/null 2>&1 || true
                timeout 15 exploit_shellshock_6271 >/dev/null 2>&1 || true
                timeout 15 exploit_apache_41773 >/dev/null 2>&1 || true
                timeout 15 exploit_webmin_15107 >/dev/null 2>&1 || true
                timeout 15 exploit_log4shell_pattern >/dev/null 2>&1 || true
                timeout 15 exploit_spring4shell_pattern >/dev/null 2>&1 || true
                timeout 15 exploit_struts_upload_pattern >/dev/null 2>&1 || true
                TUI_PANEL_MID=("" "[*] Phase: Web Exploitation" "")
                tui_draw_panel 0 4 "$(( (TUI_TERM_W - 2) / 3 * 2 + 1 ))" "$(( TUI_TERM_H - 5 ))" "EXECUTE / LOGS" TUI_PANEL_MID
                timeout 15 exploit_sqli >/dev/null 2>&1 || true
                timeout 15 exploit_command_injection >/dev/null 2>&1 || true
                timeout 15 exploit_webshell_deploy >/dev/null 2>&1 || true
                timeout 15 exploit_xss_poc >/dev/null 2>&1 || true
                TUI_PANEL_MID=("" "[*] Phase: Brute Force" "")
                tui_draw_panel 0 4 "$(( (TUI_TERM_W - 2) / 3 * 2 + 1 ))" "$(( TUI_TERM_H - 5 ))" "EXECUTE / LOGS" TUI_PANEL_MID
                timeout 15 bruteforce_ssh >/dev/null 2>&1 || true
                timeout 15 bruteforce_ftp >/dev/null 2>&1 || true
                timeout 15 bruteforce_http >/dev/null 2>&1 || true
                TUI_PANEL_MID=("" "[*] Phase: PrivEsc + Post-Exploit" "")
                tui_draw_panel 0 4 "$(( (TUI_TERM_W - 2) / 3 * 2 + 1 ))" "$(( TUI_TERM_H - 5 ))" "EXECUTE / LOGS" TUI_PANEL_MID
                timeout 15 exploit_polkit_4034 >/dev/null 2>&1 || true
                timeout 15 crawl_all >/dev/null 2>&1 || true
                timeout 15 post_exploit_all >/dev/null 2>&1 || true
                timeout 15 malware_c2_all >/dev/null 2>&1 || true
                _refresh_results_panel
                _load_result_status
                TUI_HEADER_STATUS="Connected"
                clear
                _draw_table
                ;;
            C|c)
                TUI_PANEL_MID=("" "[*] Running All CVEs..." "")
                tui_draw_panel 0 4 "$(( (TUI_TERM_W - 2) / 3 * 2 + 1 ))" "$(( TUI_TERM_H - 5 ))" "EXECUTE / LOGS" TUI_PANEL_MID
                timeout 15 exploit_ghostcat_1938 >/dev/null 2>&1 || true
                timeout 15 exploit_shellshock_6271 >/dev/null 2>&1 || true
                timeout 15 exploit_apache_41773 >/dev/null 2>&1 || true
                timeout 15 exploit_webmin_15107 >/dev/null 2>&1 || true
                timeout 15 exploit_log4shell_pattern >/dev/null 2>&1 || true
                timeout 15 exploit_spring4shell_pattern >/dev/null 2>&1 || true
                timeout 15 exploit_struts_upload_pattern >/dev/null 2>&1 || true
                timeout 15 exploit_polkit_4034 >/dev/null 2>&1 || true
                _refresh_results_panel
                _load_result_status
                TUI_HEADER_STATUS="Connected"
                clear
                _draw_table
                ;;
            H|h) tui_cleanup; return ;;
        esac
    }

    # --- Init ---
    _init_vectors

    if [ -f "${BNB_TARGET_FILE}" ]; then
        local saved; saved="$(cat "${BNB_TARGET_FILE}")"
        TUI_TARGET_IP="$(echo "$saved" | cut -d' ' -f1)"
        TARGET_PORT="$(echo "$saved" | cut -d' ' -f2)"
        TARGET_IP="$TUI_TARGET_IP"
        TUI_TARGET_NAT="${TUI_TARGET_IP}"
        TUI_HEADER_STATUS="Connected"
    else
        TUI_HEADER_STATUS="No target"
    fi

    TUI_FOOTER_TEXT="  <H> HOME | <T> TARGET | <A> RUN ALL | <C> RUN CVEs | <L> LOGS | <Q> BACK"
    _load_result_status
    _probe_cve_ports
    _draw_table

    # --- Event Loop ---
    while [ "$TUI_RUNNING" -eq 1 ]; do
        local key
        key="$(tui_read_key)" || { sleep 0.05; continue; }

        case "$key" in
            UP)
                if [ "$TUI_CURSOR_VECTOR" -gt 0 ]; then
                    TUI_CURSOR_VECTOR=$((TUI_CURSOR_VECTOR - 1))
                    _draw_table
                fi
                ;;
            DOWN)
                if [ "$TUI_CURSOR_VECTOR" -lt "$((VEC_COUNT - 1))" ]; then
                    TUI_CURSOR_VECTOR=$((TUI_CURSOR_VECTOR + 1))
                    _draw_table
                fi
                ;;
            ENTER)
                if [ "$TUI_CURSOR_VECTOR" -lt "$VEC_COUNT" ]; then
                    local sel=$((TUI_CURSOR_VECTOR + 1))
                    _execute_vector "$sel"
                fi
                ;;
            [1-9])
                local num="$key"
                if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le 9 ] 2>/dev/null; then
                    TUI_CURSOR_VECTOR=$((num - 1))
                    _draw_table
                    _execute_vector "$num"
                fi
                ;;
            A|a)
                _execute_vector "A"
                ;;
            C|c)
                _execute_vector "C"
                ;;
            T|t)
                tui_cleanup
                target_prompt || true
                tui_init || return
                if [ -f "${BNB_TARGET_FILE}" ]; then
                    local s; s="$(cat "${BNB_TARGET_FILE}")"
                    TUI_TARGET_IP="$(echo "$s" | cut -d' ' -f1)"
                    TARGET_IP="$TUI_TARGET_IP"
                    TUI_TARGET_NAT="${TUI_TARGET_IP}"
                fi
                TUI_HEADER_STATUS="Connected"
                _draw_table
                ;;
            L|l)
                tui_cleanup
                if [ -f "${BNB_ATTACK_RESULTS}" ]; then
                    cat "${BNB_ATTACK_RESULTS}" | less
                else
                    echo "No results log yet."
                    read -r -p "Press Enter to continue..." _
                fi
                tui_init || return
                _draw_table
                ;;
            H|h|ESC|Q|q)
                tui_cleanup
                return
                ;;
        esac
    done
}
