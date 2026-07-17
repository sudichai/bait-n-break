#!/usr/bin/env bash
# Attacker console -- whiptail menu with live terminal execution, status icons,
# TOTAL stats, and results summary. Sourced, not executed.

attacker_console() {
    # --- Part A: Initialization ---
    source "${BNB_ROOT}/bait_n_break/attacker/lib_target.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_engine.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_traffic.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_payloads.sh"

    if ! target_ensure_set; then
        ui_error "Target Not Set" "No target IP configured. Cannot launch attacker console."
        return 1
    fi

    source "${BNB_ROOT}/bait_n_break/attacker/lib_recon.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_bruteforce.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_web_exploit.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_cve_exploits.sh" 2>/dev/null || true
    source "${BNB_ROOT}/bait_n_break/attacker/lib_crawler.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_post_exploit.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_malware_c2.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_results.sh"

    results_init

    crawl_all() { crawl_leaked_files 2>/dev/null || true; }
    bruteforce_all() { bruteforce_ssh 2>/dev/null || true; bruteforce_ftp 2>/dev/null || true; bruteforce_http 2>/dev/null || true; }
    malware_c2_all() { c2_beacon_check 2>/dev/null || true; ransomware_trigger 2>/dev/null || true; }
    post_exploit_all() {
        exploit_lfi 2>/dev/null || true; exploit_ssrf 2>/dev/null || true
        exploit_xxe 2>/dev/null || true; exploit_idor 2>/dev/null || true
        exploit_pickle_deser 2>/dev/null || true; exploit_docker_escape 2>/dev/null || true
        exploit_persist_ssh 2>/dev/null || true; exploit_persist_cron 2>/dev/null || true
        exploit_cred_harvest 2>/dev/null || true; exploit_dns_exfil 2>/dev/null || true
    }

    # --- Part B: _build_menu() ---
    _build_menu() {
        local -a menu_args=()
        local status prefix
        local -a vectors=(
            "1|Reconnaissance (nmap scan)"
            "2|Brute Force (SSH/FTP/HTTP)"
            "3|SQL Injection (auth bypass)"
            "4|Command Injection (RCE)"
            "5|Webshell Deploy (upload)"
            "6|XSS PoC (reflected + stored)"
            "7|CVE-2021-41773 Apache Path Traversal"
            "8|CVE-2014-6271 Shellshock Bash CGI"
            "9|CVE-2019-15107 Webmin RCE"
            "10|CVE-2020-1938 Tomcat Ghostcat (AJP LFI)"
            "11|Log4Shell Pattern (JNDI Injection)"
            "12|Spring4Shell Pattern (Binding)"
            "13|Struts2 Pattern (Upload -> RCE)"
            "14|CVE-2021-4034 Polkit LPE (pkexec)"
            "15|Crawler -- Bait File Exfiltration"
            "16|Post-Exploitation (10 techniques)"
            "17|Malware / C2 Simulation"
        )

        local tag label mod
        for item in "${vectors[@]}"; do
            tag="${item%%|*}"; label="${item##*|}"
            case "$tag" in
                1) mod="recon" ;;  2) mod="bruteforce_ssh" ;;  3) mod="exploit_sqli" ;;
                4) mod="exploit_command_injection" ;;  5) mod="exploit_webshell_deploy" ;;  6) mod="exploit_xss_reflected" ;;
                7) mod="exploit_apache_41773" ;;  8) mod="exploit_shellshock_6271" ;;  9) mod="exploit_webmin_15107" ;;
                10) mod="exploit_ghostcat_1938" ;;  11) mod="exploit_log4shell_pattern" ;;  12) mod="exploit_spring4shell_pattern" ;;
                13) mod="exploit_struts_upload_pattern" ;;  14) mod="exploit_polkit_4034" ;;
                15) mod="crawler" ;;  16) mod="post_exploit" ;;  17) mod="malware_c2" ;;
                *) mod="" ;;
            esac
            status="$(results_status_for "$mod" 2>/dev/null || true)"
            case "$status" in
                VULNERABLE|SUCCESS) prefix="[+] " ;;
                FAILED) prefix="[-] " ;;
                *) prefix="[ ] " ;;
            esac
            menu_args+=("$tag" "${prefix}${label}")
        done

        menu_args+=("A" "   >>> RUN ALL SCENARIOS (Kill-Chain) <<<")
        menu_args+=("C" "   >>> RUN ALL CVEs <<<")
        menu_args+=("R" "   View Results Summary")
        menu_args+=("T" "   Change Target IP")
        menu_args+=("Q" "   Back to Main Menu")

        ui_menu "bait-n-break Attacker" "Target: ${TARGET_IP}:${TARGET_PORT:-8080}  |  TOTAL: $(results_stats 2>/dev/null || echo 'n/a')" "${menu_args[@]}"
    }

    # --- Part C: _do() helper ---
    _do() {
        local t="$1"; shift
        clear
        echo "=============================================="
        echo "  [bait-n-break]  ${t}  Target: ${TARGET_IP}"
        echo "=============================================="
        echo ""
        "$@" 2>&1
        echo ""
        echo "----------------------------------------------"
        read -r -p "Press Enter to return to menu..." _
    }

    # --- Part D: _all(), _cves(), _results() helpers ---
    _all() { _do "RUN ALL SCENARIOS (Kill-Chain)" _exec_all; }
    _cves() { _do "RUN ALL CVEs" _exec_cves; }
    _results() { clear; results_short_summary 2>/dev/null || true; echo ""; read -r -p "Press Enter to return to menu..." _; }

    # --- Part E: Main loop ---
    while true; do
        local choice
        choice="$(_build_menu)" || break

        case "$choice" in
            1)  _do "Reconnaissance (nmap scan)" recon_scan ;;
            2)  _do "Brute Force (SSH/FTP/HTTP)" bruteforce_all ;;
            3)  _do "SQL Injection (auth bypass)" exploit_sqli ;;
            4)  _do "Command Injection (RCE)" exploit_command_injection ;;
            5)  _do "Webshell Deploy (upload)" exploit_webshell_deploy ;;
            6)  _do "XSS PoC (reflected + stored)" exploit_xss_poc ;;
            7)  _do "CVE-2021-41773 Apache Path Traversal" exploit_apache_41773 ;;
            8)  _do "CVE-2014-6271 Shellshock Bash CGI" exploit_shellshock_6271 ;;
            9)  _do "CVE-2019-15107 Webmin RCE" exploit_webmin_15107 ;;
            10) _do "CVE-2020-1938 Tomcat Ghostcat (AJP LFI)" exploit_ghostcat_1938 ;;
            11) _do "Log4Shell Pattern (JNDI Injection)" exploit_log4shell_pattern ;;
            12) _do "Spring4Shell Pattern (Binding)" exploit_spring4shell_pattern ;;
            13) _do "Struts2 Pattern (Upload -> RCE)" exploit_struts_upload_pattern ;;
            14) _do "CVE-2021-4034 Polkit LPE (pkexec)" exploit_polkit_4034 ;;
            15) _do "Crawler -- Bait File Exfiltration" crawl_all ;;
            16) _do "Post-Exploitation (10 techniques)" post_exploit_all ;;
            17) _do "Malware / C2 Simulation" malware_c2_all ;;
            A|a) _all ;;
            C|c) _cves ;;
            R|r) _results ;;
            T|t)
                local ip
                read -r -p "New Target IP: " ip
                if target_is_valid_ip "$ip"; then
                    TARGET_IP="$ip"
                    state_set_target "$TARGET_IP" "${TARGET_PORT:-8080}"
                    results_init
                else
                    ui_error "Invalid Target" "\"$ip\" is not a valid IPv4 address."
                fi
                ;;
            Q|q|"") break ;;
        esac
    done
}

# --- Part F: Execution dispatchers ---

_exec_all() {
    local phase_fn_count=0 phase_fn_ok=0 phase_fn_fail=0 phase_name=""
    local total_ok=0 total_fail=0

    _run_all_phase() {
        local phase="$1" tactic="$2"; shift 2
        printf '\n'
        phase_banner "$phase" "$tactic"
        local fn i=0 total=$#
        phase_fn_count=$total phase_fn_ok=0 phase_fn_fail=0 phase_name="$phase"
        for fn in "$@"; do
            i=$((i+1))
            printf '\033[1;33m[%d/%d]\033[0m \033[1m%s\033[0m\n' "$i" "$total" "$fn"
            ( "$fn" 2>&1 ) & local _pid=$!
            ( sleep 30; kill "$_pid" 2>/dev/null ) & local _killer=$!
            wait "$_pid" 2>/dev/null; local _rc=$?
            kill "$_killer" 2>/dev/null; wait "$_killer" 2>/dev/null
            if [ "$_rc" -eq 0 ]; then
                printf '  \033[1;32m[OK]\033[0m\n\n'
                phase_fn_ok=$((phase_fn_ok+1)); total_ok=$((total_ok+1))
            else
                printf '  \033[1;31m[FAIL]\033[0m\n\n'
                phase_fn_fail=$((phase_fn_fail+1)); total_fail=$((total_fail+1))
            fi
        done
        printf '  \033[1;37mPhase: %s  |  %d/%d OK  |  %d failed\033[0m\n\n' \
            "$phase_name" "$phase_fn_ok" "$phase_fn_count" "$phase_fn_fail"
    }

    _run_all_phase "RECONNAISSANCE" "TA0043" recon_scan
    _run_all_phase "INITIAL ACCESS" "TA0001" exploit_sqli exploit_command_injection exploit_webshell_deploy exploit_xss_poc exploit_apache_41773 exploit_shellshock_6271 exploit_webmin_15107 exploit_ghostcat_1938 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern
    _run_all_phase "CREDENTIAL ACCESS" "TA0006" bruteforce_ssh bruteforce_ftp bruteforce_http
    _run_all_phase "PRIVILEGE ESCALATION" "TA0004" exploit_polkit_4034
    _run_all_phase "COLLECTION" "TA0009" crawl_all
    _run_all_phase "LATERAL MOVEMENT + PERSISTENCE" "TA0008/TA0003" post_exploit_all
    _run_all_phase "IMPACT" "TA0040" malware_c2_all

    printf '\n\033[1;37;42m  KILL-CHAIN COMPLETE  \033[0m\n'
    printf '  %d OK / %d FAIL / %d total functions executed\n\n' "$total_ok" "$total_fail" $((total_ok + total_fail))
    results_short_summary 2>/dev/null || true
    echo ""
}

_exec_cves() {
    local -a cve_fns=(exploit_ghostcat_1938 exploit_shellshock_6271 exploit_apache_41773 exploit_webmin_15107 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern exploit_polkit_4034)
    local i=1 fn ok=0 fail=0
    for fn in "${cve_fns[@]}"; do
        printf '\n\033[1;33m[CVE %d/8]\033[0m \033[1m%s\033[0m\n' "$i" "$fn"
        ( "$fn" 2>&1 ) & local _pid=$!
        ( sleep 30; kill "$_pid" 2>/dev/null ) & local _killer=$!
        wait "$_pid" 2>/dev/null; local _rc=$?
        kill "$_killer" 2>/dev/null; wait "$_killer" 2>/dev/null
        if [ "$_rc" -eq 0 ]; then
            printf '  \033[1;32m[OK]\033[0m\n'
            ok=$((ok+1))
        else
            printf '  \033[1;31m[FAIL]\033[0m\n'
            fail=$((fail+1))
        fi
        i=$((i+1))
    done
    printf '\n  %d OK / %d FAIL / 8 total\n\n' "$ok" "$fail"
    echo "[DONE] All 8 CVEs complete"
}
