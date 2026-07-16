#!/usr/bin/env bash
# Attacker console — whiptail menu for vector selection, full-screen during attacks.
# Sourced, not executed.

attacker_console() {
    source "${BNB_ROOT}/bait_n_break/attacker/lib_target.sh"

    # --- IP Target Input ---
    if [ -z "${TARGET_IP:-}" ]; then
        local saved; saved="$(state_get_target 2>/dev/null)"
        [ -n "$saved" ] && { TARGET_IP="$(echo "$saved" | cut -d' ' -f1)"; TARGET_PORT="$(echo "$saved" | cut -d' ' -f2)"; }
    fi
    if [ -z "${TARGET_IP:-}" ]; then
        clear; echo ""; echo "  +-------------------------------------------+"
        echo "  |         bait-n-break Attacker Console      |"
        echo "  +-------------------------------------------+"; echo ""
        while true; do
            printf "  Enter Target IP: "; read -r target_ip
            if target_is_valid_ip "$target_ip"; then
                TARGET_IP="$target_ip"; TARGET_PORT="${TARGET_PORT:-8080}"
                state_set_target "$TARGET_IP" "${TARGET_PORT:-8080}"; break
            fi
            echo "  Invalid IPv4 address."; echo ""
        done; echo ""; echo "  Target: ${TARGET_IP}:${TARGET_PORT:-8080}"; sleep 1
    fi

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
    post_exploit_all() { exploit_lfi 2>/dev/null; exploit_ssrf 2>/dev/null; exploit_xxe 2>/dev/null; exploit_idor 2>/dev/null; exploit_pickle_deser 2>/dev/null; exploit_docker_escape 2>/dev/null; exploit_persist_ssh 2>/dev/null; exploit_persist_cron 2>/dev/null; exploit_cred_harvest 2>/dev/null; exploit_dns_exfil 2>/dev/null; }

    _do() { local t="$1"; shift; clear
        echo "=============================================="
        echo "  [bait-n-break]  ${t}  Target: ${TARGET_IP}"
        echo "=============================================="; echo ""
        "$@" 2>&1
        echo ""; echo "----------------------------------------------"
        if [ -f "${BNB_ATTACK_RESULTS}" ]; then
            echo "Latest results:"; grep -E "SUCCESS|VULNERABLE|FAILED" "${BNB_ATTACK_RESULTS}" | tail -5
        fi
        read -r -p "Press Enter to continue..." _
    }

    _all() { _do "Run All Scenarios" _exec_all; }
    _cves() { _do "Run All CVEs" _exec_cves; }

    while true; do
        local choice
        choice="$(ui_menu "bait-n-break Attacker" "Target: ${TARGET_IP}:${TARGET_PORT:-8080}" \
            "1"  "Reconnaissance (nmap scan)" \
            "2"  "Brute Force (SSH/FTP/HTTP)" \
            "3"  "SQL Injection" \
            "4"  "Command Injection" \
            "5"  "Webshell Deploy" \
            "6"  "XSS PoC" \
            "7"  "CVE-2021-41773 Apache Path Traversal" \
            "8"  "CVE-2014-6271 Shellshock" \
            "9"  "CVE-2019-15107 Webmin RCE" \
            "10" "CVE-2020-1938 Tomcat Ghostcat" \
            "11" "Log4Shell Pattern (JNDI)" \
            "12" "Spring4Shell Pattern (Binding)" \
            "13" "Struts2 Pattern (Upload)" \
            "14" "CVE-2021-4034 Polkit LPE" \
            "15" "Crawler / Bait Exfiltration" \
            "16" "Post-Exploitation" \
            "17" "Malware / C2 Simulation" \
            "A"  ">>> RUN ALL SCENARIOS (kill-chain) <<<" \
            "C"  ">>> RUN ALL CVEs <<<" \
            "T"  "Change Target IP" \
            "Q"  "Back to Main Menu")" || break

        case "$choice" in
            1)  _do "Reconnaissance" recon_scan ;;
            2)  _do "Brute Force" bash -c "bruteforce_ssh 2>/dev/null; bruteforce_ftp 2>/dev/null; bruteforce_http 2>/dev/null" ;;
            3)  _do "SQL Injection" exploit_sqli ;;
            4)  _do "Command Injection" exploit_command_injection ;;
            5)  _do "Webshell Deploy" exploit_webshell_deploy ;;
            6)  _do "XSS PoC" exploit_xss_poc ;;
            7)  _do "CVE-2021-41773" bash -c "exploit_apache_41773 2>/dev/null || true" ;;
            8)  _do "CVE-2014-6271 Shellshock" bash -c "exploit_shellshock_6271 2>/dev/null || true" ;;
            9)  _do "CVE-2019-15107 Webmin" bash -c "exploit_webmin_15107 2>/dev/null || true" ;;
            10) _do "CVE-2020-1938 Ghostcat" bash -c "exploit_ghostcat_1938 2>/dev/null || true" ;;
            11) _do "Log4Shell Pattern" bash -c "exploit_log4shell_pattern 2>/dev/null || true" ;;
            12) _do "Spring4Shell Pattern" bash -c "exploit_spring4shell_pattern 2>/dev/null || true" ;;
            13) _do "Struts2 Pattern" bash -c "exploit_struts_upload_pattern 2>/dev/null || true" ;;
            14) _do "Polkit LPE" bash -c "exploit_polkit_4034 2>/dev/null || true" ;;
            15) _do "Crawler" crawl_all ;;
            16) _do "Post-Exploit" post_exploit_all ;;
            17) _do "Malware/C2" malware_c2_all ;;
            A|a) _all ;;
            C|c) _cves ;;
            T|t) read -r -p "New Target IP: " ip; target_is_valid_ip "$ip" && { TARGET_IP="$ip"; state_set_target "$TARGET_IP" "${TARGET_PORT:-8080}"; } || ui_error "Invalid" "Not a valid IPv4 address." ;;
            Q|q|"") break ;;
        esac
    done
}

_exec_one() { case "$1" in
    1) recon_scan ;;  2) bruteforce_ssh 2>/dev/null; bruteforce_ftp 2>/dev/null; bruteforce_http 2>/dev/null ;;
    3) exploit_sqli ;;  4) exploit_command_injection ;;  5) exploit_webshell_deploy ;;  6) exploit_xss_poc ;;
    7) exploit_apache_41773 2>/dev/null || true ;;  8) exploit_shellshock_6271 2>/dev/null || true ;;
    9) exploit_webmin_15107 2>/dev/null || true ;;  10) exploit_ghostcat_1938 2>/dev/null || true ;;
    11) exploit_log4shell_pattern 2>/dev/null || true ;;  12) exploit_spring4shell_pattern 2>/dev/null || true ;;
    13) exploit_struts_upload_pattern 2>/dev/null || true ;;  14) exploit_polkit_4034 2>/dev/null || true ;;
    15) crawl_all 2>/dev/null || true ;;  16) post_exploit_all 2>/dev/null || true ;;  17) malware_c2_all 2>/dev/null || true ;;
esac; }

_exec_all() {
    echo "[Phase 1/5] Reconnaissance"; recon_scan
    echo; echo "[Phase 2/5] CVE Initial Access"
    for fn in exploit_ghostcat_1938 exploit_shellshock_6271 exploit_apache_41773 exploit_webmin_15107 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern; do timeout 15 $fn >/dev/null 2>&1 || true; done
    echo; echo "[Phase 3/5] Web Exploitation"
    for fn in exploit_sqli exploit_command_injection exploit_webshell_deploy exploit_xss_poc; do timeout 15 $fn >/dev/null 2>&1 || true; done
    echo; echo "[Phase 4/5] Brute Force"
    for fn in bruteforce_ssh bruteforce_ftp bruteforce_http; do timeout 15 $fn >/dev/null 2>&1 || true; done
    echo; echo "[Phase 5/5] PrivEsc + Post-Exploit"
    for fn in exploit_polkit_4034 crawl_all post_exploit_all malware_c2_all; do timeout 15 $fn >/dev/null 2>&1 || true; done
    echo; echo "[DONE] All scenarios complete"
}

_exec_cves() {
    local i=1; for fn in exploit_ghostcat_1938 exploit_shellshock_6271 exploit_apache_41773 exploit_webmin_15107 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern exploit_polkit_4034; do echo "[CVE ${i}/8]"; timeout 15 $fn >/dev/null 2>&1 || true; i=$((i+1)); done
    echo "[DONE] All CVEs complete"
}
