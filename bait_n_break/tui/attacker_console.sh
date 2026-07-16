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
        sleep 1
    fi

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
    source "${BNB_ROOT}/bait_n_break/attacker/lib_malware__C2.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_results.sh"

    TUI_HEADER_TITLE="bait-n-break"
    TUI_CURSOR_VECTOR=0

    local _C1=6 _C2=32 _C3=20 _C4=8

    local -a VEC_NAME=()
    local -a VEC_DESC=()
    local -a VEC_OPSEC=()
    local -a VEC_RESULT=()
    local VEC_COUNT=0

    _init_vectors() {
        VEC_NAME=()
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
            "CVE-2015-3306 ProFTPD|mod_copy file copy|quiet"
            "CVE-2019-15107 Webmin|password_change.cgi CMDi|medium"
            "CVE-2020-1938 Tomcat Ghostcat|AJP file read -> RCE|medium"
            "Log4Shell Pattern|JNDI injection /api/log|medium"
            "Spring4Shell Pattern|param binding -> file write|medium"
            "Struts2 Pattern Upload|path traversal upload|loud"
            "CVE-2021-4034 Polkit LPE|pkexec arg injection|quiet"
            "Crawler / Bait Exfil|50-path wordlist scan|quiet"
            "Post-Exploitation|LFI/SSRF/XXE/IDOR/chains|loud"
            "Malware / C2|ransomware/beacon/deface|medium"
        )
        VEC_COUNT="${#vectors[@]}"
        local i=0
        for v in "${vectors[@]}"; do
            VEC_NAME[$i]="${v%%|*}"; local r="${v#*|}"
            VEC_DESC[$i]="${r%%|*}"; VEC_OPSEC[$i]="${r##*|}"
            VEC_RESULT[$i]="---"
            i=$((i + 1))
        done
    }

    _load_result_status() {
        if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
            return
        fi
        local i
        local -a key_map=( recon "bruteforce" "exploit_sqli" "exploit_command" "exploit_webshell" "exploit_xss" "exploit_apache" "exploit_shellshock" "exploit_proftpd" "exploit_webmin" "exploit_ghostcat" "exploit_log4shell" "exploit_spring4shell" "exploit_struts" "exploit_polkit" "crawler" "post_exploit" "malware" )
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

    _draw_table() {
        local w="$TUI_TERM_W"
        local h="$TUI_TERM_H"
        local sel="$TUI_CURSOR_VECTOR"

        tui_draw_header "" "$TUI_HEADER_STATUS"
        _draw_target_line

        local table_y=3
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

        # separator before actions
        local sep_y=$((table_y + 3 + VEC_COUNT))
        _table_border "$sep_y" 0 "$total_w" "+" "+" "+" "-"

        # action rows
        local actions=(
            "A|Run All Scenarios (kill-chain)"
            "C|Run All CVEs"
        )
        local ai
        for ((ai = 0; ai < 2; ai++)); do
            local act_line="${actions[$ai]}"
            local act_key="${act_line%%|*}"; local act_desc="${act_line##*|}"
            local act_y=$((sep_y + 1 + ai))
            tput cup "$act_y" 0
            if [ "$((VEC_COUNT + ai))" = "$sel" ]; then
                printf '\033[7m|  %s  | %-*s | %*s | %*s |\033[0m' \
                    "$act_key" "$((_C2 - 2))" "$act_desc" "$_C3" "" "$_C4" ""
            else
                printf '|  %s  | %-*s | %*s | %*s |' \
                    "$act_key" "$((_C2 - 2))" "$act_desc" "$_C3" "" "$_C4" ""
            fi
        done

        # bottom border
        _table_border $((sep_y + 3)) 0 "$total_w" "+" "+" "+" "-"

        tui_draw_footer
    }

    _table_border() {
        local y="$1" x="$2" w="$3" l="$4" m="$5" r="$6" c="$7"
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
        tput cup 2 0
        printf '\033[7m  TARGET: %-18s [%s]%*s[%s]\033[0m' "$ip" "$tp" "$((w - ${#ip} - ${#tp} - ${#nat} - 22))" "" "$nat"
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
            9)  _run_exploit_with_output "CVE-2015-3306" exploit_proftpd_3306 2>/dev/null || true ;;
            10) _run_exploit_with_output "CVE-2019-15107" exploit_webmin_15107 2>/dev/null || true ;;
            11) _run_exploit_with_output "CVE-2020-1938" exploit_ghostcat_1938 2>/dev/null || true ;;
            12) _run_exploit_with_output "Log4Shell Pattern" exploit_log4shell_pattern 2>/dev/null || true ;;
            13) _run_exploit_with_output "Spring4Shell" exploit_spring4shell_pattern 2>/dev/null || true ;;
            14) _run_exploit_with_output "Struts2 Upload" exploit_struts_upload_pattern 2>/dev/null || true ;;
            15) _run_exploit_with_output "Polkit LPE" exploit_polkit_4034 2>/dev/null || true ;;
            16) _run_exploit_with_output "Crawler" crawl_all 2>/dev/null || true ;;
            17) _run_exploit_with_output "Post-Exploit" post_exploit_all 2>/dev/null || true ;;
            18) _run_exploit_with_output "Malware/C2" malware__C2_all 2>/dev/null || true ;;
            A|a)
                _run_exploit_with_output "Reconnaissance" recon_scan
                exploit_ghostcat_1938 >/dev/null 2>&1 || true
                exploit_shellshock_6271 >/dev/null 2>&1 || true
                exploit_apache_41773 >/dev/null 2>&1 || true
                exploit_proftpd_3306 >/dev/null 2>&1 || true
                exploit_webmin_15107 >/dev/null 2>&1 || true
                exploit_log4shell_pattern >/dev/null 2>&1 || true
                exploit_spring4shell_pattern >/dev/null 2>&1 || true
                exploit_struts_upload_pattern >/dev/null 2>&1 || true
                exploit_sqli >/dev/null 2>&1 || true
                exploit_command_injection >/dev/null 2>&1 || true
                exploit_webshell_deploy >/dev/null 2>&1 || true
                exploit_xss_poc >/dev/null 2>&1 || true
                bruteforce_ssh >/dev/null 2>&1 || true
                bruteforce_ftp >/dev/null 2>&1 || true
                bruteforce_http >/dev/null 2>&1 || true
                exploit_polkit_4034 >/dev/null 2>&1 || true
                crawl_all >/dev/null 2>&1 || true
                post_exploit_all >/dev/null 2>&1 || true
                malware__C2_all >/dev/null 2>&1 || true
                _refresh_results_panel
                _load_result_status
                TUI_HEADER_STATUS="Connected"
                _draw_table
                ;;
            C|c)
                exploit_ghostcat_1938 >/dev/null 2>&1 || true
                exploit_shellshock_6271 >/dev/null 2>&1 || true
                exploit_apache_41773 >/dev/null 2>&1 || true
                exploit_proftpd_3306 >/dev/null 2>&1 || true
                exploit_webmin_15107 >/dev/null 2>&1 || true
                exploit_log4shell_pattern >/dev/null 2>&1 || true
                exploit_spring4shell_pattern >/dev/null 2>&1 || true
                exploit_struts_upload_pattern >/dev/null 2>&1 || true
                exploit_polkit_4034 >/dev/null 2>&1 || true
                _refresh_results_panel
                _load_result_status
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
                if [ "$TUI_CURSOR_VECTOR" -lt "$((VEC_COUNT + 1))" ]; then
                    TUI_CURSOR_VECTOR=$((TUI_CURSOR_VECTOR + 1))
                    _draw_table
                fi
                ;;
            ENTER)
                if [ "$TUI_CURSOR_VECTOR" -lt "$VEC_COUNT" ]; then
                    local sel=$((TUI_CURSOR_VECTOR + 1))
                    _execute_vector "$sel"
                elif [ "$TUI_CURSOR_VECTOR" = "$VEC_COUNT" ]; then
                    _execute_vector "A"
                elif [ "$TUI_CURSOR_VECTOR" = "$((VEC_COUNT + 1))" ]; then
                    _execute_vector "C"
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
                TUI_CURSOR_VECTOR="$VEC_COUNT"
                _execute_vector "A"
                ;;
            C|c)
                TUI_CURSOR_VECTOR="$((VEC_COUNT + 1))"
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
