#!/usr/bin/env bash
# Top-level role menu: Victim / Attacker / Exit.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

main_menu() {
    while true; do
        local choice
        choice="$(ui_menu "bait-n-break" "Select a role:" \
            "1" "Victim (Target Machine)" \
            "2" "Attacker (Kali Machine)" \
            "3" "Exit")" || break

        case "$choice" in
            1)
                # shellcheck source=bait_n_break/tui/victim_dashboard.sh
                source "${BNB_ROOT}/bait_n_break/tui/victim_dashboard.sh"
                victim_dashboard
                ;;
            2)
                # shellcheck source=bait_n_break/tui/attacker_console.sh
                source "${BNB_ROOT}/bait_n_break/tui/attacker_console.sh"
                attacker_console
                ;;
            3|"")
                break
                ;;
        esac
    done
}
