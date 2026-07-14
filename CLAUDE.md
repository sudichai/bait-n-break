# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Pre-implementation. This repository currently contains only this file (the prior spec notes have been folded in below). There is no code, build system, or test suite yet — do not assume any tooling exists until it has actually been added.

## What this project is

`bait-n-break` is a self-contained cyber security **training lab**, not a tool for attacking real systems. It ships two roles that run from the same codebase:

- **Victim / Target node** (Ubuntu): deploys intentionally vulnerable services and decoy ("bait") files so an attacker has something realistic to find and exploit.
- **Attacker node** (Kali): runs menu-driven scripts that exploit the vulnerabilities the victim node exposes.

Everything is meant to run in an isolated lab environment for education/testing purposes only. When adding or modifying attack/exploit scripts, keep them scoped to the lab's own victim node — do not generalize them into tools aimed at arbitrary/real targets.

## Hard constraints

- **Bash/shell only.** The TUI and orchestration must be pure `.sh` — no Python, Node, or other runtime that needs `pip`/`npm`/venvs for the shell/menu layer itself. (The vulnerable web app deployed *by* the victim module is an exception — it is explicitly meant to be a Python (Flask/FastAPI) or Docker-based target service, since it needs to be exploitable, not the framework driving the lab.)
- **Single entry point.** The whole project launches via one script from the repo root: `./run.sh` (or `./main.sh`). That script presents the TUI and lets the user pick a role — `[1] Target (Victim Machine)` or `[2] Attacker (Kali Machine)`.
- **TUI**: use `whiptail` or `dialog`; if neither is present, fall back to a plain `select`/`read` terminal menu. Must work out of the box on stock Ubuntu and Kali.
- **No forced setup step**: a `setup.sh` bootstrap script should exist to install any needed system packages, but running the lab should still work via the single entry point after that.

## Intended module layout

```
bait_n_break/
  tui/       # Main menu, Victim Dashboard, Attacker Control Console
  victim/    # Bait file generator, vulnerable web server, logging/monitoring
  attacker/  # Exploitation scripts, attack scenarios, payload delivery
  shared/    # Configs, helper functions used by both roles
```

## Victim module scope

- **Bait files**: decoy secrets/data dropped into predictable paths (e.g. `/var/www/html/backups/`, `/home/ubuntu/secrets/`, `/opt/deception/`) — fake `.env`/API keys, payroll/budget/employee-record files, fake password/shadow dumps, fake source/DB backups. These must be dummy data, never real credentials.
- **Vulnerable web app**: exposes, on purpose, a webshell-capable upload endpoint, an exposed `/admin` + directory listing + debug mode, weak SSH/FTP/web-admin credentials, a command-injection endpoint, SQL injection (auth bypass + data extraction), stored/reflected XSS, and harmless simulated malware triggers (ransomware-style file-encryption demo, botnet C2 beacon checks, EICAR-signature trojan/virus drops).
- **Victim TUI view** needs: a service status panel (what's running, what ports are open), a bait-file inventory, and an access/incident monitor that tails web/SSH/filesystem logs to surface attacker activity in real time.

## Attacker module scope

- Menu-driven scripts targeting a user-supplied IP: recon/brute-force (SSH/FTP/HTTP), web exploitation (SQLi, command injection, webshell deploy, XSS), a crawler for leaked `.env`/password/backup files, and malware/ransomware/C2 simulation.
- Target IP/port is entered once in the Attacker TUI and threaded through `shared/config.sh` (`TARGET_IP`) so every attack script reads the same value instead of prompting separately.
- A "Run All Scenarios" option chains recon → vuln scan → exploitation → bait exfiltration → post-exploitation.
- Attacker TUI needs target IP/port input, live streaming output of what's running, and a results summary showing `[SUCCESS]` / `[FAILED]` / `[VULNERABLE]` per module.

## Attacker module design methodology

Use the `red-team` skill's structure when designing/ordering attacker scenarios (the skill's own `--authorized`/RoE tooling doesn't apply here since this is a self-owned isolated lab, not a third-party engagement — only the methodology is reused):

- **Kill-chain phase ordering**: "Run All Scenarios" follows Recon → Initial Access → Execution → Credential Access → Lateral Movement → Collection → Exfiltration → Impact, not an arbitrary order.
- **Crown jewels**: the victim module's bait files (payroll, `.env`, backups, etc.) are the crown jewels — attacker success is measured by which bait files were reached, not just how many vulnerabilities fired.
- **Technique scoring / OPSEC risk**: each scenario's result summary should note detection risk (does it show up loudly in the victim's Access & Incident Monitor, or quietly) alongside `[SUCCESS]`/`[FAILED]`/`[VULNERABLE]`.

## Development process

- Use the `superpowers` skill set throughout development: `brainstorming` before new features/modules (already used for the overall design), `systematic-debugging` for any bug/unexpected behavior instead of guessing at fixes, `test-driven-development` when writing new scripts, and `verification-before-completion` before claiming anything is done.
- Every module/feature must go through an explicit QA/debug pass after implementation (actually run the TUI flow and the affected scripts end-to-end, not just read the code) before it's considered finished — this applies to both the victim module and attacker module.

## Working conventions

- Keep victim-side vulnerable endpoints and attacker-side exploit scripts in sync deliberately — an exploit script should target a specific, documented endpoint/vuln in the victim module, not be written speculatively ahead of it.
- Everything (bait content, "leaked" credentials, malware simulation payloads) must be inert/dummy — safe to run, safe to leave on disk, no real-world capability.
- Write all code comments in English, even though project discussion happens in Thai.
