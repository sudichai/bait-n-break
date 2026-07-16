#!/usr/bin/env bash
# Attacker (Kali) role console: target configuration, per-scenario attack
# execution, Run All Scenarios, results summary.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

_attacker_console_fallback() {
    source "${BNB_ROOT}/bait_n_break/attacker/lib_results.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_target.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_recon.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_bruteforce.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_web_exploit.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_crawler.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_malware_c2.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_post_exploit.sh"

    results_init

    while true; do
        local choice
        choice="$(ui_menu "Attacker Console" "Select an action:" \
            "1" "Set/Change Target" \
            "2" "Recon" \
            "3" "Brute-force (SSH/FTP/HTTP/MySQL)" \
            "4" "Web Exploitation (SQLi/CMDi/XSS/Webshell)" \
            "5" "Advanced Web (LFI/SSRF/XXE/IDOR/Pickle)" \
            "6" "Privilege Escalation & Persistence" \
            "7" "Credential Harvesting" \
            "8" "Crawler (bait exfiltration)" \
            "9" "Malware/C2" \
            "10" "Impact (Deface/Wipe/Clear)" \
            "11" "Run All Scenarios" \
            "12" "Chain A: SQLi->Docker Escape" \
            "13" "Chain B: CMDi->Impact" \
            "14" "Chain C: SSRF->Exfil" \
            "15" "Results Summary" \
            "16" "Back")" || break

        case "$choice" in
            1) target_prompt ;;
            2) attacker_run_and_pause recon_scan ;;
            3) attacker_run_and_pause attacker_bruteforce_menu ;;
            4) attacker_run_and_pause attacker_web_exploit_menu ;;
            5) attacker_run_and_pause attacker_advanced_web_menu ;;
            6) attacker_run_and_pause attacker_priv_esc_menu ;;
            7) attacker_run_and_pause exploit_cred_harvest ;;
            8) attacker_run_and_pause crawl_leaked_files ;;
            9) attacker_run_and_pause attacker_malware_c2_menu ;;
            10) attacker_run_and_pause attacker_impact_menu ;;
            11) attacker_run_and_pause attacker_run_all ;;
            12) attacker_run_and_pause chain_a_sqli_to_docker ;;
            13) attacker_run_and_pause chain_b_cmdi_to_impact ;;
            14) attacker_run_and_pause chain_c_ssrf_to_exfil ;;
            15) ui_msgbox "Results Summary" "$(results_summary)" ;;
            16|"") break ;;
        esac
    done
}

attacker_run_and_pause() {
    clear
    "$@"
    echo ""
    read -r -p "Press Enter to continue..." _
}

attacker_bruteforce_menu() {
    bruteforce_ssh
    bruteforce_ftp
    bruteforce_http
    exploit_mysql
}

attacker_web_exploit_menu() {
    exploit_sqli
    exploit_command_injection
    exploit_webshell_deploy
    exploit_xss_poc
}

attacker_advanced_web_menu() {
    exploit_lfi
    exploit_ssrf
    exploit_xxe
    exploit_idor
    exploit_pickle_deser
}

attacker_priv_esc_menu() {
    exploit_docker_escape
    exploit_persist_ssh
    exploit_persist_cron
}

attacker_impact_menu() {
    exploit_dns_exfil
    exploit_impact_deface
    exploit_impact_wipe_db
    exploit_impact_clear_logs
}

attacker_malware_c2_menu() {
    c2_beacon_check
    ransomware_trigger
}

attacker_run_all() {
    echo ""
    echo "=============================================="
    echo "  FULL KILL-CHAIN ATTACK"
    echo "  Target: ${TARGET_IP:-<not set>}"
    echo "  Phases: 1-Recon 2-CredAccess 3-Execution"
    echo "          4-AdvWeb 5-PrivEsc 6-CredHarvest"
    echo "          7-Crawler 8-Malware 9-Impact"
    echo "=============================================="
    echo ""
    target_ensure_set || { echo "No target set - aborting Run All Scenarios."; return 1; }
    results_clear
    sleep 1

    echo ""
    echo ">>> PHASE 1/9: RECONNAISSANCE <<<"
    recon_scan
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 2/9: CREDENTIAL ACCESS (BRUTE FORCE) <<<"
    attacker_bruteforce_menu
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 3/9: EXECUTION (WEB EXPLOITATION) <<<"
    attacker_web_exploit_menu
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 4/9: EXECUTION (ADVANCED WEB) <<<"
    attacker_advanced_web_menu
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 5/9: PRIVILEGE ESCALATION & PERSISTENCE <<<"
    attacker_priv_esc_menu
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 6/9: CREDENTIAL HARVESTING <<<"
    exploit_cred_harvest
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 7/9: COLLECTION (BAIT EXFILTRATION) <<<"
    crawl_leaked_files
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 8/9: MALWARE / C2 <<<"
    attacker_malware_c2_menu
    echo "    [*] phase complete, pausing 2s..."
    sleep 2

    echo ""
    echo ">>> PHASE 9/9: IMPACT <<<"
    attacker_impact_menu

    echo ""
    echo "=============================================="
    echo "  FULL KILL-CHAIN COMPLETE"
    echo "=============================================="
    echo ""
    results_summary
}
