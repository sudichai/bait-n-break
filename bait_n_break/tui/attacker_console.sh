#!/usr/bin/env bash
# Attacker console — custom ANSI TUI with persistent 3-panel dashboard.
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

    # shellcheck source=bait_n_break/attacker/lib_recon.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_recon.sh"
    # shellcheck source=bait_n_break/attacker/lib_bruteforce.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_bruteforce.sh"
    # shellcheck source=bait_n_break/attacker/lib_web_exploit.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_web_exploit.sh"
    # shellcheck source=bait_n_break/attacker/lib_cve_exploits.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_cve_exploits.sh" 2>/dev/null
    # shellcheck source=bait_n_break/attacker/lib_crawler.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_crawler.sh"
    # shellcheck source=bait_n_break/attacker/lib_post_exploit.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_post_exploit.sh"
    # shellcheck source=bait_n_break/attacker/lib_malware_c2.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_malware_c2.sh"
    # shellcheck source=bait_n_break/attacker/lib_results.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_results.sh"

    TUI_LEFT_TITLE="ATTACK VECTORS"
    TUI_MID_TITLE="EXECUTE / LOGS"
    TUI_RIGHT_TITLE="VULNERABILITIES FOUND"
    TUI_HEADER_TITLE="HACKER LABS"
    TUI_FOOTER_TEXT="  <H> HOME | <T> TARGET | <A> RUN ALL | <C> RUN CVEs | <L> LOGS | <Q> BACK"
    TUI_USE_ASCII_HEADER=1
    TUI_CURSOR_VECTOR=0

    _load_target_state() {
        if [ -f "${BNB_TARGET_FILE}" ]; then
            local saved
            saved="$(cat "${BNB_TARGET_FILE}")"
            TUI_TARGET_IP="$(echo "$saved" | cut -d' ' -f1)"
            TARGET_PORT="$(echo "$saved" | cut -d' ' -f2)"
            TARGET_IP="$TUI_TARGET_IP"
            TUI_TARGET_TYPE="Web_Server"
            TUI_TARGET_NAT="${TUI_TARGET_IP}"
            TUI_HEADER_STATUS="Connected"
        else
            TUI_HEADER_STATUS="No target"
        fi
    }

    _build_vector_menu() {
        TUI_PANEL_LEFT=()
        local vectors=(
            "Reconnaissance"
            "Brute Force (SSH/FTP/HTTP)"
            "SQL Injection"
            "Command Injection"
            "Webshell Deploy"
            "XSS PoC"
            "CVE-2021-41773 Apache Path Traversal"
            "CVE-2014-6271 Shellshock"
            "CVE-2015-3306 ProFTPD RCE"
            "CVE-2019-15107 Webmin RCE"
            "CVE-2020-1938 Tomcat Ghostcat"
            "Log4Shell Pattern JNDI"
            "Spring4Shell Pattern Binding"
            "Struts2 Pattern Upload"
            "CVE-2021-4034 Polkit LPE"
            "Crawler / Bait Exfiltration"
            "Post-Exploitation"
            "Malware / C2 Simulation"
            "---"
            "[A] Run All Scenarios"
            "[C] Run All CVEs"
            "[H] Back to Main Menu"
        )
        local i=0
        for v in "${vectors[@]}"; do
            local label
            if [ "$v" = "---" ]; then
                label="  ------------------------"
            elif [ "$i" -lt 9 ]; then
                label="  [$(($i + 1))] ${v}"
            else
                label="  ${v}"
            fi
            TUI_PANEL_LEFT+=("$label")
            i=$((i + 1))
        done
        TUI_VECTOR_COUNT=18
    }

    _highlight_current_vector() {
        if [ "$TUI_CURSOR_VECTOR" -ge 0 ] 2>/dev/null && [ "$TUI_CURSOR_VECTOR" -lt 18 ] 2>/dev/null; then
            local panel_w=$(( (TUI_TERM_W - 2) / 3 ))
            local x=1
            local y=$(( 11 + TUI_CURSOR_VECTOR ))
            local line="${TUI_PANEL_LEFT[$TUI_CURSOR_VECTOR]:-}"
            tput cup "$y" "$x"
            printf '\033[7m %-*s \033[0m' "$((panel_w - 2))" "${line:0:$((panel_w - 2))}"
        fi
    }

    _run_exploit_with_output() {
        local name="$1"
        shift
        local panel_y=10
        local panel_h=$(( TUI_TERM_H - panel_y - 1 ))
        TUI_PANEL_MID=("" "[*] Executing: ${name}" "----------------------------------------")

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
            tui_draw_panel 0 "$panel_y" "$(( (TUI_TERM_W - 2) / 3 ))" "$panel_h" "$TUI_LEFT_TITLE" TUI_PANEL_LEFT
            tui_draw_panel "$(( (TUI_TERM_W - 2) / 3 + 1 ))" "$panel_y" "$(( (TUI_TERM_W - 2) / 3 ))" "$panel_h" "$TUI_MID_TITLE" TUI_PANEL_MID
            tui_draw_panel "$(( 2 * (TUI_TERM_W - 2) / 3 + 2 ))" "$panel_y" "$(( (TUI_TERM_W - 2) / 3 ))" "$panel_h" "$TUI_RIGHT_TITLE" TUI_PANEL_RIGHT
            tui_draw_footer
        done < <("$@" 2>&1)

        _refresh_results_panel
        rm -f "$tmpfile"
        tui_refresh
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
            7)  _run_exploit_with_output "CVE-2021-41773" exploit_apache_41773 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            8)  _run_exploit_with_output "CVE-2014-6271" exploit_shellshock_6271 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            9)  _run_exploit_with_output "CVE-2015-3306" exploit_proftpd_3306 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            10) _run_exploit_with_output "CVE-2019-15107" exploit_webmin_15107 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            11) _run_exploit_with_output "CVE-2020-1938" exploit_ghostcat_1938 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            12) _run_exploit_with_output "Log4Shell Pattern" exploit_log4shell_pattern 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            13) _run_exploit_with_output "Spring4Shell Pattern" exploit_spring4shell_pattern 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            14) _run_exploit_with_output "Struts2 Upload" exploit_struts_upload_pattern 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            15) _run_exploit_with_output "Polkit LPE" exploit_polkit_4034 2>/dev/null || echo "[!] CVE exploit module not loaded" ;;
            16) _run_exploit_with_output "Crawler" crawl_all 2>/dev/null || echo "[!] Crawl module not loaded" ;;
            17) _run_exploit_with_output "Post-Exploit" post_exploit_all 2>/dev/null || echo "[!] Post-exploit module not loaded" ;;
            18) _run_exploit_with_output "Malware/C2" malware_c2_all 2>/dev/null || echo "[!] Malware module not loaded" ;;
            A|a)
                _run_exploit_with_output "Reconnaissance" recon_scan
                TUI_PANEL_MID=("" "[*] Phase 2: CVE Initial Access" "")
                tui_refresh
                exploit_ghostcat_1938 >/dev/null 2>&1 || true
                exploit_shellshock_6271 >/dev/null 2>&1 || true
                exploit_apache_41773 >/dev/null 2>&1 || true
                exploit_proftpd_3306 >/dev/null 2>&1 || true
                exploit_webmin_15107 >/dev/null 2>&1 || true
                exploit_log4shell_pattern >/dev/null 2>&1 || true
                exploit_spring4shell_pattern >/dev/null 2>&1 || true
                exploit_struts_upload_pattern >/dev/null 2>&1 || true
                TUI_PANEL_MID=("" "[*] Phase 3: Web Exploitation" "")
                tui_refresh
                exploit_sqli >/dev/null 2>&1 || true
                exploit_command_injection >/dev/null 2>&1 || true
                exploit_webshell_deploy >/dev/null 2>&1 || true
                exploit_xss_poc >/dev/null 2>&1 || true
                TUI_PANEL_MID=("" "[*] Phase 4: Brute Force" "")
                tui_refresh
                bruteforce_ssh >/dev/null 2>&1 || true
                bruteforce_ftp >/dev/null 2>&1 || true
                bruteforce_http >/dev/null 2>&1 || true
                TUI_PANEL_MID=("" "[*] Phase 5: PrivEsc + Post-Exploit" "")
                tui_refresh
                exploit_polkit_4034 >/dev/null 2>&1 || true
                crawl_all >/dev/null 2>&1 || true
                post_exploit_all >/dev/null 2>&1 || true
                malware_c2_all >/dev/null 2>&1 || true
                _refresh_results_panel
                TUI_PANEL_MID=("" "[*] Run All Scenarios complete" "")
                tui_refresh
                ;;
            C|c)
                _run_exploit_with_output "CVE-2020-1938 Ghostcat" exploit_ghostcat_1938 2>/dev/null
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_shellshock_6271 2>/dev/null)
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_apache_41773 2>/dev/null)
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_proftpd_3306 2>/dev/null)
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_webmin_15107 2>/dev/null)
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_log4shell_pattern 2>/dev/null)
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_spring4shell_pattern 2>/dev/null)
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_struts_upload_pattern 2>/dev/null)
                sleep 1
                while IFS= read -r l; do TUI_PANEL_MID+=("$l"); done < <(exploit_polkit_4034 2>/dev/null)
                _refresh_results_panel
                TUI_PANEL_MID=("" "[*] All CVEs complete" "")
                tui_refresh
                ;;
            H|h) tui_cleanup; return ;;
            "")  ;;
            *)  TUI_PANEL_MID+=("[!] Invalid selection: ${choice}") ;;
        esac
    }

    # Main event loop
    _load_target_state
    _build_vector_menu
    _refresh_results_panel
    tui_refresh
    _highlight_current_vector

    while [ "$TUI_RUNNING" -eq 1 ]; do
        local key
        key="$(tui_read_key)" || { sleep 0.05; continue; }

        case "$key" in
            UP)
                if [ "$TUI_CURSOR_VECTOR" -gt 0 ]; then
                    TUI_CURSOR_VECTOR=$((TUI_CURSOR_VECTOR - 1))
                    tui_refresh
                    _highlight_current_vector
                fi
                ;;
            DOWN)
                if [ "$TUI_CURSOR_VECTOR" -lt 17 ]; then
                    TUI_CURSOR_VECTOR=$((TUI_CURSOR_VECTOR + 1))
                    tui_refresh
                    _highlight_current_vector
                fi
                ;;
            "ENTER"|"")
                local sel=$((TUI_CURSOR_VECTOR + 1))
                _execute_vector "$sel"
                _build_vector_menu
                tui_refresh
                _highlight_current_vector
                ;;
            [1-9])
                local num="$key"
                if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le 9 ] 2>/dev/null; then
                    TUI_CURSOR_VECTOR=$((num - 1))
                    _execute_vector "$num"
                    _build_vector_menu
                    tui_refresh
                    _highlight_current_vector
                fi
                ;;
            A|a)
                TUI_CURSOR_VECTOR=18
                _execute_vector "A"
                _build_vector_menu
                tui_refresh
                _highlight_current_vector
                ;;
            C|c)
                TUI_CURSOR_VECTOR=19
                _execute_vector "C"
                _build_vector_menu
                tui_refresh
                _highlight_current_vector
                ;;
            T|t)
                tui_cleanup
                target_prompt || true
                tui_init || return
                _load_target_state
                tui_refresh
                _highlight_current_vector
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
                tui_refresh
                _highlight_current_vector
                ;;
            H|h|"ESC")
                tui_cleanup
                return
                ;;
        esac
    done
}
