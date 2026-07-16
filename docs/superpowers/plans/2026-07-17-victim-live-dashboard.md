# Victim Live ANSI TUI Dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace whiptail victim dashboard with a persistent 3-panel ANSI TUI showing live service status with connection counts, kill-chain vulnerability tallies, and real-time incident log — all auto-refreshing every 2 seconds.

**Architecture:** New `lib_live_dashboard.sh` provides pure-bash data-gathering functions (port probes, vuln counting, incident reading). Modified `victim_dashboard.sh` runs the ANSI event loop using the existing `ansi_tui.sh` engine. Old whiptail dashboard preserved as fallback. All existing lib_* files unchanged.

**Tech Stack:** Bash 4.x+, tput/ncurses (via ansi_tui.sh), ss (from iproute2), docker-compose

---

## File Structure

```
bait_n_break/
  victim/
    lib_live_dashboard.sh               # NEW: data-gathering functions
  tui/
    ansi_tui.sh                         # UNCHANGED: reused as-is
    victim_dashboard.sh                 # REWRITE: ANSI TUI event loop
    victim_dashboard_fallback.sh        # NEW: copy of old whiptail version
```

---

### Task 1: Create `lib_live_dashboard.sh` — Data-Gathering Functions

**Files:**
- Create: `bait_n_break/victim/lib_live_dashboard.sh`

- [ ] **Step 1: Create the complete file**

Write the full file to `bait_n_break/victim/lib_live_dashboard.sh`:

```bash
#!/usr/bin/env bash
# Live data-gathering functions for the victim ANSI TUI dashboard.
# Provides port probing, vuln counting, incident reading.
# Sourced, not executed.

LIVE_SERVICES=(
    "webapp:8080"
    "ssh-decoy:2222"
    "ftp-decoy:2121"
    "db:3306"
    "apache-41773:${BNB_CVE_APACHE_41773_PORT:-8081}"
    "shellshock:${BNB_CVE_SHELLSHOCK_PORT:-8082}"
    "proftpd:${BNB_CVE_PROFTPD_PORT:-2122}"
    "webmin:${BNB_CVE_WEBMIN_PORT:-10000}"
    "tomcat:${BNB_CVE_TOMCAT_HTTP_PORT:-8083}"
)

live_probe_services() {
    local -n result="$1" 2>/dev/null || return 1
    result=()

    for svc_entry in "${LIVE_SERVICES[@]}"; do
        local name="${svc_entry%%:*}"
        local port="${svc_entry##*:}"
        local status="DOWN"
        local conns="0"

        if ss -tulpn 2>/dev/null | grep -q ":${port}\b"; then
            status="UP"
        elif (exec 3<>/dev/tcp/127.0.0.1/${port}) 2>/dev/null; then
            status="UP"
            exec 3<&- 2>/dev/null
            exec 3>&- 2>/dev/null
        fi

        if [ "$status" = "UP" ]; then
            conns="$(ss -tn state established sport = ":${port}" 2>/dev/null | wc -l)"
            conns=$((conns - 1))
            [ "$conns" -lt 0 ] && conns=0
        fi

        result+=("${name}|${port}|${status}|${conns}")
    done
}

live_count_vulns() {
    local webapp_up=0
    local cve41773_up=0
    local cve6271_up=0
    local cve3306_up=0
    local cve15107_up=0
    local cve1938_up=0

    if ss -tulpn 2>/dev/null | grep -q ':8080\b' || (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null; then
        webapp_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_APACHE_41773_PORT:-8081}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_APACHE_41773_PORT:-8081}) 2>/dev/null; then
        cve41773_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_SHELLSHOCK_PORT:-8082}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_SHELLSHOCK_PORT:-8082}) 2>/dev/null; then
        cve6271_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_PROFTPD_PORT:-2122}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_PROFTPD_PORT:-2122}) 2>/dev/null; then
        cve3306_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_WEBMIN_PORT:-10000}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_WEBMIN_PORT:-10000}) 2>/dev/null; then
        cve15107_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_TOMCAT_HTTP_PORT:-8083}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_TOMCAT_HTTP_PORT:-8083}) 2>/dev/null; then
        cve1938_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi

    printf '%s\n' \
        "RECON|5|$webapp_up" \
        "INIT ACCESS|6|$webapp_up" \
        "EXECUTION|8|$webapp_up" \
        "PRIV ESC|4|$webapp_up" \
        "PERSIST|2|$webapp_up" \
        "CRED|5|$webapp_up" \
        "COLLECT|6|$webapp_up" \
        "WEB VULNS|9|$webapp_up" \
        "EXFIL|2|$webapp_up" \
        "C2|1|$webapp_up" \
        "IMPACT|5|$webapp_up" \
        "CVE-41773|1|$cve41773_up" \
        "CVE-6271|1|$cve6271_up" \
        "CVE-3306|1|$cve3306_up" \
        "CVE-15107|1|$cve15107_up" \
        "CVE-1938|1|$cve1938_up" \
        "FLASK CVE|3|$webapp_up"
}

live_tail_incidents() {
    local lines="${1:-15}"
    if [ -f "${BNB_INCIDENT_LOG}" ] && [ -s "${BNB_INCIDENT_LOG}" ]; then
        tail -n "$lines" "${BNB_INCIDENT_LOG}" 2>/dev/null
    else
        echo "No attacker activity detected yet"
    fi
}

live_get_bait_count() {
    find "${BNB_STATE_DIR}/bait" -type f 2>/dev/null | wc -l
}

live_get_hostname() {
    hostname 2>/dev/null || echo "victim-lab"
}

live_get_service_count() {
    local -a svc_data
    live_probe_services svc_data
    local count=0
    for entry in "${svc_data[@]}"; do
        local status="${entry##*|}"
        status="${status%%|*}"
        [ "$status" = "UP" ] && count=$((count + 1))
    done
    echo "$count"
}
```

- [ ] **Step 2: Commit**

```bash
git add bait_n_break/victim/lib_live_dashboard.sh
git commit -m "feat: add live data-gathering functions for victim TUI dashboard"
```

---

### Task 2: Rewrite Victim Dashboard as ANSI TUI

**Files:**
- Create: `bait_n_break/tui/victim_dashboard_fallback.sh` (copy old)
- Modify: `bait_n_break/tui/victim_dashboard.sh` (rewrite)

- [ ] **Step 1: Preserve old victim_dashboard.sh as fallback**

```bash
cp bait_n_break/tui/victim_dashboard.sh bait_n_break/tui/victim_dashboard_fallback.sh
```

- [ ] **Step 2: Write new victim_dashboard.sh**

Write the complete file to `bait_n_break/tui/victim_dashboard.sh`:

```bash
#!/usr/bin/env bash
# Victim (Target) role dashboard — persistent ANSI TUI with live-updating
# service status, vulnerability counts, and incident log.
# Falls back to whiptail if terminal is too small.
# Sourced, not executed.

victim_dashboard() {
    # shellcheck source=bait_n_break/tui/ansi_tui.sh
    source "${BNB_ROOT}/bait_n_break/tui/ansi_tui.sh"

    if ! tui_init; then
        source "${BNB_ROOT}/bait_n_break/tui/victim_dashboard_fallback.sh"
        _victim_dashboard_fallback
        return
    fi
    trap 'tui_cleanup; monitor_stop 2>/dev/null' EXIT INT

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

    TUI_LEFT_TITLE="SERVICES & CONNS"
    TUI_MID_TITLE="VULNERABILITIES"
    TUI_RIGHT_TITLE="INCIDENTS"
    TUI_HEADER_TITLE="HACKER LABS"
    TUI_HEADER_STATUS="Idle"
    TUI_TARGET_TYPE="victim-lab"

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
        key="$(read -n1 -t2 key && echo "$key")" || { _refresh_all; continue; }

        case "$key" in
            D|d)
                TUI_PANEL_RIGHT=("" "  [*] Deploying services..." "")
                tui_refresh
                bait_generate_all 2>/dev/null
                if webapp_up 2>/dev/null; then
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
            F|f)
                _refresh_all
                ;;
            Q|q|"ESC")
                tui_cleanup
                return
                ;;
        esac
    done
}
```

- [ ] **Step 3: Commit both files**

```bash
git add bait_n_break/tui/victim_dashboard.sh bait_n_break/tui/victim_dashboard_fallback.sh
git commit -m "feat: rewrite victim dashboard as live ANSI TUI with connection monitoring"
```

---

### Task 3: Final Verification

- [ ] **Step 1: Bash syntax check on all new/modified files**

```bash
wsl bash -n bait_n_break/victim/lib_live_dashboard.sh && echo "lib_live_dashboard.sh: OK" || echo "FAIL"
wsl bash -n bait_n_break/tui/victim_dashboard.sh && echo "victim_dashboard.sh: OK" || echo "FAIL"
wsl bash -n bait_n_break/tui/victim_dashboard_fallback.sh && echo "fallback: OK" || echo "FAIL"
```

- [ ] **Step 2: Verify fallback file exists and has _victim_dashboard_fallback function**

```bash
grep -q '_victim_dashboard_fallback' bait_n_break/tui/victim_dashboard.sh && echo "OK: references fallback" || echo "FAIL: missing fallback ref"
```

Wait — the fallback file was copied from the old `victim_dashboard.sh` which defines `victim_dashboard()`, not `_victim_dashboard_fallback()`. Need to rename the function in the fallback file. This is the same bug pattern we found in the attacker console fallback.

Edit the fallback file: change `victim_dashboard()` to `_victim_dashboard_fallback()`.

```bash
sed -i 's/^victim_dashboard()/_victim_dashboard_fallback()/' bait_n_break/tui/victim_dashboard_fallback.sh
```

- [ ] **Step 3: Verify function cross-references**

```bash
echo "=== Functions referenced in victim_dashboard.sh ==="
for fn in live_probe_services live_count_vulns live_tail_incidents live_get_bait_count live_get_hostname state_set_status state_reset state_manifest_list bait_generate_all webapp_up webapp_down monitor_start monitor_stop malware_drop_eicar malware_ransomware_demo_run malware_ransomware_demo_restore malware_c2_beacon_check; do
    grep -q "$fn" bait_n_break/victim/lib_live_dashboard.sh bait_n_break/victim/lib_bait.sh bait_n_break/victim/lib_webapp.sh bait_n_break/victim/lib_monitor.sh bait_n_break/victim/lib_malware_sim.sh bait_n_break/shared/lib_state.sh 2>/dev/null && echo "  OK: $fn" || echo "  MISSING: $fn"
done
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: final verification — victim live ANSI TUI dashboard complete"
```

---

## Self-Review Checklist

- [ ] **Spec coverage**:
  - Section 2.1 (Services panel with connections) → Task 1 (live_probe_services) + Task 2 (_build_services_panel)
  - Section 2.2 (Vulnerabilities panel) → Task 1 (live_count_vulns) + Task 2 (_build_vulns_panel)
  - Section 2.3 (Incidents panel) → Task 1 (live_tail_incidents) + Task 2 (_build_incidents_panel)
  - Section 3 (Refresh loop 2s) → Task 2 (read -n1 -t2 + loop)
  - Section 4 (Hotkeys D/T/M/B/F/Q) → Task 2 (case statement)
  - Section 5.2 (Modal overlays) → Task 2 (_draw_modal, _malware_menu)
  - Section 5.3 (Fallback) → Task 2 Step 1 (copy old), Task 3 Step 2 (rename function)
  - Section 6 (Edge cases) → Task 1 (ss fallback to /dev/tcp), Task 2 (terminal size check, tui_init guard)

- [ ] **No placeholders**: All tasks have complete code, no TBD/TODO

- [ ] **Type consistency**: Function names match across tasks and match existing codebase. `live_probe_services` returns parsed array consumed by `_build_services_panel`. `live_count_vulns` outputs pipe-delimited lines consumed by `_build_vulns_panel`.
