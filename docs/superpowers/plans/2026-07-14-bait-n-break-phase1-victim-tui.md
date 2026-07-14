# bait-n-break Phase 1 (TUI Shell + Victim Module) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the single-entry-point TUI shell and the full Victim (Target) module for `bait-n-break`, per `docs/superpowers/specs/2026-07-14-bait-n-break-phase1-victim-tui-design.md`.

**Architecture:** Pure-bash TUI (`run.sh` -> `tui/main_menu.sh` -> `tui/victim_dashboard.sh`) driving a set of pure-function shell libraries (`shared/`, `victim/`) that own state, UI rendering, bait generation, Docker orchestration, log monitoring, and inert malware simulation. The one exception to bash-only is the vulnerable web app itself (`victim/webapp/app.py`), a Flask app run in Docker.

**Tech Stack:** Bash (POSIX-ish, `set -uo pipefail`), whiptail/dialog with a plain `select`/`read` fallback, Docker + Docker Compose, Python 3 / Flask for the vulnerable web app, SQLite for the app's demo DB.

## Global Constraints

- Bash/shell only for the TUI/orchestration layer; no Python/Node/other runtime there. The vulnerable web app is the sole exception (Python/Flask, Docker-based) per CLAUDE.md.
- Single entry point: `./run.sh`. `run.sh` has no logic of its own — it sources libs and calls `main_menu`.
- TUI backend auto-detects whiptail -> dialog -> plain `select`/`read`; must work out of the box on stock Ubuntu and Kali.
- All runtime state lives under `.state/` as flat files. `bait_n_break/shared/lib_state.sh` is the **only** code allowed to read/write those files directly; every other module calls its functions.
- Every library file is a pure collection of functions with **no side effects on `source`** (no `mkdir`, no network calls, no process spawns at source time).
- Bait content, "leaked" credentials, and malware-sim payloads must be dummy/inert — never real secrets, safe to leave on disk, safe to run.
- Code comments are written in English.
- Every lib function returns a standard exit code (0 = success, non-zero = failure); failures surface to the user via `ui_msgbox`/`ui_error`, never silently.
- No automated test suite for this shell/infra project (per CLAUDE.md's Development process). Each task's "test" is a syntax check plus a concrete manual verification command with the exact expected output — run it and confirm the output, don't just read the code.
- Ransomware-demo simulation must never touch anything outside `.state/bait/deception/ransomware_target/`.
- Bait file drop paths (bind-mounted into the webapp container): backups -> `/bait/backups`, secrets -> `/bait/secrets`, deception -> `/bait/deception`, sourced on the host from `.state/bait/{backups,secrets,deception}/`.
- Only files meant to be *executed* directly (`run.sh`, `setup.sh`) call `set -uo pipefail`. Files meant to be *sourced* (everything under `shared/`, `victim/`, `tui/` except `run.sh` itself) must NOT set shell options — doing so mutates the sourcing shell's global option state (`nounset`/`pipefail`) for the rest of that shell's life, which is exactly the kind of side-effect-on-source the "pure functions" constraint above forbids.

---

## Task 1: Shared config, UI abstraction, and `.gitignore`

**Files:**
- Create: `bait_n_break/shared/config.sh`
- Create: `bait_n_break/shared/lib_ui.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces (consumed by every later task): env vars `BNB_ROOT`, `BNB_STATE_DIR`, `BNB_VICTIM_DIR`, `BNB_WEBAPP_DIR`, `BNB_STATE_FILE`, `BNB_BAIT_MANIFEST`, `BNB_INCIDENT_LOG`, `BNB_BAIT_ACCESS_LOG`, `BNB_BAIT_BACKUPS_DIR`, `BNB_BAIT_SECRETS_DIR`, `BNB_BAIT_DECEPTION_DIR`, `TARGET_IP`, `TARGET_PORT`; functions `ui_backend()`, `ui_menu(title, prompt, tag1, item1, ...)`, `ui_msgbox(title, text)`, `ui_error(title, text)`, `ui_yesno(title, text)`.

- [ ] **Step 1: Write `bait_n_break/shared/config.sh`**

```bash
#!/usr/bin/env bash
# Shared configuration and path constants for bait-n-break.
# Sourced by every module. Must have no side effects beyond variable exports.
# Deliberately does NOT set shell options (set -u/-e/pipefail) - this file
# is sourced, not executed, and mutating the caller's shell options is a
# side effect the "no side effects on source" constraint forbids. Only
# run.sh and setup.sh (executed directly) set shell options.

BNB_ROOT="${BNB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

BNB_STATE_DIR="${BNB_ROOT}/.state"
BNB_VICTIM_DIR="${BNB_ROOT}/bait_n_break/victim"
BNB_WEBAPP_DIR="${BNB_VICTIM_DIR}/webapp"

BNB_STATE_FILE="${BNB_STATE_DIR}/victim_status"
BNB_BAIT_MANIFEST="${BNB_STATE_DIR}/bait_manifest.txt"
BNB_INCIDENT_LOG="${BNB_STATE_DIR}/incident_log.txt"
BNB_BAIT_ACCESS_LOG="${BNB_STATE_DIR}/bait_access.log"

BNB_BAIT_BACKUPS_DIR="${BNB_STATE_DIR}/bait/backups"
BNB_BAIT_SECRETS_DIR="${BNB_STATE_DIR}/bait/secrets"
BNB_BAIT_DECEPTION_DIR="${BNB_STATE_DIR}/bait/deception"

# TARGET_IP/PORT: consumed by Phase 2 attacker scripts. Empty TARGET_IP
# means "not configured yet" - Phase 1 does not require it.
TARGET_IP="${TARGET_IP:-}"
TARGET_PORT="${TARGET_PORT:-8080}"
```

- [ ] **Step 2: Syntax-check it**

Run: `bash -n bait_n_break/shared/config.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Write `bait_n_break/shared/lib_ui.sh`**

```bash
#!/usr/bin/env bash
# UI abstraction: whiptail -> dialog -> plain select/read fallback.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

ui_backend() {
    if command -v whiptail >/dev/null 2>&1; then
        echo "whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        echo "dialog"
    else
        echo "plain"
    fi
}

# ui_menu TITLE PROMPT TAG1 ITEM1 [TAG2 ITEM2 ...]
# Prints the chosen TAG to stdout. Returns non-zero if cancelled/no choice.
ui_menu() {
    local title="$1" prompt="$2"
    shift 2
    local backend
    backend="$(ui_backend)"

    case "$backend" in
        whiptail)
            whiptail --title "$title" --menu "$prompt" 20 70 10 "$@" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --menu "$prompt" 20 70 10 "$@" 3>&1 1>&2 2>&3
            ;;
        plain)
            echo "== $title ==" >&2
            echo "$prompt" >&2
            local i=1 tag item tags=()
            while [ $# -gt 0 ]; do
                tag="$1"; item="$2"; shift 2
                tags+=("$tag")
                echo "  [$i] $tag - $item" >&2
                i=$((i + 1))
            done
            local choice
            read -r -p "Select number: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#tags[@]}" ]; then
                echo "${tags[$((choice - 1))]}"
                return 0
            fi
            return 1
            ;;
    esac
}

ui_msgbox() {
    local title="$1" text="$2"
    local backend
    backend="$(ui_backend)"
    case "$backend" in
        whiptail) whiptail --title "$title" --msgbox "$text" 15 70 ;;
        dialog) dialog --title "$title" --msgbox "$text" 15 70 ;;
        plain)
            echo "== $title ==" >&2
            echo "$text" >&2
            read -r -p "Press Enter to continue..." _
            ;;
    esac
}

ui_error() {
    ui_msgbox "Error: $1" "$2"
}

ui_yesno() {
    local title="$1" text="$2"
    local backend
    backend="$(ui_backend)"
    case "$backend" in
        whiptail) whiptail --title "$title" --yesno "$text" 10 70 ;;
        dialog) dialog --title "$title" --yesno "$text" 10 70 ;;
        plain)
            local ans
            read -r -p "$text [y/N]: " ans
            [[ "$ans" =~ ^[Yy]$ ]]
            ;;
    esac
}
```

- [ ] **Step 4: Syntax-check and manually verify the plain fallback**

Run: `bash -n bait_n_break/shared/lib_ui.sh`
Expected: no output, exit code 0.

Run (forces the plain backend and answers menu prompt "2"):
```bash
bash -c '
source bait_n_break/shared/lib_ui.sh
command() { [ "$1" = -v ] && return 1; }  # hide whiptail/dialog for this shell
export -f command
echo 2 | ui_menu "Test" "pick one" a "Option A" b "Option B"
'
```
Expected output includes `b` as the final line (the selected tag echoed to stdout).

- [ ] **Step 5: Write `.gitignore`**

```gitignore
.state/
*.pyc
__pycache__/
*.db
uploads/
.superpowers/
```

- [ ] **Step 6: Commit**

```bash
git add bait_n_break/shared/config.sh bait_n_break/shared/lib_ui.sh .gitignore
git commit -m "Add shared config and UI abstraction layer"
```

---

## Task 2: State management library

**Files:**
- Create: `bait_n_break/shared/lib_state.sh`

**Interfaces:**
- Consumes: all `BNB_*` path vars from Task 1's `config.sh`.
- Produces (consumed by Tasks 3, 4, 8, 9, 10): `state_init()`, `state_set_status(status)`, `state_get_status()`, `state_manifest_add(path)`, `state_manifest_list()`, `state_manifest_clear()`, `state_incident_append(source, detail)`, `state_incident_tail(n)`, `state_bait_marker_touch()`, `state_bait_marker_files_since(dir)`, `state_reset()`.

- [ ] **Step 1: Write `bait_n_break/shared/lib_state.sh`**

```bash
#!/usr/bin/env bash
# Sole reader/writer of .state/* runtime files. Other modules must not
# touch .state/* directly - they call these functions instead.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

state_init() {
    mkdir -p "${BNB_STATE_DIR}" "${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}"
    touch "${BNB_STATE_FILE}" "${BNB_BAIT_MANIFEST}" "${BNB_INCIDENT_LOG}" "${BNB_BAIT_ACCESS_LOG}"
}

state_set_status() {
    echo "$1" > "${BNB_STATE_FILE}"
}

state_get_status() {
    if [ -s "${BNB_STATE_FILE}" ]; then
        cat "${BNB_STATE_FILE}"
    else
        echo "not_deployed"
    fi
}

state_manifest_add() {
    echo "$1" >> "${BNB_BAIT_MANIFEST}"
}

state_manifest_list() {
    [ -f "${BNB_BAIT_MANIFEST}" ] && cat "${BNB_BAIT_MANIFEST}"
}

state_manifest_clear() {
    : > "${BNB_BAIT_MANIFEST}"
}

state_incident_append() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [$1] $2" >> "${BNB_INCIDENT_LOG}"
}

state_incident_tail() {
    local n="${1:-50}"
    [ -f "${BNB_INCIDENT_LOG}" ] && tail -n "$n" "${BNB_INCIDENT_LOG}"
}

state_bait_marker_touch() {
    touch "${BNB_BAIT_ACCESS_LOG}"
}

state_bait_marker_files_since() {
    local dir="$1"
    find "$dir" -type f -newer "${BNB_BAIT_ACCESS_LOG}" -printf '%p accessed\n' 2>/dev/null
}

state_reset() {
    rm -f "${BNB_STATE_FILE}" "${BNB_BAIT_MANIFEST}" "${BNB_INCIDENT_LOG}" "${BNB_BAIT_ACCESS_LOG}"
    rm -rf "${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}"
    state_init
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/shared/lib_state.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify state round-trips, in a scratch state dir**

```bash
bash -c '
export BNB_ROOT="$(mktemp -d)"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_state.sh
state_init
state_set_status "deployed"
echo "status=$(state_get_status)"
state_manifest_add "/fake/path/one"
state_manifest_add "/fake/path/two"
echo "manifest_lines=$(state_manifest_list | wc -l)"
state_incident_append "test" "hello world"
state_incident_tail 5
state_reset
echo "status_after_reset=$(state_get_status)"
'
```
Expected: `status=deployed`, `manifest_lines=2`, a line containing `[test] hello world`, then `status_after_reset=not_deployed`.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/shared/lib_state.sh
git commit -m "Add state management library"
```

---

## Task 3: Entry point and top-level TUI menu

**Files:**
- Create: `run.sh`
- Create: `bait_n_break/tui/main_menu.sh`
- Create: `bait_n_break/tui/attacker_console.sh`

**Interfaces:**
- Consumes: `ui_menu`, `ui_msgbox` (Task 1), `state_init` (Task 2). Sources `bait_n_break/tui/victim_dashboard.sh` and calls `victim_dashboard` — that file does not exist until Task 10, so until then selecting "Victim" will error; this task's own verification only exercises menu navigation and Exit.
- Produces (consumed by Task 10): `main_menu()`, `attacker_console()`, and the convention that `BNB_ROOT` is exported before any `tui/*.sh` file is sourced.

- [ ] **Step 1: Write `run.sh`**

```bash
#!/usr/bin/env bash
# Single entry point for bait-n-break. No logic of its own - sources libs
# and hands off to the top-level menu.

set -uo pipefail

BNB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BNB_ROOT

# shellcheck source=bait_n_break/shared/config.sh
source "${BNB_ROOT}/bait_n_break/shared/config.sh"
# shellcheck source=bait_n_break/shared/lib_ui.sh
source "${BNB_ROOT}/bait_n_break/shared/lib_ui.sh"
# shellcheck source=bait_n_break/shared/lib_state.sh
source "${BNB_ROOT}/bait_n_break/shared/lib_state.sh"

state_init

# shellcheck source=bait_n_break/tui/main_menu.sh
source "${BNB_ROOT}/bait_n_break/tui/main_menu.sh"

main_menu
```

- [ ] **Step 2: Write `bait_n_break/tui/main_menu.sh`**

```bash
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
```

- [ ] **Step 3: Write `bait_n_break/tui/attacker_console.sh`**

```bash
#!/usr/bin/env bash
# Phase 2 placeholder. The Attacker module is out of scope for Phase 1.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

attacker_console() {
    ui_msgbox "Attacker Console" "The Attacker module is not implemented yet (Phase 2). Coming soon."
}
```

- [ ] **Step 4: Syntax-check all three**

Run: `bash -n run.sh && bash -n bait_n_break/tui/main_menu.sh && bash -n bait_n_break/tui/attacker_console.sh`
Expected: no output, exit code 0.

- [ ] **Step 5: Manually verify menu navigation and clean exit**

```bash
chmod +x run.sh
echo 3 | ./run.sh
```
Expected: prints the "bait-n-break" plain menu with options 1-3, reads `3`, and exits with code 0 (no error, no hang). Also run `echo 2 | ./run.sh` and confirm it prints the Attacker Console placeholder message then exits after Enter.

- [ ] **Step 6: Commit**

```bash
git add run.sh bait_n_break/tui/main_menu.sh bait_n_break/tui/attacker_console.sh
git commit -m "Add entry point and top-level TUI menu"
```

---

## Task 4: Bait file generator

**Files:**
- Create: `bait_n_break/victim/lib_bait.sh`

**Interfaces:**
- Consumes: `state_manifest_add`, `state_manifest_clear` (Task 2); `BNB_BAIT_BACKUPS_DIR`, `BNB_BAIT_SECRETS_DIR`, `BNB_BAIT_DECEPTION_DIR` (Task 1).
- Produces (consumed by Task 10): `bait_generate_all()`.

- [ ] **Step 1: Write `bait_n_break/victim/lib_bait.sh`**

```bash
#!/usr/bin/env bash
# Generates dummy bait files (decoys) into .state/bait/* and records them
# in the bait manifest. All content is fake/dummy data - never real secrets.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

bait_generate_env() {
    local path="${BNB_BAIT_DECEPTION_DIR}/.env"
    cat > "$path" <<'EOF'
# WARNING: dummy lab credentials - not real, safe to leak
APP_ENV=production
DB_HOST=127.0.0.1
DB_USER=admin
DB_PASSWORD=SuperSecretPass123!
AWS_ACCESS_KEY_ID=AKIAFAKEEXAMPLE00000
AWS_SECRET_ACCESS_KEY=fAkE/exampleSecretKeyDoNotUse0000000000
STRIPE_API_KEY=stripe_test_FAKE000000000000000000
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_passwords() {
    local path="${BNB_BAIT_BACKUPS_DIR}/passwords.txt"
    cat > "$path" <<'EOF'
# dummy leaked credential list - lab bait, not real accounts
admin:admin123
root:toor
svc-backup:B4ckup!2024
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_shadow_dump() {
    local path="${BNB_BAIT_BACKUPS_DIR}/shadow.bak"
    cat > "$path" <<'EOF'
root:$6$fakesalt$FAKEHASHDONOTUSE0000000000000000000000000000000000000000000000000000000000:19000:0:99999:7:::
admin:$6$fakesalt$FAKEHASHDONOTUSE1111111111111111111111111111111111111111111111111111111111:19000:0:99999:7:::
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_db_dump() {
    local path="${BNB_BAIT_BACKUPS_DIR}/production_dump.sql"
    cat > "$path" <<'EOF'
-- dummy DB backup, lab bait
CREATE TABLE users (id INT, username TEXT, password TEXT);
INSERT INTO users VALUES (1, 'admin', 'admin123');
INSERT INTO users VALUES (2, 'jdoe', 'Password1!');
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_source_backup() {
    local path="${BNB_BAIT_BACKUPS_DIR}/website_backup.tar.gz"
    local tmpdir
    tmpdir="$(mktemp -d)" || return 1
    [ -n "$tmpdir" ] || return 1
    echo "<?php // dummy leaked source file ?>" > "${tmpdir}/config.php"
    tar -czf "$path" -C "$tmpdir" . || { rm -rf "$tmpdir"; return 1; }
    rm -rf "$tmpdir"
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_payroll() {
    local path="${BNB_BAIT_SECRETS_DIR}/payroll_2025.csv"
    cat > "$path" <<'EOF'
employee_id,name,salary,ssn
1001,Jane Doe,95000,000-00-0000
1002,John Smith,88000,000-00-0001
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_employee_db() {
    local path="${BNB_BAIT_SECRETS_DIR}/employee_records.db"
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$path" "CREATE TABLE employees (id INTEGER, name TEXT, dept TEXT); INSERT INTO employees VALUES (1,'Jane Doe','Finance');"
    else
        echo "SQLite placeholder - dummy employee records" > "$path"
    fi
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_all() {
    local rc=0
    state_manifest_clear
    bait_generate_env || rc=1
    bait_generate_passwords || rc=1
    bait_generate_shadow_dump || rc=1
    bait_generate_db_dump || rc=1
    bait_generate_source_backup || rc=1
    bait_generate_payroll || rc=1
    bait_generate_employee_db || rc=1
    return "$rc"
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/victim/lib_bait.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify generation and manifest, in a scratch state dir**

```bash
bash -c '
export BNB_ROOT="$(mktemp -d)"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/victim/lib_bait.sh
state_init
bait_generate_all
echo "manifest_lines=$(state_manifest_list | wc -l)"
test -s "${BNB_BAIT_DECEPTION_DIR}/.env" && echo "env_ok"
test -s "${BNB_BAIT_BACKUPS_DIR}/passwords.txt" && echo "passwords_ok"
test -s "${BNB_BAIT_SECRETS_DIR}/payroll_2025.csv" && echo "payroll_ok"
'
```
Expected: `manifest_lines=7`, `env_ok`, `passwords_ok`, `payroll_ok` all printed.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/victim/lib_bait.sh
git commit -m "Add bait file generator"
```

---

## Task 5: Vulnerable web app (Flask)

**Files:**
- Create: `bait_n_break/victim/webapp/app.py`
- Create: `bait_n_break/victim/webapp/requirements.txt`

**Interfaces:**
- Produces (consumed by Task 6's container packaging, Task 7's `webapp_up` verification, Task 9's `malware_c2_beacon_check`): an HTTP server on port 5000 (mapped to `TARGET_PORT` externally) exposing `/`, `/admin`, `/files/<area>/`, `/files/<area>/<filename>`, `/login`, `/ping`, `/upload`, `/uploads/<filename>`, `/shell/<filename>`, `/search`, `/comments`, `/c2/beacon`. Reads bait directories from `/bait/backups`, `/bait/secrets`, `/bait/deception` (the in-container mount points Task 6 wires up).

- [ ] **Step 1: Write `bait_n_break/victim/webapp/requirements.txt`**

```
flask==3.0.3
```

- [ ] **Step 2: Write `bait_n_break/victim/webapp/app.py`**

```python
#!/usr/bin/env python3
"""bait-n-break vulnerable web app.

Intentionally vulnerable Flask app for an isolated training lab. Every
vulnerability here is deliberate and documented - do not "fix" these, and
never deploy this outside the lab's isolated network.
"""
import os
import sqlite3
import subprocess

from flask import Flask, request, render_template_string, send_from_directory

app = Flask(__name__)
app.config["DEBUG"] = True  # intentional: exposed debug mode

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
DB_PATH = os.path.join(BASE_DIR, "app.db")

BAIT_AREAS = {
    "backups": "/bait/backups",
    "secrets": "/bait/secrets",
    "deception": "/bait/deception",
}

os.makedirs(UPLOAD_DIR, exist_ok=True)


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.execute(
        "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS comments (id INTEGER PRIMARY KEY, author TEXT, body TEXT)"
    )
    row = conn.execute("SELECT COUNT(*) AS n FROM users").fetchone()
    if row["n"] == 0:
        # intentionally weak, dummy lab credentials
        conn.execute(
            "INSERT INTO users (username, password) VALUES (?, ?)", ("admin", "admin123")
        )
    conn.commit()
    conn.close()


@app.route("/")
def index():
    return "<h1>bait-n-break demo corp portal</h1><p><a href='/login'>Login</a> | <a href='/search'>Search</a></p>"


# --- Reconnaissance: exposed /admin + directory listing, debug mode ---


@app.route("/admin")
def admin():
    links = "".join(f"<li><a href='/files/{area}/'>{area}</a></li>" for area in BAIT_AREAS)
    return f"<h1>Admin Panel</h1><p>debug={app.config['DEBUG']}</p><ul>{links}</ul>"


@app.route("/files/<area>/")
def list_files(area):
    directory = BAIT_AREAS.get(area)
    if directory is None or not os.path.isdir(directory):
        return "Not found", 404
    entries = os.listdir(directory)
    items = "".join(f"<li><a href='/files/{area}/{name}'>{name}</a></li>" for name in entries)
    return f"<h1>Index of {area}/</h1><ul>{items}</ul>"


@app.route("/files/<area>/<path:filename>")
def get_file(area, filename):
    directory = BAIT_AREAS.get(area)
    if directory is None:
        return "Not found", 404
    return send_from_directory(directory, filename)


# --- Initial Access: SQL injection auth bypass ---


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return """
        <form method="post">
          <input name="username" placeholder="username">
          <input name="password" placeholder="password" type="password">
          <button type="submit">Login</button>
        </form>
        """
    username = request.form.get("username", "")
    password = request.form.get("password", "")
    # Intentional SQL injection: raw string formatting, not parameterized.
    query = f"SELECT * FROM users WHERE username = '{username}' AND password = '{password}'"
    conn = get_db()
    try:
        row = conn.execute(query).fetchone()
    except sqlite3.Error as exc:
        return f"DB error: {exc}", 500
    finally:
        conn.close()
    if row:
        return f"<h1>Welcome, {row['username']}</h1>"
    return "<h1>Invalid credentials</h1>", 401


# --- Execution: command injection ---


@app.route("/ping")
def ping():
    host = request.args.get("host", "127.0.0.1")
    # Intentional command injection: unsanitized input passed to the shell.
    result = subprocess.run(f"ping -c 1 {host}", shell=True, capture_output=True, text=True)
    return f"<pre>{result.stdout}\n{result.stderr}</pre>"


# --- Execution / Persistence: unrestricted upload -> webshell ---


@app.route("/upload", methods=["GET", "POST"])
def upload():
    if request.method == "GET":
        return """
        <form method="post" enctype="multipart/form-data">
          <input type="file" name="file">
          <button type="submit">Upload</button>
        </form>
        """
    uploaded = request.files.get("file")
    if not uploaded or not uploaded.filename:
        return "No file", 400
    # Intentional: no extension/type validation.
    dest = os.path.join(UPLOAD_DIR, uploaded.filename)
    uploaded.save(dest)
    return f"Uploaded to /uploads/{uploaded.filename} - run it via /shell/{uploaded.filename}?cmd=..."


@app.route("/uploads/<path:filename>")
def get_upload(filename):
    return send_from_directory(UPLOAD_DIR, filename)


@app.route("/shell/<path:filename>")
def shell(filename):
    cmd = request.args.get("cmd", "")
    script_path = os.path.join(UPLOAD_DIR, filename)
    if not os.path.isfile(script_path):
        return "Not found", 404
    # Intentional webshell behavior: the uploaded file is executed with an
    # attacker-controlled argument, concatenated straight into the shell.
    result = subprocess.run(f"bash {script_path} {cmd}", shell=True, capture_output=True, text=True)
    return f"<pre>{result.stdout}\n{result.stderr}</pre>"


# --- Collection: reflected + stored XSS ---


@app.route("/search")
def search():
    q = request.args.get("q", "")
    # Intentional reflected XSS: query echoed back unescaped.
    return render_template_string(f"<h1>Results for: {q}</h1><p>No results found.</p>")


@app.route("/comments", methods=["GET", "POST"])
def comments():
    conn = get_db()
    if request.method == "POST":
        author = request.form.get("author", "anon")
        body = request.form.get("body", "")
        conn.execute("INSERT INTO comments (author, body) VALUES (?, ?)", (author, body))
        conn.commit()
    rows = conn.execute("SELECT author, body FROM comments").fetchall()
    conn.close()
    # Intentional stored XSS: comment body rendered unescaped.
    items = "".join(f"<li><b>{r['author']}</b>: {r['body']}</li>" for r in rows)
    form = """
    <form method="post">
      <input name="author" placeholder="name">
      <input name="body" placeholder="comment">
      <button type="submit">Post</button>
    </form>
    """
    return render_template_string(f"<h1>Comments</h1><ul>{items}</ul>{form}")


# --- Command & Control: mock beacon ---


@app.route("/c2/beacon", methods=["GET", "POST"])
def c2_beacon():
    return {"status": "ack", "task": "none"}


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
```

- [ ] **Step 3: Syntax-check**

Run: `python3 -c "import ast; ast.parse(open('bait_n_break/victim/webapp/app.py').read())"`
Expected: no output, exit code 0.

- [ ] **Step 4: Manually verify locally (if `flask` is installed; otherwise skip to Step 5 and rely on Task 6/7's container-based verification)**

```bash
cd bait_n_break/victim/webapp
pip install -r requirements.txt --quiet
python3 app.py &
sleep 1
curl -s http://127.0.0.1:5000/ | grep -q "demo corp portal" && echo "index_ok"
curl -s -X POST http://127.0.0.1:5000/login -d "username=' OR '1'='1'--&password=x" | grep -q "Welcome" && echo "sqli_ok"
curl -s "http://127.0.0.1:5000/c2/beacon" | grep -q '"status": "ack"' && echo "c2_ok"
kill %1
```
Expected: `index_ok`, `sqli_ok`, `c2_ok` all printed.

- [ ] **Step 5: Commit**

```bash
git add bait_n_break/victim/webapp/app.py bait_n_break/victim/webapp/requirements.txt
git commit -m "Add vulnerable web app"
```

---

## Task 6: Web app container packaging

**Files:**
- Create: `bait_n_break/victim/webapp/Dockerfile`
- Create: `bait_n_break/victim/webapp/docker-compose.yml`

**Interfaces:**
- Consumes: `app.py`, `requirements.txt` (Task 5); bait host paths `.state/bait/{backups,secrets,deception}` (Task 1's `BNB_BAIT_*` values, hardcoded here as relative paths since compose files can't read shell vars from `config.sh` directly).
- Produces (consumed by Task 7): a `webapp` service listening on `${TARGET_PORT:-8080}` externally / `5000` internally, plus `ssh-decoy` (port 2222, weak creds `admin`/`admin123`) and `ftp-decoy` (port 2121, weak creds `admin`/`admin123`) services satisfying the SSH/FTP weak-credential rows of the design spec's kill-chain table.

- [ ] **Step 1: Write `bait_n_break/victim/webapp/Dockerfile`**

```dockerfile
FROM python:3.11-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends iputils-ping \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 5000
CMD ["python3", "app.py"]
```

- [ ] **Step 2: Write `bait_n_break/victim/webapp/docker-compose.yml`**

```yaml
services:
  webapp:
    build: .
    ports:
      - "${TARGET_PORT:-8080}:5000"
    volumes:
      - ../../../.state/bait/backups:/bait/backups:ro
      - ../../../.state/bait/secrets:/bait/secrets:ro
      - ../../../.state/bait/deception:/bait/deception:ro
    restart: unless-stopped

  ssh-decoy:
    image: lscr.io/linuxserver/openssh-server:latest
    environment:
      - PUID=1000
      - PGID=1000
      - PASSWORD_ACCESS=true
      - USER_NAME=admin
      - USER_PASSWORD=admin123
    ports:
      - "2222:2222"
    restart: unless-stopped

  ftp-decoy:
    image: fauria/vsftpd
    environment:
      - FTP_USER=admin
      - FTP_PASS=admin123
      - PASV_ADDRESS=127.0.0.1
    ports:
      - "2121:21"
      - "21100-21110:21100-21110"
    restart: unless-stopped
```

- [ ] **Step 3: Validate the compose file**

Run: `docker compose -f bait_n_break/victim/webapp/docker-compose.yml config`
Expected: exit code 0, prints the resolved compose config with no errors. If Docker is unavailable in this environment, note that in the task report and validate the YAML with `python3 -c "import yaml; yaml.safe_load(open('bait_n_break/victim/webapp/docker-compose.yml'))"` instead.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/victim/webapp/Dockerfile bait_n_break/victim/webapp/docker-compose.yml
git commit -m "Add web app container packaging with SSH/FTP decoys"
```

---

## Task 7: Docker orchestration wrapper

**Files:**
- Create: `bait_n_break/victim/lib_webapp.sh`

**Interfaces:**
- Consumes: `BNB_WEBAPP_DIR` (Task 1); `docker-compose.yml` (Task 6).
- Produces (consumed by Task 9's `malware_c2_beacon_check` indirectly via the running service, and Task 10): `webapp_up()`, `webapp_down()`, `webapp_status()`, `webapp_ports()`.

- [ ] **Step 1: Write `bait_n_break/victim/lib_webapp.sh`**

```bash
#!/usr/bin/env bash
# docker compose wrapper for the vulnerable web app + decoy services.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

webapp_compose_file() {
    echo "${BNB_WEBAPP_DIR}/docker-compose.yml"
}

webapp_up() {
    ( cd "${BNB_WEBAPP_DIR}" && docker compose -f "$(webapp_compose_file)" up -d --build )
}

webapp_down() {
    ( cd "${BNB_WEBAPP_DIR}" && docker compose -f "$(webapp_compose_file)" down -v )
}

webapp_status() {
    ( cd "${BNB_WEBAPP_DIR}" && docker compose -f "$(webapp_compose_file)" ps )
}

webapp_ports() {
    ss -tulpn 2>/dev/null | grep -E ':(8080|2222|2121)\b' || echo "No matching ports found"
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/victim/lib_webapp.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify**

If Docker is available:
```bash
bash -c '
export BNB_ROOT="$(pwd)"
source bait_n_break/shared/config.sh
source bait_n_break/victim/lib_webapp.sh
webapp_up
sleep 3
curl -s http://127.0.0.1:8080/ | grep -q "demo corp portal" && echo "webapp_reachable"
webapp_status
webapp_down
'
```
Expected: `webapp_reachable` printed, `webapp_status` lists the three services, `webapp_down` exits 0.

If Docker is unavailable in this environment, run only Step 2 and record in the task report that container-dependent verification is deferred to an environment with Docker.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/victim/lib_webapp.sh
git commit -m "Add Docker orchestration wrapper for the victim web app"
```

---

## Task 8: Access & Incident Monitor

**Files:**
- Create: `bait_n_break/victim/lib_monitor.sh`

**Interfaces:**
- Consumes: `state_incident_append` (Task 2); `BNB_WEBAPP_DIR`, `BNB_BAIT_BACKUPS_DIR`, `BNB_BAIT_SECRETS_DIR`, `BNB_BAIT_DECEPTION_DIR`, `BNB_BAIT_ACCESS_LOG` (Task 1); the running `webapp` compose service (Task 7).
- Produces (consumed by Task 10): `monitor_start()`, `monitor_stop()`, `monitor_live_view()`.

- [ ] **Step 1: Write `bait_n_break/victim/lib_monitor.sh`**

```bash
#!/usr/bin/env bash
# Access & Incident Monitor: combines web app logs, auth.log, and a bait
# file access watcher into .state/incident_log.txt.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

monitor_watch_webapp() {
    ( cd "${BNB_WEBAPP_DIR}" && docker compose logs -f webapp ) 2>&1 | while IFS= read -r line; do
        state_incident_append "webapp" "$line"
    done &
}

monitor_watch_auth() {
    local authlog="/var/log/auth.log"
    if [ -f "$authlog" ]; then
        tail -F "$authlog" 2>/dev/null | while IFS= read -r line; do
            state_incident_append "auth" "$line"
        done &
    fi
}

monitor_watch_bait() {
    local paths=("${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}")
    if command -v inotifywait >/dev/null 2>&1; then
        inotifywait -m -r -e access,open "${paths[@]}" 2>/dev/null | while IFS= read -r line; do
            state_incident_append "bait-access" "$line"
        done &
    else
        (
            while true; do
                for p in "${paths[@]}"; do
                    [ -d "$p" ] || continue
                    state_bait_marker_files_since "$p" | while IFS= read -r line; do
                        state_incident_append "bait-access" "$line"
                    done
                done
                state_bait_marker_touch
                sleep 5
            done
        ) &
        # Track the polling subshell's PID (in this same shell session) so
        # monitor_stop can kill it - pkill -f can't match it reliably since
        # it has no distinctive command-line string.
        BNB_MONITOR_BAIT_POLL_PID=$!
    fi
}

monitor_start() {
    monitor_watch_webapp
    monitor_watch_auth
    monitor_watch_bait
}

monitor_stop() {
    pkill -f "docker compose logs -f webapp" 2>/dev/null
    pkill -f "tail -F /var/log/auth.log" 2>/dev/null
    pkill -f "inotifywait -m -r" 2>/dev/null
    if [ -n "${BNB_MONITOR_BAIT_POLL_PID:-}" ]; then
        kill "${BNB_MONITOR_BAIT_POLL_PID}" 2>/dev/null
        unset BNB_MONITOR_BAIT_POLL_PID
    fi
    return 0
}

monitor_live_view() {
    tail -f "${BNB_INCIDENT_LOG}"
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/victim/lib_monitor.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify the incident log plumbing (independent of Docker)**

```bash
bash -c '
export BNB_ROOT="$(mktemp -d)"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/victim/lib_monitor.sh
state_init
state_incident_append "test" "manual entry"
monitor_live_view &
sleep 1
kill %1 2>/dev/null
state_incident_tail 5
'
```
Expected: the tail output contains a line with `[test] manual entry`.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/victim/lib_monitor.sh
git commit -m "Add access and incident monitor"
```

---

## Task 9: Malware/ransomware/C2 simulation

**Files:**
- Create: `bait_n_break/victim/lib_malware_sim.sh`

**Interfaces:**
- Consumes: `state_manifest_add`, `state_incident_append` (Task 2); `BNB_BAIT_DECEPTION_DIR`, `TARGET_PORT` (Task 1); the running `webapp` service's `/c2/beacon` route (Task 5/7).
- Produces (consumed by Task 10): `malware_drop_eicar()`, `malware_ransomware_demo_run()`, `malware_ransomware_demo_restore()`, `malware_c2_beacon_check()`.

- [ ] **Step 1: Write `bait_n_break/victim/lib_malware_sim.sh`**

```bash
#!/usr/bin/env bash
# Harmless malware simulation: EICAR drop, sandboxed ransomware demo, C2
# beacon check. All effects are inert and confined to .state/bait/deception.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

BNB_EICAR_STRING='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
BNB_RANSOMWARE_TARGET_DIR="${BNB_BAIT_DECEPTION_DIR}/ransomware_target"
BNB_RANSOMWARE_KEY="lab-demo-key-not-secret"

malware_drop_eicar() {
    local path="${BNB_BAIT_DECEPTION_DIR}/eicar_test.txt"
    printf '%s' "${BNB_EICAR_STRING}" > "$path"
    state_manifest_add "$path"
    state_incident_append "malware-sim" "EICAR test file dropped at $path"
}

malware_ransomware_demo_setup() {
    mkdir -p "${BNB_RANSOMWARE_TARGET_DIR}"
    printf 'dummy sensitive file %s\n' "$(date)" > "${BNB_RANSOMWARE_TARGET_DIR}/document_$$.txt"
}

malware_ransomware_demo_run() {
    malware_ransomware_demo_setup
    local f
    for f in "${BNB_RANSOMWARE_TARGET_DIR}"/*; do
        [ -f "$f" ] || continue
        [[ "$f" == *.locked ]] && continue
        openssl enc -aes-256-cbc -pbkdf2 -k "${BNB_RANSOMWARE_KEY}" -in "$f" -out "${f}.locked" 2>/dev/null && rm -f "$f"
    done
    cat > "${BNB_RANSOMWARE_TARGET_DIR}/README_RESTORE.txt" <<'EOF'
This is a harmless training-lab demo. Files in this directory were
encrypted with a fixed, known key for educational purposes only.
EOF
    state_incident_append "malware-sim" "Ransomware demo run against ${BNB_RANSOMWARE_TARGET_DIR}"
}

malware_ransomware_demo_restore() {
    local f
    for f in "${BNB_RANSOMWARE_TARGET_DIR}"/*.locked; do
        [ -f "$f" ] || continue
        openssl enc -d -aes-256-cbc -pbkdf2 -k "${BNB_RANSOMWARE_KEY}" -in "$f" -out "${f%.locked}" 2>/dev/null && rm -f "$f"
    done
}

malware_c2_beacon_check() {
    local url="http://localhost:${TARGET_PORT:-8080}/c2/beacon"
    if curl -s -o /dev/null -w '%{http_code}' "$url" | grep -q '200'; then
        state_incident_append "malware-sim" "C2 beacon check ok: $url"
        return 0
    fi
    state_incident_append "malware-sim" "C2 beacon check failed: $url"
    return 1
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/victim/lib_malware_sim.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify EICAR drop and ransomware demo scope**

```bash
bash -c '
export BNB_ROOT="$(mktemp -d)"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/victim/lib_malware_sim.sh
state_init
malware_drop_eicar
grep -q "EICAR-STANDARD-ANTIVIRUS-TEST-FILE" "${BNB_BAIT_DECEPTION_DIR}/eicar_test.txt" && echo "eicar_ok"

malware_ransomware_demo_run
ls "${BNB_RANSOMWARE_TARGET_DIR}"/*.locked >/dev/null 2>&1 && echo "ransomware_locked_ok"
# confirm nothing outside the target dir changed
find "${BNB_BAIT_DECEPTION_DIR}" -maxdepth 1 -newer "${BNB_BAIT_DECEPTION_DIR}/eicar_test.txt" ! -path "${BNB_RANSOMWARE_TARGET_DIR}*" | grep -v "^${BNB_BAIT_DECEPTION_DIR}$" && echo "SCOPE_VIOLATION" || echo "scope_ok"

malware_ransomware_demo_restore
ls "${BNB_RANSOMWARE_TARGET_DIR}"/*.locked >/dev/null 2>&1 || echo "restore_ok"
'
```
Expected: `eicar_ok`, `ransomware_locked_ok`, `scope_ok` (not `SCOPE_VIOLATION`), `restore_ok`.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/victim/lib_malware_sim.sh
git commit -m "Add malware/ransomware/C2 simulation"
```

---

## Task 10: Victim dashboard (wires the module together)

**Files:**
- Create: `bait_n_break/tui/victim_dashboard.sh`

**Interfaces:**
- Consumes: `ui_menu`, `ui_msgbox`, `ui_error` (Task 1); `state_get_status`, `state_set_status`, `state_manifest_list`, `state_incident_tail`, `state_reset` (Task 2); `bait_generate_all` (Task 4); `webapp_up`, `webapp_down`, `webapp_status`, `webapp_ports` (Task 7); `monitor_start`, `monitor_stop` (Task 8); `malware_drop_eicar`, `malware_ransomware_demo_run`, `malware_ransomware_demo_restore`, `malware_c2_beacon_check` (Task 9).
- Produces (consumed by Task 3's `main_menu.sh`, already written): `victim_dashboard()`.

- [ ] **Step 1: Write `bait_n_break/tui/victim_dashboard.sh`**

```bash
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
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/tui/victim_dashboard.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify the full menu flow end-to-end**

```bash
echo 1 | ./run.sh   # role menu -> Victim
```
Then, with the Victim submenu now reachable, verify the inventory path without Docker:
```bash
bash -c '
export BNB_ROOT="$(pwd)"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
state_init
source bait_n_break/tui/victim_dashboard.sh
source bait_n_break/victim/lib_bait.sh
bait_generate_all
victim_inventory
' 
```
Expected: the printed inventory msgbox text lists 7 file paths under `.state/bait/...`.

Then run the full interactive flow end to end selecting Victim -> Deploy (requires Docker) -> Service Status Panel -> Honey-Asset Inventory -> Malware/Ransomware Simulation -> Drop EICAR -> Teardown -> Back -> Exit, confirming each screen shows the expected content and no script errors out. Record in the task report whether Docker was available for the Deploy step.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/tui/victim_dashboard.sh
git commit -m "Add victim dashboard wiring the victim module together"
```

---

## Task 11: Setup script

**Files:**
- Create: `setup.sh`

**Interfaces:**
- Consumes: nothing from other tasks (standalone installer).
- Produces: an environment with `docker`, `whiptail`, `inotify-tools`, `iproute2` installed, sufficient for `run.sh` and the victim module to function. Does not deploy services itself.

- [ ] **Step 1: Write `setup.sh`**

```bash
#!/usr/bin/env bash
# Idempotent dependency installer. Detects OS, installs only what's missing.
# Does not deploy services - that is the TUI's "Deploy" action.

set -uo pipefail

log() { echo "[setup] $*"; }

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

ensure_pkg() {
    local pkg="$1"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        log "$pkg already installed"
    else
        log "installing $pkg"
        sudo apt-get install -y "$pkg"
    fi
}

main() {
    local os
    os="$(detect_os)"
    case "$os" in
        ubuntu|kali|debian)
            sudo apt-get update
            ensure_pkg whiptail
            ensure_pkg inotify-tools
            ensure_pkg iproute2
            if ! command -v docker >/dev/null 2>&1; then
                log "installing docker.io"
                sudo apt-get install -y docker.io docker-compose-plugin
                sudo systemctl enable --now docker || true
            else
                log "docker already installed"
            fi
            ;;
        *)
            log "Unsupported or undetected OS ($os). Please install docker, whiptail, inotify-tools, iproute2 manually."
            ;;
    esac
    log "Setup complete. Run ./run.sh to start bait-n-break."
}

main "$@"
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n setup.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify OS detection logic in isolation**

```bash
bash -c '
source setup.sh
detect_os
'
```
Expected: prints the current OS `ID` from `/etc/os-release` (e.g. `ubuntu`) or `unknown` if the file is absent. Full `main` execution (package installation) is environment-dependent and requires `sudo` + apt — note in the task report whether it was run for real or only syntax/function-verified.

- [ ] **Step 4: Commit**

```bash
git add setup.sh
git commit -m "Add idempotent setup script"
```
