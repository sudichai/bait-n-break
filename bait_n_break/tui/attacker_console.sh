#!/usr/bin/env bash
# Attacker console — whiptail menu with live terminal execution, status icons,
# WAF stats, and results summary. Sourced, not executed.

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

    crawl_all() {
        crawl_leaked_files 2>/dev/null || true
    }

    malware_c2_all() {
        c2_beacon_check 2>/dev/null || true
        ransomware_trigger 2>/dev/null || true
    }

    post_exploit_all() {
        exploit_lfi 2>/dev/null || true
        exploit_ssrf 2>/dev/null || true
        exploit_xxe 2>/dev/null || true
        exploit_idor 2>/dev/null || true
        exploit_pickle_deser 2>/dev/null || true
        exploit_docker_escape 2>/dev/null || true
        exploit_persist_ssh 2>/dev/null || true
        exploit_persist_cron 2>/dev/null || true
        exploit_cred_harvest 2>/dev/null || true
        exploit_dns_exfil 2>/dev/null || true
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
            "15|Crawler — Bait File Exfiltration"
            "16|Post-Exploitation (10 techniques)"
            "17|Malware / C2 Simulation"
        )

        local tag label
        for item in "${vectors[@]}"; do
            tag="${item%%|*}"
            label="${item##*|}"
            status="$(results_status_for "$tag" 2>/dev/null || true)"
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

        ui_menu "bait-n-break Attacker" "Target: ${TARGET_IP}:${TARGET_PORT:-8080}  |  WAF: $(results_waf_stats 2>/dev/null || echo 'n/a')" "${menu_args[@]}"
    }

    # --- Part C: _do() helper ---
    _do() {
        local t="$1"
        shift
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
    _all() {
        _do "Run All Scenarios (Kill-Chain)" _exec_all
    }

    _cves() {
        _do "Run All CVEs" _exec_cves
    }

    _results() {
        clear
        results_short_summary 2>/dev/null || true
        echo ""
        read -r -p "Press Enter to return to menu..." _
    }

    # --- Part E: Main loop ---
    while true; do
        local choice
        choice="$(_build_menu)" || break

        case "$choice" in
            1)  _do "Reconnaissance (nmap scan)" recon_scan ;;
            2)  _do "Brute Force (SSH/FTP/HTTP)" bash -c "bruteforce_ssh 2>/dev/null || true; bruteforce_ftp 2>/dev/null || true; bruteforce_http 2>/dev/null || true" ;;
            3)  _do "SQL Injection (auth bypass)" exploit_sqli ;;
            4)  _do "Command Injection (RCE)" exploit_command_injection ;;
            5)  _do "Webshell Deploy (upload)" exploit_webshell_deploy ;;
            6)  _do "XSS PoC (reflected + stored)" exploit_xss_poc ;;
            7)  _do "CVE-2021-41773 Apache Path Traversal" bash -c "exploit_apache_41773 2>/dev/null || true" ;;
            8)  _do "CVE-2014-6271 Shellshock Bash CGI" bash -c "exploit_shellshock_6271 2>/dev/null || true" ;;
            9)  _do "CVE-2019-15107 Webmin RCE" bash -c "exploit_webmin_15107 2>/dev/null || true" ;;
            10) _do "CVE-2020-1938 Tomcat Ghostcat (AJP LFI)" bash -c "exploit_ghostcat_1938 2>/dev/null || true" ;;
            11) _do "Log4Shell Pattern (JNDI Injection)" bash -c "exploit_log4shell_pattern 2>/dev/null || true" ;;
            12) _do "Spring4Shell Pattern (Binding)" bash -c "exploit_spring4shell_pattern 2>/dev/null || true" ;;
            13) _do "Struts2 Pattern (Upload -> RCE)" bash -c "exploit_struts_upload_pattern 2>/dev/null || true" ;;
            14) _do "CVE-2021-4034 Polkit LPE (pkexec)" bash -c "exploit_polkit_4034 2>/dev/null || true" ;;
            15) _do "Crawler — Bait File Exfiltration" crawl_all ;;
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

_exec_one() {
    case "$1" in
        1)  recon_scan ;;
        2)  bruteforce_ssh 2>/dev/null || true; bruteforce_ftp 2>/dev/null || true; bruteforce_http 2>/dev/null || true ;;
        3)  exploit_sqli ;;
        4)  exploit_command_injection ;;
        5)  exploit_webshell_deploy ;;
        6)  exploit_xss_poc ;;
        7)  exploit_apache_41773 2>/dev/null || true ;;
        8)  exploit_shellshock_6271 2>/dev/null || true ;;
        9)  exploit_webmin_15107 2>/dev/null || true ;;
        10) exploit_ghostcat_1938 2>/dev/null || true ;;
        11) exploit_log4shell_pattern 2>/dev/null || true ;;
        12) exploit_spring4shell_pattern 2>/dev/null || true ;;
        13) exploit_struts_upload_pattern 2>/dev/null || true ;;
        14) exploit_polkit_4034 2>/dev/null || true ;;
        15) crawl_all 2>/dev/null || true ;;
        16) post_exploit_all 2>/dev/null || true ;;
        17) malware_c2_all 2>/dev/null || true ;;
    esac
}

_exec_all() {
    local fn

    phase_banner "RECONNAISSANCE" "TA0043"
    recon_scan

    phase_banner "INITIAL ACCESS" "TA0001"
    for fn in exploit_sqli exploit_command_injection exploit_webshell_deploy exploit_xss_poc exploit_apache_41773 exploit_shellshock_6271 exploit_webmin_15107 exploit_ghostcat_1938 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern; do
        timeout 15 "$fn" >/dev/null 2>&1 || true
    done

    phase_banner "EXECUTION" "TA0002"
    exploit_webshell_deploy >/dev/null 2>&1 || true

    phase_banner "CREDENTIAL ACCESS" "TA0006"
    for fn in bruteforce_ssh bruteforce_ftp bruteforce_http; do
        timeout 15 "$fn" >/dev/null 2>&1 || true
    done

    phase_banner "PRIVILEGE ESCALATION" "TA0004"
    timeout 15 exploit_polkit_4034 >/dev/null 2>&1 || true

    phase_banner "COLLECTION" "TA0009"
    timeout 15 crawl_all >/dev/null 2>&1 || true

    phase_banner "LATERAL MOVEMENT + PERSISTENCE" "TA0008/TA0003"
    timeout 15 post_exploit_all >/dev/null 2>&1 || true

    phase_banner "IMPACT" "TA0040"
    timeout 15 malware_c2_all >/dev/null 2>&1 || true

    echo "[DONE] All kill-chain phases complete"
}

_exec_cves() {
    local -a cve_fns=(exploit_ghostcat_1938 exploit_shellshock_6271 exploit_apache_41773 exploit_webmin_15107 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern exploit_polkit_4034)
    local i=1
    for fn in "${cve_fns[@]}"; do
        echo "[CVE ${i}/8]"
        timeout 15 "$fn" >/dev/null 2>&1 || true
        i=$((i + 1))
    done
    echo "[DONE] All CVEs complete"
}
