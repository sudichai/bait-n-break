# bait-n-break — Phase 2 Design: Attacker (Kali) Module

Date: 2026-07-14
Status: Approved (pending written-spec review)

## Goal

Build the Attacker (Kali) module for `bait-n-break`: menu-driven exploit scripts that target the Phase 1 Victim node's vulnerabilities, threaded through a single `TARGET_IP`/`TARGET_PORT`, with a "Run All Scenarios" kill-chain runner and a results summary. This replaces the Phase 1 placeholder in `bait_n_break/tui/attacker_console.sh`.

Out of scope: any change to Phase 1's victim TUI/dashboard flow, any new victim-side vulnerability class beyond what Phase 1 already built (Phase 2 only adds the one endpoint described below to make an existing Phase 1 *capability* — the ransomware demo — remotely reachable, it does not add a new vulnerability).

## Decisions carried in from brainstorming

- **Attack tooling**: wrap standard Kali tools (`hydra`, `sqlmap`, `nmap`) where available, with a hand-rolled bash+curl fallback so the attacker role still works on stock Ubuntu, per CLAUDE.md's "must work out of the box on stock Ubuntu and Kali" constraint. `setup.sh` best-effort installs these tools (same idempotent pattern as Phase 1), but their absence must not break the attacker flow.
- **Output/UX**: every attack scenario exits the whiptail/dialog TUI chrome and runs directly in the raw terminal so its output streams live and unmodified (curl responses, hydra progress, etc.), then waits for Enter before returning to the menu. This differs from Phase 1's `victim_monitor_view()`, which is a `ui_msgbox` snapshot — that pattern doesn't fit here because attack output is meant to be watched as it happens, not summarized after the fact.
- **Run All Scenarios pacing**: runs every kill-chain phase back-to-back with no pause/confirmation between phases, then shows one combined results summary at the end.
- **Results storage**: persisted to a new `.state/attack_results.txt`, owned by a new `bait_n_break/attacker/lib_results.sh` (sole reader/writer, mirroring `shared/lib_state.sh`'s pattern), so results survive across individual scenario runs and can be reviewed via a "Results Summary" menu item independent of Run All.
- **Crawler behavior**: wordlist-based path guessing (`bait_n_break/attacker/wordlists/common_paths.txt`) rather than hardcoding the exact bait paths from the Phase 1 design table — the wordlist mixes the real bait paths among plausible decoy paths so recon has to actually search, matching how the crawler is described in CLAUDE.md ("crawler for leaked ... files").
- **Ransomware-demo remote triggering (architecture fix)**: Phase 1 built the ransomware-demo as a host-only bash function operating through a `:ro` (read-only) bind mount into the webapp container, so it is *not* actually reachable through the webshell as the original Phase 1 design spec's prose implied. Rather than leave that gap, Phase 2 closes it by: (a) changing the `deception` bind mount in `docker-compose.yml` to read-write, and (b) adding a new `POST /admin/ransomware-demo` route to `app.py` that reimplements the same fixed-key encryption *in Python, inside the container*, scoped strictly to `/bait/deception/ransomware_target/`. This does not shell out to the host and does not mount the Docker socket — the "never touch anything outside `ransomware_target/`" safety constraint is preserved, just enforced container-side instead of host-side.

## 1. Architecture & directory structure

```
bait_n_break/
  tui/
    attacker_console.sh       # target IP/port input, scenario menu, Run All, results summary
  attacker/
    lib_target.sh             # prompts for/validates TARGET_IP + TARGET_PORT, persists into .state
    lib_recon.sh               # port/service scan + banner grab (SSH/FTP/HTTP)
    lib_bruteforce.sh          # SSH/FTP/HTTP-basic weak-credential brute force
    lib_web_exploit.sh         # SQLi auth bypass, command injection, webshell deploy, XSS PoC
    lib_crawler.sh             # wordlist-based leaked-file discovery
    lib_malware_c2.sh          # C2 beacon check, remote ransomware-demo trigger
    lib_results.sh             # sole reader/writer of .state/attack_results.txt
    wordlists/
      common_paths.txt         # candidate leaked-file paths (real bait paths mixed with decoys)
  shared/
    config.sh                  # TARGET_IP/TARGET_PORT already defined (Phase 1); Phase 2 is the first
                                # consumer, plus a new BNB_ATTACK_RESULTS state path
  victim/
    webapp/
      app.py                   # +1 new route: POST /admin/ransomware-demo
      docker-compose.yml       # deception mount changes from :ro to read-write
```

Principle carried over from Phase 1: library files under `attacker/` are pure function collections, sourced not executed, and must not call `set -uo pipefail` (only `run.sh`/`setup.sh` do that — this was a real bug class caught repeatedly during Phase 1 review and must not recur here).

## 2. TUI flow & target configuration

- `attacker_console.sh` replaces the Phase 1 placeholder. On first entry it sources `lib_target.sh`, which prompts for `TARGET_IP` (required) and `TARGET_PORT` (defaults to 8080, matching Phase 1's `docker-compose.yml` default) if not already set for this session, and stores them via `state_set_status`-style persistence so re-entering the Attacker Console doesn't re-prompt every time.
- Menu (via `lib_ui.sh`'s existing `ui_menu`): `[1] Set/Change Target` `[2] Recon` `[3] Brute-force` `[4] Web Exploitation` `[5] Crawler (bait exfiltration)` `[6] Malware/C2` `[7] Run All Scenarios` `[8] Results Summary` `[9] Back`.
- Selecting any of 2-7 exits the whiptail/dialog screen, runs the corresponding `attacker/lib_*.sh` function directly against the raw terminal (live output), waits for `read -r -p "Press Enter to continue..."`, then re-enters the menu loop.
- `[8] Results Summary` shows the accumulated `.state/attack_results.txt` contents via `ui_msgbox`, one line per completed scenario: `[SCENARIO] [SUCCESS|FAILED|VULNERABLE] [OPSEC:loud|quiet] detail`.

## 3. Attack scenario modules (kill-chain mapped, matching Phase 1's table)

| Module | Function(s) | Kill-chain phase | Tool (primary → fallback) |
|---|---|---|---|
| `lib_recon.sh` | `recon_scan()` | Reconnaissance | `nmap -sV` → `/dev/tcp` port probe + `curl`/banner grab |
| `lib_bruteforce.sh` | `bruteforce_ssh()`, `bruteforce_ftp()`, `bruteforce_http()` | Initial Access | `hydra` → hand-rolled loop over a small built-in weak-credential list via `sshpass`/`curl`/`ftp` |
| `lib_web_exploit.sh` | `exploit_sqli()` | Initial Access | `sqlmap --batch` → hand-rolled `' OR '1'='1'--` payload against `/login` |
| `lib_web_exploit.sh` | `exploit_command_injection()` | Execution | hand-rolled only (no standard tool fits this narrow case) — `curl` against `/ping?host=` |
| `lib_web_exploit.sh` | `exploit_webshell_deploy()` | Execution / Persistence | hand-rolled only — `curl` multipart upload to `/upload`, then `/shell/<file>?cmd=` |
| `lib_web_exploit.sh` | `exploit_xss_poc()` | Collection | hand-rolled only — `curl` against `/search` (reflected) and `/comments` (stored) |
| `lib_crawler.sh` | `crawl_leaked_files()` | Reconnaissance / Collection | hand-rolled only — iterates `wordlists/common_paths.txt` against `/files/<area>/<name>` |
| `lib_malware_c2.sh` | `c2_beacon_check()` | Command & Control | hand-rolled only — `curl` against `/c2/beacon` |
| `lib_malware_c2.sh` | `ransomware_trigger()` | Impact | hand-rolled only — `curl -X POST` against the new `/admin/ransomware-demo` |

Every function follows the same contract: run its attack, print live output to the terminal, determine `[SUCCESS]`/`[FAILED]`/`[VULNERABLE]` from the actual response (not assumed), tag an OPSEC risk (`loud` if it would show up prominently in Phase 1's Access & Incident Monitor — e.g. brute-force floods auth logs — `quiet` if it wouldn't — e.g. a single crafted SQLi request), and append one line to `.state/attack_results.txt` via `lib_results.sh`.

## 4. Victim-side changes (Phase 1 files touched by Phase 2)

- `bait_n_break/victim/webapp/docker-compose.yml`: `deception` volume mount changes from `../../../.state/bait/deception:/bait/deception:ro` to the same path without `:ro` (read-write). `backups` and `secrets` mounts stay read-only — only the ransomware-demo target needs write access.
- `bait_n_break/victim/webapp/app.py`: new route:
  ```python
  @app.route("/admin/ransomware-demo", methods=["POST"])
  def admin_ransomware_demo():
      # Intentional: reachable post-exploitation action, reimplements the
      # host-side ransomware-demo (fixed-key encryption) container-side so
      # it's actually triggerable through the webshell/RCE an attacker has
      # already achieved. Strictly scoped to ransomware_target/ - never
      # touches anything else, matching the host-side version's constraint.
      target_dir = "/bait/deception/ransomware_target"
      os.makedirs(target_dir, exist_ok=True)
      ...
  ```
  (Full implementation detail deferred to the Phase 2 implementation plan — the constraint that matters for this spec is: Python-only, no `subprocess`/shell-out to the host, no Docker socket, confined to `ransomware_target/`.)

## 5. Run All Scenarios

`attacker_run_all()`: calls, in order, `recon_scan` → `bruteforce_ssh`/`bruteforce_ftp`/`bruteforce_http` → `exploit_sqli`/`exploit_command_injection`/`exploit_webshell_deploy`/`exploit_xss_poc` → `crawl_leaked_files` → `c2_beacon_check`/`ransomware_trigger`, with no pauses between them, all writing to the same `.state/attack_results.txt`, then displays the combined summary automatically at the end (equivalent to auto-selecting `[8]`).

## 6. Results & state

New file `bait_n_break/attacker/lib_results.sh`, sole reader/writer of `.state/attack_results.txt`:
- `results_init()` — creates the file if missing (called once, like `state_init()`).
- `results_record(scenario, verdict, opsec, detail)` — appends one formatted line.
- `results_summary()` — returns the full file contents for display.
- `results_clear()` — clears the file (used when a fresh Run All starts, so summaries don't mix across sessions).

`shared/config.sh` gains one new path constant, `BNB_ATTACK_RESULTS="${BNB_STATE_DIR}/attack_results.txt"`, following the exact same naming/placement convention as Phase 1's other `.state/*` paths.

## 7. setup.sh

Adds best-effort idempotent installs (same `dpkg -s` check-before-install pattern as Phase 1) for `hydra`, `sqlmap`, `nmap` alongside the existing `whiptail`/`inotify-tools`/`iproute2`/docker installs. Their absence is never fatal — every `attacker/lib_*.sh` function checks `command -v` before deciding which code path to take, exactly like Phase 1's `lib_bait.sh` already does for `sqlite3`.

## Open items for the implementation plan (not decided here)

- Exact wordlist contents for `common_paths.txt`.
- Exact hand-rolled fallback credential list for brute-force (must stay dummy/inert, matching Phase 1's bait credentials so the "attack" is realistic against this specific lab).
- Exact Python implementation of `/admin/ransomware-demo`'s encryption (mirroring the host-side `openssl enc -aes-256-cbc -pbkdf2` scheme via Python's `cryptography`/`hashlib`+`Crypto`, or shelling out to the container's own `openssl` binary via `subprocess` scoped only to files already inside `ransomware_target/` — a plan-time implementation choice, not an architecture choice).
- Whether `lib_target.sh`'s persisted `TARGET_IP`/`TARGET_PORT` lives in `.state/` (via `lib_state.sh`) or a dedicated attacker-only state file — should follow the same "sole reader/writer" convention as everything else; exact file TBD at plan time.
