#!/usr/bin/env bash
# Attacker console — custom ANSI TUI with persistent 3-panel dashboard.
# Falls back to whiptail/dialog if terminal is too small.
# Sourced, not executed.

attacker_console() {
    # shellcheck source=bait_n_break/tui/ansi_tui.sh
    source "${BNB_ROOT}/bait_n_break/tui/ansi_tui.sh"

    if ! tui_init; then
        source "${BNB_ROOT}/bait_n_break/tui/attacker_console_fallback.sh"
        _attacker_console_fallback
        return
    fi
    trap 'tui_cleanup' EXIT INT

    # shellcheck source=bait_n_break/attacker/lib_target.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_target.sh"
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
            "[1] Reconnaissance"
            "[2] Brute Force (SSH/FTP/HTTP)"
            "[3] SQL Injection"
            "[4] Command Injection"
            "[5] Webshell Deploy"
            "[6] XSS PoC"
            "[7] CVE-2021-41773 Apache Path Traversal"
            "[8] CVE-2014-6271 Shellshock"
            "[9] CVE-2015-3306 ProFTPD RCE"
            "[10] CVE-2019-15107 Webmin RCE"
            "[11] CVE-2020-1938 Tomcat Ghostcat"
            "[12] Log4Shell Pattern JNDI"
            "[13] Spring4Shell Pattern Binding"
            "[14] Struts2 Pattern Upload"
            "[15] CVE-2021-4034 Polkit LPE"
            "[16] Crawler / Bait Exfiltration"
            "[17] Post-Exploitation"
            "[18] Malware / C2 Simulation"
            "[A] Run All Scenarios"
            "[C] Run All CVEs"
            "[H] Back to Main Menu"
        )
        for v in "${vectors[@]}"; do
            TUI_PANEL_LEFT+=("$v")
        done
    }

    _run_exploit_with_output() {
        local name="$1"
        shift
        TUI_PANEL_RIGHT=("" "[*] Executing: ${name}" "----------------------------------------")

        local tmpfile
        tmpfile="$(mktemp)"

        # Run the command and capture output in background
        {
            "$@" 2>&1
        } | while IFS= read -r line; do
            echo "$line" >> "$tmpfile"
            TUI_PANEL_RIGHT+=("${line}")
            if [ "${#TUI_PANEL_RIGHT[@]}" -gt "$((TUI_TERM_H - 6))" ]; then
                TUI_PANEL_RIGHT=("${TUI_PANEL_RIGHT[@]: -$((TUI_TERM_H - 6))}")
            fi
            tui_refresh
        done

        _refresh_results_panel
        rm -f "$tmpfile"
        tui_refresh
    }

    _refresh_results_panel() {
        TUI_PANEL_MID=()
        if [ -f "${BNB_ATTACK_RESULTS}" ]; then
            while IFS= read -r line; do
                TUI_PANEL_MID+=("  ${line:0:60}")
            done < "${BNB_ATTACK_RESULTS}"
        fi
        if [ "${#TUI_PANEL_MID[@]}" -eq 0 ]; then
            TUI_PANEL_MID=("  No results yet. Run an attack vector.")
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
                TUI_PANEL_RIGHT=("" "[*] Phase 2: CVE Initial Access" "")
                tui_refresh
                exploit_ghostcat_1938 2>/dev/null
                exploit_shellshock_6271 2>/dev/null
                exploit_apache_41773 2>/dev/null
                exploit_proftpd_3306 2>/dev/null
                exploit_webmin_15107 2>/dev/null
                exploit_log4shell_pattern 2>/dev/null
                exploit_spring4shell_pattern 2>/dev/null
                exploit_struts_upload_pattern 2>/dev/null
                TUI_PANEL_RIGHT=("" "[*] Phase 3: Web Exploitation" "")
                tui_refresh
                exploit_sqli 2>/dev/null
                exploit_command_injection 2>/dev/null
                exploit_webshell_deploy 2>/dev/null
                exploit_xss_poc 2>/dev/null
                TUI_PANEL_RIGHT=("" "[*] Phase 4: Brute Force" "")
                tui_refresh
                bruteforce_ssh 2>/dev/null
                bruteforce_ftp 2>/dev/null
                bruteforce_http 2>/dev/null
                TUI_PANEL_RIGHT=("" "[*] Phase 5: PrivEsc + Post-Exploit" "")
                tui_refresh
                exploit_polkit_4034 2>/dev/null
                crawl_all 2>/dev/null
                post_exploit_all 2>/dev/null
                malware_c2_all 2>/dev/null
                _refresh_results_panel
                TUI_PANEL_RIGHT=("" "[*] Run All Scenarios complete" "")
                tui_refresh
                ;;
            C|c)
                _run_exploit_with_output "CVE-2020-1938 Ghostcat" exploit_ghostcat_1938 2>/dev/null
                sleep 1
                exploit_shellshock_6271 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                sleep 1
                exploit_apache_41773 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                sleep 1
                exploit_proftpd_3306 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                sleep 1
                exploit_webmin_15107 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                sleep 1
                exploit_log4shell_pattern 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                sleep 1
                exploit_spring4shell_pattern 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                sleep 1
                exploit_struts_upload_pattern 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                sleep 1
                exploit_polkit_4034 2>/dev/null | while IFS= read -r l; do TUI_PANEL_RIGHT+=("$l"); done
                _refresh_results_panel
                TUI_PANEL_RIGHT=("" "[*] All CVEs complete" "")
                tui_refresh
                ;;
            H|h) tui_cleanup; return ;;
            "")  ;;
            *)  TUI_PANEL_RIGHT+=("[!] Invalid selection: ${choice}") ;;
        esac
    }

    # Main event loop
    _load_target_state
    _build_vector_menu
    _refresh_results_panel
    tui_refresh

    while [ "$TUI_RUNNING" -eq 1 ]; do
        local key
        key="$(tui_read_key)" || { sleep 0.05; continue; }

        case "$key" in
            [1-9]|0)
                local num="$key"
                if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le 18 ] 2>/dev/null; then
                    _execute_vector "$num"
                    tui_refresh
                fi
                ;;
            A|a|C|c)
                _execute_vector "$key"
                tui_refresh
                ;;
            T|t)
                tui_cleanup
                target_prompt || true
                tui_init || return
                _load_target_state
                tui_refresh
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
                ;;
            H|h|"ESC")
                tui_cleanup
                return
                ;;
        esac
    done
}
