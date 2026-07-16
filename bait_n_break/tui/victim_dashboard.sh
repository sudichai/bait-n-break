#!/usr/bin/env bash
# Victim (Target) role dashboard — persistent ANSI TUI with live-updating
# service status, vulnerability counts, and incident log.
# Auto-deploys on entry; falls back to whiptail if terminal is too small.
# Sourced, not executed.

victim_dashboard() {
    # Source libs needed for deploy before TUI init
    # shellcheck source=bait_n_break/victim/lib_bait.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_bait.sh"
    # shellcheck source=bait_n_break/victim/lib_webapp.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_webapp.sh"
    # shellcheck source=bait_n_break/victim/lib_monitor.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_monitor.sh"
    # shellcheck source=bait_n_break/victim/lib_malware_sim.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_malware_sim.sh"
    # shellcheck source=bait_n_break/victim/lib_live_dashboard.sh
    source "${BNB_ROOT}/bait_n_break/victim/lib_live_dashboard.sh"

    # --- Auto-Deploy Loading Screen ---
    clear
    echo ""
    echo "=============================================="
    echo "  bait-n-break Victim Node — Auto-Deploy"
    echo "=============================================="
    echo ""

    local deploy_failed=""
    local cve_dir="${BNB_WEBAPP_DIR}/cve-services"

    # Auto-download CVE dependencies if missing
    local need_dl=""
    for f in \
        "${cve_dir}/proftpd-1.3.5/proftpd-1.3.5.tar.gz" \
        "${cve_dir}/webmin-1.890/webmin_1.890_all.deb" \
        "${cve_dir}/tomcat-ghostcat/apache-tomcat-9.0.30.tar.gz"; do
        [ -f "$f" ] || need_dl=1
    done
    if [ -n "$need_dl" ]; then
        echo "  [..] Downloading CVE dependencies (first run)..."
        bash "${cve_dir}/download.sh"
        # Re-check after download
        need_dl=""
        for f in \
            "${cve_dir}/proftpd-1.3.5/proftpd-1.3.5.tar.gz" \
            "${cve_dir}/webmin-1.890/webmin_1.890_all.deb" \
            "${cve_dir}/tomcat-ghostcat/apache-tomcat-9.0.30.tar.gz"; do
            [ -f "$f" ] || need_dl=1
        done
        if [ -n "$need_dl" ]; then
            echo "  [FAIL] Could not download all dependencies"
            read -r -p "  Press Enter to return to menu..." _
            return
        fi
        echo "  [OK] CVE dependencies downloaded"
        echo ""
    fi

    echo -n "  [..] Stopping any existing containers... "
    webapp_down >/dev/null 2>&1
    echo -e "\r  [OK] Stopping any existing containers... "

    echo -n "  [..] Generating bait files...          "
    if bait_generate_all >/dev/null 2>&1; then
        echo -e "\r  [OK] Generating bait files...          "
    else
        echo -e "\r  [WARN] Bait generation had errors      "
    fi

    echo "  [..] Starting Docker containers..."
    if webapp_up 2>&1; then
        echo ""
        echo "  [OK] Docker containers started"
    else
        echo ""
        echo "  [FAIL] Docker containers failed to start"
        deploy_failed=1
    fi

    if [ -z "$deploy_failed" ]; then
        state_set_status "deployed"
        echo -n "  [..] Activating monitor...              "
        monitor_start 2>/dev/null
        echo -e "\r  [OK] Activating monitor...              "
    fi

    echo ""
    if [ -n "$deploy_failed" ]; then
        while true; do
            echo ""
            echo "  Docker daemon is not running. Start Docker and retry."
            echo ""
            printf "  [R] Retry  [B] Back to menu: "
            read -r choice
            case "$choice" in
                R|r)
                    echo ""
                    echo -n "  [..] Stopping existing containers...    "
                    webapp_down >/dev/null 2>&1
                    echo -e "\r  [OK] Stopping existing containers...    "
                    echo "  [..] Starting containers..."
                    if webapp_up 2>&1; then
                        echo ""
                        echo "  [OK] Docker containers started"
                        state_set_status "deployed"
                        echo -n "  [..] Activating monitor...              "
                        monitor_start 2>/dev/null
                        echo -e "\r  [OK] Activating monitor...              "
                        break
                    else
                        echo ""
                        echo "  [FAIL] Docker containers failed to start"
                    fi
                    ;;
                *) return ;;
            esac
        done
    fi

    echo "  All services ready. Starting dashboard..."
    sleep 2

    # --- TUI Init ---
    # shellcheck source=bait_n_break/tui/ansi_tui.sh
    source "${BNB_ROOT}/bait_n_break/tui/ansi_tui.sh"

    if ! tui_init; then
        source "${BNB_ROOT}/bait_n_break/tui/victim_dashboard_fallback.sh"
        _victim_dashboard_fallback
        return
    fi
    trap 'tui_cleanup; monitor_stop 2>/dev/null' EXIT INT

    TUI_LEFT_TITLE="SERVICES & CONNS"
    TUI_MID_TITLE="VULNERABILITIES"
    TUI_RIGHT_TITLE="INCIDENTS"
    TUI_HEADER_TITLE="bait-n-break"
    TUI_HEADER_STATUS="Idle"
    TUI_TARGET_TYPE="victim-lab"
    TUI_FOOTER_TEXT="  <D> DEPLOY | <T> TEARDOWN | <M> MALWARE | <B> BAIT | <Q> BACK"

    _build_services_panel() {
        TUI_PANEL_LEFT=()
        local -a svc_data
        live_probe_services svc_data

        local up_count=0
        for entry in "${svc_data[@]}"; do
            local name="${entry%%|*}"; local rest="${entry#*|}"
            local port="${rest%%|*}"; rest="${rest#*|}"
            local status="${rest%%|*}"; local conns="${rest##*|}"

            if [ "$status" = "UP" ]; then
                up_count=$((up_count + 1))
                printf -v line '  [UP] %-14s :%s' "$name" "$port"
                TUI_PANEL_LEFT+=("$line")
                local conn_line="       ${conns} connection"
                [ "$conns" != "1" ] && conn_line="${conn_line}s"
                TUI_PANEL_LEFT+=("$conn_line")
            else
                printf -v line '  [DN] %-14s :%s' "$name" "$port"
                TUI_PANEL_LEFT+=("$line")
            fi
        done

        TUI_HEADER_STATUS="${up_count} svcs running"
        TUI_TARGET_IP="$(live_get_hostname)"
        TUI_TARGET_NAT="Bait: $(live_get_bait_count) files"
    }

    _build_vulns_panel() {
        TUI_PANEL_MID=()
        local total=0
        local total_active=0

        while IFS='|' read -r phase count active; do
            total=$((total + count))
            local label="ACTIVE"
            if [ "$active" = "0" ]; then
                label="INACTIVE"
            else
                total_active=$((total_active + count))
            fi
            printf -v line '  %-12s %2d  [%s]' "$phase" "$count" "$label"
            TUI_PANEL_MID+=("$line")
        done < <(live_count_vulns)

        TUI_PANEL_MID+=("")
        printf -v line '  TOTAL: %d vulns active' "$total_active"
        TUI_PANEL_MID+=("$line")
    }

    _build_incidents_panel() {
        TUI_PANEL_RIGHT=()
        while IFS= read -r line; do
            TUI_PANEL_RIGHT+=("  ${line:0:60}")
        done < <(live_tail_incidents 15)
    }

    _draw_modal() {
        local title="$1" body="$2"
        local w=52 h=10
        local x=$(( (TUI_TERM_W - w) / 2 ))
        local y=$(( (TUI_TERM_H - h) / 2 ))

        tput cup "$y" "$x"
        local i
        printf '\033[7m %-*s \033[0m' "$((w-2))" " $title "
        for ((i = 1; i < h - 1; i++)); do
            tput cup $((y + i)) "$x"
            printf ' %-*s ' "$((w-2))" ""
        done
        tput cup $((y + h - 1)) "$x"
        printf '\033[7m %-*s \033[0m' "$((w-2))" " Press any key to close "

        echo "$body" | head -$((h - 3)) | while IFS= read -r b_line; do
            tput cup $((y + 1)) "$x"
            printf ' %-*s ' "$((w-2))" "${b_line:0:$((w-4))}"
            y=$((y + 1))
        done

        read -r -n1 -s _
        tui_refresh
    }

    _malware_menu() {
        local choice
        tput cup $((TUI_TERM_H / 2 - 3)) $((TUI_TERM_W / 2 - 25))
        printf '\033[7m %-48s \033[0m' " MALWARE SIMULATION "
        tput cup $((TUI_TERM_H / 2 - 1)) $((TUI_TERM_W / 2 - 25)); printf '  [1] Drop EICAR test file'
        tput cup $((TUI_TERM_H / 2))     $((TUI_TERM_W / 2 - 25)); printf '  [2] Run ransomware demo'
        tput cup $((TUI_TERM_H / 2 + 1)) $((TUI_TERM_W / 2 - 25)); printf '  [3] Restore ransomware demo'
        tput cup $((TUI_TERM_H / 2 + 2)) $((TUI_TERM_W / 2 - 25)); printf '  [4] Check C2 beacon'
        tput cup $((TUI_TERM_H / 2 + 3)) $((TUI_TERM_W / 2 - 25)); printf '  [5] Back'

        read -r -n1 choice
        case "$choice" in
            1) malware_drop_eicar; _draw_modal "EICAR" "EICAR test file dropped." ;;
            2) malware_ransomware_demo_run; _draw_modal "Ransomware Demo" "Demo run complete. Files under ransomware_target/ are now *.locked." ;;
            3) malware_ransomware_demo_restore; _draw_modal "Ransomware Demo" "Files restored." ;;
            4)
                if malware_c2_beacon_check; then
                    _draw_modal "C2 Beacon" "Beacon check succeeded."
                else
                    _draw_modal "C2 Beacon" "Beacon check failed (is the web app running?)."
                fi
                ;;
        esac
    }

    _refresh_all() {
        _build_services_panel
        _build_vulns_panel
        _build_incidents_panel
        tui_refresh
    }

    _refresh_all

    while [ "$TUI_RUNNING" -eq 1 ]; do
        local key
        key="$(read -n1 -t2 key 2>/dev/null && echo "$key")" || { _refresh_all; continue; }

        case "$key" in
            D|d)
                TUI_PANEL_RIGHT=("" "  [*] Re-deploying services..." "")
                tui_refresh
                bait_generate_all 2>/dev/null
                if webapp_up >/dev/null 2>&1; then
                    state_set_status "deployed"
                    monitor_start
                    TUI_PANEL_RIGHT=("" "  [OK] Services deployed." "")
                else
                    TUI_PANEL_RIGHT=("" "  [ERR] Deploy failed. Is Docker running?" "")
                fi
                tui_refresh
                sleep 2
                _refresh_all
                ;;
            T|t)
                TUI_PANEL_RIGHT=("" "  [*] Tearing down..." "")
                tui_refresh
                monitor_stop 2>/dev/null
                webapp_down 2>/dev/null
                state_reset 2>/dev/null
                TUI_PANEL_RIGHT=("" "  [OK] Services stopped." "")
                tui_refresh
                sleep 2
                _refresh_all
                ;;
            M|m)
                _malware_menu
                _refresh_all
                ;;
            B|b)
                local bait_list
                bait_list="$(state_manifest_list 2>/dev/null || echo "No bait files")"
                _draw_modal "BAIT FILE INVENTORY" "$bait_list"
                _refresh_all
                ;;
            Q|q|"ESC")
                tui_cleanup
                return
                ;;
        esac
    done
}
