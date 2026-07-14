#!/usr/bin/env bash
# Victim (Target) role dashboard: deploy, status, bait inventory, monitor,
# malware simulation, teardown.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

victim_dashboard() {
    # shellcheck source=bait_n_break/victim/lib_bait.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_bait.sh"
    # shellcheck source=bait_n_break/victim/lib_webapp.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_webapp.sh"
    # shellcheck source=bait_n_break/victim/lib_monitor.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_monitor.sh"
    # shellcheck source=bait_n_break/victim/lib_malware_sim.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_malware_sim.sh"

    # Background log-tailing jobs started by monitor_start() must not outlive
    # the TUI process if the user exits without going through Teardown first.
    trap 'monitor_stop 2>/dev/null' EXIT

    while true; do
        local choice
        choice="$(ui_menu "Victim Dashboard" "Select an action:" \
            "1" "Deploy / Start victim services" \
            "2" "Service Status Panel" \
            "3" "Honey-Asset Inventory" \
            "4" "Access & Incident Monitor" \
            "5" "Malware/Ransomware Simulation" \
            "6" "Stop / Teardown" \
            "7" "Back")" || break

        case "$choice" in
            1) victim_deploy ;;
            2) victim_status ;;
            3) victim_inventory ;;
            4) victim_monitor_view ;;
            5) victim_malware_menu ;;
            6) victim_teardown ;;
            7|"") break ;;
        esac
    done
}

victim_deploy() {
    local bait_warning=""
    bait_generate_all || bait_warning="Warning: one or more bait files failed to generate (see incident/log output for details).

"
    if webapp_up; then
        state_set_status "deployed"
        monitor_start
        ui_msgbox "Deploy" "${bait_warning}Victim services deployed. Bait files generated and web app started."
    else
        ui_error "Deploy" "${bait_warning}Failed to start web app. Is Docker installed and running?"
    fi
}

victim_status() {
    local status ports compose_ps
    status="$(state_get_status)"
    ports="$(webapp_ports)"
    compose_ps="$(webapp_status 2>&1)"
    ui_msgbox "Service Status" "Status: ${status}

Open ports:
${ports}

Containers:
${compose_ps}"
}

victim_inventory() {
    local list
    list="$(state_manifest_list)"
    ui_msgbox "Honey-Asset Inventory" "${list:-No bait files generated yet.}"
}

victim_monitor_view() {
    ui_msgbox "Access & Incident Monitor" "$(state_incident_tail 30)"
}

victim_malware_menu() {
    local choice
    choice="$(ui_menu "Malware Simulation" "Select a demo:" \
        "1" "Drop EICAR test file" \
        "2" "Run ransomware demo" \
        "3" "Restore ransomware demo" \
        "4" "Check C2 beacon" \
        "5" "Back")" || return
    case "$choice" in
        1) malware_drop_eicar; ui_msgbox "EICAR" "EICAR test file dropped." ;;
        2) malware_ransomware_demo_run; ui_msgbox "Ransomware Demo" "Demo run complete. Files under ransomware_target/ are now *.locked." ;;
        3) malware_ransomware_demo_restore; ui_msgbox "Ransomware Demo" "Files restored." ;;
        4)
            if malware_c2_beacon_check; then
                ui_msgbox "C2 Beacon" "Beacon check succeeded."
            else
                ui_msgbox "C2 Beacon" "Beacon check failed (is the web app running?)."
            fi
            ;;
    esac
}

victim_teardown() {
    monitor_stop
    if webapp_down; then
        state_reset
        ui_msgbox "Teardown" "Victim services stopped and state reset."
    else
        state_reset
        ui_error "Teardown" "docker compose down reported an error, but state was reset anyway. Check Docker manually if containers may still be running."
    fi
}
