#!/usr/bin/env bash
# Attacker (Kali) role console: target configuration, per-scenario attack
# execution, Run All Scenarios, results summary.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

attacker_console() {
    # shellcheck source=bait_n_break/attacker/lib_results.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_results.sh"
    # shellcheck source=bait_n_break/attacker/lib_target.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_target.sh"
    # shellcheck source=bait_n_break/attacker/lib_recon.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_recon.sh"
    # shellcheck source=bait_n_break/attacker/lib_bruteforce.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_bruteforce.sh"
    # shellcheck source=bait_n_break/attacker/lib_web_exploit.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_web_exploit.sh"
    # shellcheck source=bait_n_break/attacker/lib_crawler.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_crawler.sh"
    # shellcheck source=bait_n_break/attacker/lib_malware_c2.sh
    source "${BNB_ROOT}/bait_n_break/attacker/lib_malware_c2.sh"

    results_init

    while true; do
        local choice
        choice="$(ui_menu "Attacker Console" "Select an action:" \
            "1" "Set/Change Target" \
            "2" "Recon" \
            "3" "Brute-force" \
            "4" "Web Exploitation" \
            "5" "Crawler (bait exfiltration)" \
            "6" "Malware/C2" \
            "7" "Run All Scenarios" \
            "8" "Results Summary" \
            "9" "Back")" || break

        case "$choice" in
            1) target_prompt ;;
            2) attacker_run_and_pause recon_scan ;;
            3) attacker_run_and_pause attacker_bruteforce_menu ;;
            4) attacker_run_and_pause attacker_web_exploit_menu ;;
            5) attacker_run_and_pause crawl_leaked_files ;;
            6) attacker_run_and_pause attacker_malware_c2_menu ;;
            7) attacker_run_and_pause attacker_run_all ;;
            8) ui_msgbox "Results Summary" "$(results_summary)" ;;
            9|"") break ;;
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
}

attacker_web_exploit_menu() {
    exploit_sqli
    exploit_command_injection
    exploit_webshell_deploy
    exploit_xss_poc
}

attacker_malware_c2_menu() {
    c2_beacon_check
    ransomware_trigger
}

attacker_run_all() {
    echo "=== Run All Scenarios: full kill-chain against ${TARGET_IP:-<not set>} ==="
    target_ensure_set || { echo "No target set - aborting Run All Scenarios."; return 1; }
    results_clear
    recon_scan
    attacker_bruteforce_menu
    attacker_web_exploit_menu
    crawl_leaked_files
    attacker_malware_c2_menu
    echo ""
    echo "=== Run All Scenarios complete ==="
    results_summary
}
