# bait-n-break — Phase 1 Design: TUI Shell + Victim Module

Date: 2026-07-14
Status: Approved (pending written-spec review)

## Goal

Build the foundation of `bait-n-break`, a self-contained, isolated-lab red/blue team training range: a single-entry-point TUI plus the full **Victim (Target) module**. The Attacker (Kali) module is an explicit separate Phase 2 (its own spec later), so the interfaces the Victim module exposes (target state, log formats, config) are designed to be consumable by attacker scripts without rework.

Out of scope for this document: attacker exploit scripts, attacker TUI console (a placeholder file only), anything beyond a working victim node + shell.

## Decisions carried in from brainstorming

- Deployment: vulnerable web app runs in **Docker** (not native host process) — safer to reset, doesn't pollute the host, `setup.sh` just needs Docker + compose.
- Phase 1 scope is the **full victim spec**, including malware/ransomware/C2 simulation (not deferred).
- Code comments are written in **English**; conversation/design docs may be in Thai.
- Development must use the `superpowers` skill set (`brainstorming`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`) and every module needs an explicit manual QA/debug pass (real end-to-end TUI run) before being considered done — no automated test suite planned for this shell/infra project.
- Attacker module design (Phase 2) will follow the `red-team` skill's methodology: kill-chain phase ordering, crown-jewel framing (bait files = crown jewels), and technique effort/OPSEC-risk scoring in results output. The skill's `--authorized`/RoE tooling itself doesn't apply (this is a self-owned isolated lab, not a third-party engagement) — only the structuring methodology is reused.

## 1. Architecture & directory structure

```
bait-n-break/
  run.sh                     # single entry point: source shared libs, launch tui/main_menu.sh
  setup.sh                   # installs docker, docker-compose plugin, whiptail/dialog, inotify-tools, iproute2
  CLAUDE.md
  bait_n_break/
    tui/
      main_menu.sh           # role menu: [1] Victim [2] Attacker [3] Exit
      victim_dashboard.sh    # deploy / status / bait inventory / monitor / teardown submenu
      attacker_console.sh    # Phase 2 placeholder only
    victim/
      lib_bait.sh            # generates bait files from templates, writes .state/bait_manifest.txt
      lib_webapp.sh           # docker compose up/down/status wrapper for the vulnerable app
      lib_monitor.sh          # tails docker logs + auth.log + bait-access watcher into incident_log.txt
      lib_malware_sim.sh      # EICAR drop, ransomware-demo (sandboxed dir only), C2 beacon check
      webapp/
        Dockerfile
        app.py                # Flask app, all vulnerable endpoints
        docker-compose.yml
    attacker/                 # empty in Phase 1 (Phase 2 target)
    shared/
      lib_ui.sh                # whiptail -> dialog -> plain select/read fallback wrapper functions
      lib_state.sh              # sole reader/writer of .state/* flat files
      config.sh                 # shared constants/paths; TARGET_IP variable Phase 2 will consume
  .state/                       # gitignored runtime state: status flags, PID files, manifests, logs
```

Principle: `run.sh` has no logic of its own — it sources the libs and calls `main_menu.sh`. Library files are pure functions with no side effects on `source`, so each is independently testable/runnable.

## 2. TUI flow & state management

- `main_menu.sh` shows `[1] Victim (Target)` / `[2] Attacker` / `[3] Exit` via `lib_ui.sh`'s auto-detected backend (whiptail → dialog → `select`/`read`).
- Selecting Victim opens `victim_dashboard.sh` with a submenu:
  - **Deploy / Start victim services** — calls `lib_bait.sh` then `lib_webapp.sh` (`docker compose up -d`)
  - **Service Status Panel** — `docker compose ps` + open host ports (`ss -tulpn`), shown as Active/Inactive
  - **Honey-Asset Inventory** — lists bait files from `.state/bait_manifest.txt`
  - **Access & Incident Monitor** — live view from `lib_monitor.sh`
  - **Stop / Teardown** — `docker compose down -v`, clears `.state/*` and generated bait files
- All runtime state lives in `.state/` as flat files (no DB): `.state/victim_status`, `.state/bait_manifest.txt`, `.state/incident_log.txt`, `.state/bait_access.log`. `lib_state.sh` is the only code allowed to read/write these directly — other modules call its functions.
- Error handling: every lib function returns a standard exit code (0 = success, non-zero = failure); `lib_ui.sh` provides `ui_msgbox`/`ui_error` so failures (e.g. Docker not installed) surface to the user instead of failing silently.

## 3. Bait files & vulnerable web app (kill-chain mapped)

Each asset/endpoint is deliberately mapped to the kill-chain phase Phase 2 will exercise it under, so attacker scripts and victim endpoints stay in sync:

| Asset / Endpoint | Vulnerability | Kill-chain phase |
|---|---|---|
| `/admin`, directory listing, debug mode on | Improper configuration | Reconnaissance |
| `.env`, `passwords.txt`, `*.tar.gz`, `production_dump.sql` in `/var/www/html/backups/`, `/opt/deception/` | Data leakage | Reconnaissance / Collection |
| `/login` | SQL injection (auth bypass) | Initial Access |
| SSH / FTP / web-admin | Weak credentials | Initial Access |
| Ping/util endpoint | Command injection | Execution |
| `/upload` | Unrestricted file upload → webshell | Execution / Persistence |
| Comment/profile field | Stored XSS | Collection (session/cookie theft) |
| Search box | Reflected XSS | (demo only, no phase mapping) |
| `/home/ubuntu/secrets/employee_records.db`, `payroll_2025.csv` | Sensitive data exposure | Collection |
| Ransomware-demo trigger | Sandboxed file-encrypt demo | Impact |
| C2 beacon endpoint (`/c2/beacon`) | Mock beacon, local only | Command & Control (tracked but outside the 11-phase list) |
| EICAR drop | Inert signature file | Impact (harmless) |

Implementation: all endpoints live in one Flask `app.py` in one container. Bait files are generated by `lib_bait.sh` from templates (dummy data only, never real credentials) before container start, then bind-mounted into the container at the three spec'd paths (`/var/www/html/backups/`, `/home/ubuntu/secrets/`, `/opt/deception/`) as separate Docker volumes. A manifest of what was generated goes to `.state/bait_manifest.txt`.

## 4. Access & Incident Monitor + malware simulation

**Monitor (`lib_monitor.sh`)** combines three sources into one dashboard view:
1. `docker compose logs -f` — web app access/error log
2. `tail -f /var/log/auth.log` — SSH/FTP brute-force attempts
3. Bait-file access watcher — `inotifywait -m -e access,open <bait paths>` when available, else polling on `stat -c %X` (access time) as a fallback

All captured events are normalized to `[timestamp] [source] [detail]` and appended to `.state/incident_log.txt` for a persistent, scrollable history (not just the live tail).

**Malware/ransomware simulation (`lib_malware_sim.sh`)**:
- **EICAR drop**: standard EICAR test string dropped at a bait path — industry-standard, harmless, not real malware.
- **Ransomware-demo**: triggerable (via webshell or manually from the TUI) script that copies and encrypts (e.g. `openssl enc` with a fixed key) files strictly inside `/opt/deception/ransomware_target/`, then drops a ransom note. Scope is hard-limited to that one directory — never touches anything else.
- **C2 beacon check**: a mock `/c2/beacon` route inside the same Flask app; something (cron/other container) beacons to it periodically to simulate C2 traffic without any real internet C2 involved.
- All malware-sim events also write into `incident_log.txt`.

## 5. Setup script & verification

**`setup.sh`**: detects OS via `/etc/os-release`, installs only what's missing (`docker.io`/compose plugin, `whiptail`, `dialog`, `inotify-tools`, `iproute2`). Idempotent — safe to re-run. Only installs dependencies; does not deploy services itself (that's the TUI's "Deploy" action).

**Teardown/reset**: `docker compose down -v` + delete generated bait files + clear `.state/*`, so the lab can be reset to a clean state repeatedly.

**Verification (manual QA/debug pass per the Development process convention — no automated test suite for this shell/infra project)**:
- Bait files: confirm every path in the manifest exists with real dummy content (not empty placeholders).
- Vulnerable web app: after `docker compose up -d`, manually curl each endpoint to confirm it's actually exploitable as designed (e.g. the SQLi payload really bypasses login, not just a 200 response).
- Monitor: trigger a bait-file access / endpoint hit and confirm the event appears both in `.state/incident_log.txt` and in the live TUI view.
- Malware sim: confirm the ransomware-demo only ever touches `/opt/deception/ransomware_target/` and nothing outside it.

## Open items for Phase 2 (not designed here)

- Attacker module directory contents, exploit scripts per endpoint above, recon/brute-force scripts, "Run All Scenarios" kill-chain runner, attacker TUI console, results summary format (`[SUCCESS]`/`[FAILED]`/`[VULNERABLE]` + OPSEC risk annotation per the `red-team` skill).
