# Victim Live ANSI TUI Dashboard — Design Spec

Date: 2026-07-17
Status: Approved

## Overview

Replace the whiptail-based victim dashboard with a persistent 3-panel ANSI TUI that auto-refreshes every 2 seconds. Shows live service status with connection counts, kill-chain vulnerability tallies, and real-time incident log. Reuses the existing `ansi_tui.sh` rendering engine. Preserves old whiptail victim dashboard as fallback.

---

## 1. Layout

```
+-------------------------------------------------------------------------------+
|  [HACKER LABS] - Victim Dashboard v1.0               [Status: 7 svcs running] |
+-------------------------------------------------------------------------------+
|  HOST: victim-lab                                       [Bait: 31 files]       |
+-------------------------------------------------------------------------------+
|  |  SERVICES & CONNS       |  VULNERABILITIES         |  INCIDENTS             |
|                            |                          |  [14:02:31] GET /adm.. |
|  [UP] webapp       :8080   |  RECON:     5  [ACTIVE]  |  [14:02:35] failed ss |
|       3 connections        |  INIT ACCESS:6 [ACTIVE]  |  [14:02:40] POST /lo.. |
|  [UP] ssh-decoy    :2222   |  EXECUTION: 8  [ACTIVE]  |  [14:02:42] baited fi. |
|       1 connection         |  PRIV ESC:  4  [ACTIVE]  |  [14:02:45] SSH brute. |
|  [UP] ftp-decoy    :2121   |  PERSIST:   2  [ACTIVE]  |                        |
|       0 connections        |  CRED:      5  [ACTIVE]  |                        |
|  [UP] db           :3306   |  COLLECT:   6  [ACTIVE]  |                        |
|       1 connection         |  WEB VULNS: 9  [ACTIVE]  |                        |
|  [UP] apache-41773 :8081   |  EXFIL:     2  [ACTIVE]  |                        |
|       0 connections        |  C2:        1  [ACTIVE]  |                        |
|  [UP] shellshock   :8082   |  IMPACT:    5  [ACTIVE]  |                        |
|       0 connections        |                          |                        |
|  [UP] proftpd      :2122   |  CVE SVC:   6  [ACTIVE]  |                        |
|       0 connections        |  FLASK CVE: 3  [ACTIVE]  |                        |
|  [UP] webmin       :10000  |                          |                        |
|       0 connections        |  TOTAL:    68  vulns     |                        |
|  [UP] tomcat       :8083   |                          |                        |
|       0 connections        |                          |                        |
+-------------------------------------------------------------------------------+
|  <D> DEPLOY | <T> TEARDOWN | <M> MALWARE | <B> BAIT | <R> REFRESH | <Q> BACK |
+-------------------------------------------------------------------------------+
```

---

## 2. Panels

### 2.1 Services & Connections Panel (Left, 1/3)

Lists all services with live status and TCP connection counts.

- Runs `webapp_status` (docker-compose ps) for container status
- Probes each port via `ss -tulpn` or `/dev/tcp` checks for UP/DOWN
- Counts ESTABLISHED TCP connections per port: `ss -tn state established sport = :PORT | wc -l`
- Each service row:
  ```
  [UP] service-name  :PORT
       N connections
  ```
- Green `[UP]` if port is open, red `[DN]` if closed
- Connection count shown on a sub-line, indented
- Services tracked: webapp(:8080), ssh-decoy(:2222), ftp-decoy(:2121), db(:3306), apache-41773(:8081), shellshock(:8082), proftpd(:2122), webmin(:10000), tomcat(:8083)
- Header in target bar shows: `Bait: N files`

### 2.2 Vulnerabilities Panel (Middle, 1/3)

Kill-chain organized vuln counts, live-updating based on which ports are up.

- If webapp port 8080 is up → all Flask endpoints count as active
- If CVE service port is up → that CVE counts as active
- Each row: `PHASE:    N  [ACTIVE]` or `PHASE:    N  [INACTIVE]`
- Shows running total at bottom
- Phases: RECON, INIT ACCESS, EXECUTION, PRIV ESC, PERSIST, CRED, COLLECT, WEB VULNS, EXFIL, C2, IMPACT, CVE SVC, FLASK CVE

### 2.3 Incidents Panel (Right, 1/3)

Real-time tail of `incident_log.txt` (last 15 lines). Updates every 2s.

- If log file is empty: shows "No attacker activity detected yet"
- Truncates long lines to panel width
- Auto-scrolls to newest entries at bottom

---

## 3. Refresh Loop

Main event loop polls every 2 seconds:

```
while running:
    probe_all_services()       # ss + docker ps
    count_vulns_by_phase()     # based on active ports
    tail_incidents()           # read last N lines from log
    build_panel_content()      # populate TUI_PANEL_ arrays
    tui_refresh()              # redraw all panels
    read key (timeout 2000ms)  # non-blocking, 2s timeout
    process key if pressed
```

Key read uses `read -n1 -t2` to timeout after 2s before next refresh cycle. No busy-wait.

---

## 4. Hotkeys

| Key | Action |
|-----|--------|
| `D` | Deploy all services (same `victim_deploy` logic — generates bait, runs webapp_up, starts monitor) |
| `T` | Teardown (stops monitor, runs webapp_down, resets state) |
| `M` | Malware simulation menu (EICAR drop, ransomware demo, C2 beacon) — modal overlay using simple ANSI menu |
| `B` | Bait file inventory list — modal overlay |
| `F` | Force immediate refresh |
| `Q` / `Esc` | Exit back to main menu, stops monitor background jobs |

Deploy/Teardown block the loop with a longer timeout, then resume refreshing.

---

## 5. Implementation

### 5.1 New File: `bait_n_break/victim/lib_live_dashboard.sh`

Provides data-gathering functions called by the TUI refresh loop:

```bash
live_probe_services()        # Returns associative array of service->{port, status, connections}
live_count_vulns()           # Returns vuln counts per kill-chain phase
live_tail_incidents(n)       # Returns last N lines from incident_log.txt
live_get_bait_count()        # Returns total bait file count
live_get_hostname()          # Returns hostname
```

All functions are pure bash, using `ss`, `docker compose ps`, `wc -l`, `tail`. No external deps beyond what setup.sh already installs.

### 5.2 Modified File: `bait_n_break/tui/victim_dashboard.sh`

- Rewrites `victim_dashboard()` — replaces whiptail event loop with ANSI TUI event loop
- Sources `ansi_tui.sh` and `lib_live_dashboard.sh`
- Keeps `victim_deploy()` and `victim_teardown()` logic intact, wraps in TUI refresh context
- Adds ANSI-based simple modal overlays for malware menu and bait inventory (not whiptail — pure ANSI text centered on screen with key prompt)

### 5.3 New File: `bait_n_break/tui/victim_dashboard_fallback.sh`

Copy of the current `victim_dashboard.sh` (whiptail version) before rewrite. Used when terminal is too small for ANSI TUI.

### 5.4 No Changes To

- `ansi_tui.sh` — unchanged, reused as-is
- `lib_webapp.sh` — unchanged
- `lib_monitor.sh` — unchanged
- `lib_bait.sh` — unchanged
- `lib_malware_sim.sh` — unchanged
- `lib_vuln_overview.sh` — kept for static one-shot use

---

## 6. Edge Cases

| Scenario | Behavior |
|----------|----------|
| Terminal < 80x24 | Fall back to whiptail victim dashboard |
| Docker daemon unreachable | All services show `[DN]`, `[ERR]` in header status |
| No services deployed | All `[DN]`, vuln counts show `[INACTIVE]` |
| Incident log empty | Shows "No attacker activity detected yet" |
| SS command unavailable | Fall back to `/dev/tcp` port probing |
| SIGWINCH (resize) | Trap and redraw layout |
| Background monitor jobs from deploy | Stopped on Q/Teardown via existing trap on EXIT |

---

## 7. Files Summary

### Created
```
bait_n_break/victim/lib_live_dashboard.sh       # Data-gathering functions
bait_n_break/tui/victim_dashboard_fallback.sh   # Old whiptail backup
```

### Modified
```
bait_n_break/tui/victim_dashboard.sh            # Rewrite: ANSI TUI event loop
```

### Unchanged
```
bait_n_break/tui/ansi_tui.sh                    # Reused as-is
bait_n_break/victim/lib_webapp.sh
bait_n_break/victim/lib_monitor.sh
bait_n_break/victim/lib_bait.sh
bait_n_break/victim/lib_malware_sim.sh
bait_n_break/victim/lib_vuln_overview.sh
```
