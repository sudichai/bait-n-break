# Attacker Module Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.
> Steps use checkbox (`- [ ]`) syntax for tracking.
> **Reference:** Full design spec at `docs/superpowers/specs/2026-07-17-attacker-redesign.md`

**Goal:** Rewrite attacker module to generate realistic attack traffic indistinguishable from real security tools (nmap, sqlmap, hydra, etc.) with payload encoding variants, WAF bypass tracking, and MITRE ATT&CK kill-chain phase structure.

**Architecture:** Three new core libraries (`lib_engine.sh`, `lib_traffic.sh`, `lib_payloads.sh`) provide typewriter rendering, HTTP request factory with real tool fingerprints, and payload variant libraries. Eight exploit libraries rewritten to use these cores. Attacker console remains whiptail-based but adds status icons and a results summary view.

**Tech Stack:** Bash 4+, curl, whiptail/dialog. No Python/Node for shell layer.

---

### Phase 1: Core Libraries (Parallel — 3 tasks)

> These 3 tasks have NO dependencies on each other. Run ALL THREE in parallel via subagents.

#### Task 1: lib_engine.sh — Core Rendering Engine

**File:** Create `bait_n_break/attacker/lib_engine.sh`

**What to build:**
- `twi()` — typewriter effect (print text char-by-char)
- `fake_shell()` — prints `root@kali:~# <cmd>` in green/blue, runs cmd via eval, captures output
- `phase_banner()` — prints kill-chain phase banner (blue bg) with MITRE tag
- `waf_tracker()` — takes HTTP code + payload desc, prints colored [BYPASSED]/[BLOCKED]/[ERROR], increments global counters `BNB_ENGINE_WAF_BLOCKED`, `BNB_ENGINE_WAF_BYPASSED`, `BNB_ENGINE_PAYLOAD_TOTAL`
- `_engine_reset_waf()` — resets WAF counters
- `bar()` — ASCII progress bar `[#####-----] 50%`
- `tool_sig()` — returns User-Agent string for: nmap_sV, sqlmap, hydra_ssh, gobuster, nikto, metasploit
- `ops()` — prints colored OPSEC risk level (quiet=green, medium=yellow, loud=red)
- `mission_brief()` — prints mission header with title, target, technique, tactic, OPSEC
- `debrief_card()` — prints completion summary with WAF stats, resets counters

**Verification:** `bash -n bait_n_break/attacker/lib_engine.sh` exits 0

#### Task 2: lib_traffic.sh — HTTP Traffic Factory

**File:** Create `bait_n_break/attacker/lib_traffic.sh`

**What to build:**
- `traffic_curl()` — makes HTTP request with method, url, data, extra_headers, tool (uses tool_sig for User-Agent). Returns body + HTTP code (last line via -w '\n%{http_code}')
- `traffic_extract_code()` — extracts last line (HTTP code) from response
- `traffic_extract_body()` — extracts everything except last line (response body)
- `traffic_json_post()` — POST with Content-Type: application/json + realistic Accept/X-Requested-With headers
- `traffic_form_post()` — POST with Content-Type: application/x-www-form-urlencoded
- `traffic_nmap_scan()` — runs nmap -sV -sC if available, else prints "[!] nmap not installed"

**Verification:** `bash -n bait_n_break/attacker/lib_traffic.sh` exits 0

#### Task 3: lib_payloads.sh — Payload Variant Library

**File:** Create `bait_n_break/attacker/lib_payloads.sh`

**What to build:**
- `payloads_sqli_auth_bypass` — 15 SQLi auth bypass payloads (plain, URL-encoded, hex, comment-obfuscated)
- `payloads_cmdi_ping` — 15 command injection payloads (semicolon, pipe, backtick, newline, URL-encoded)
- `payloads_shellshock_6271` — 4 Shellshock User-Agent payloads
- `payloads_apache_41773` — 3 Apache path traversal payloads (dot-dot-slash, double-encode, alt path)
- `payloads_log4shell_jndi` — 4 JNDI injection payloads (ldap, ldaps, dns, rmi)
- `payloads_lfi_traversal` — 7 LFI traversal payloads
- `payloads_bruteforce_creds` — 15 credential pairs (admin:admin, root:toor, etc.)
- `payloads_crawler_paths` — 50+ common web paths (.env, /backup/, /admin/, /wp-admin/, /config/, /db/, /passwords/, etc.)

**Verification:** `bash -n bait_n_break/attacker/lib_payloads.sh` exits 0

---

### Phase 2: Results + Console (Parallel — 2 tasks after Phase 1)

#### Task 4: lib_results.sh — Enhanced Results Tracker

**File:** Modify `bait_n_break/attacker/lib_results.sh` (full rewrite)

**What to build:**
- `results_init()` — creates results file with `sep=|` header
- `results_record()` — writes pipe-delimited line: `ts|module|status|ops|tactic|waf_stats|detail`
- `results_record_simple()` — variant without tactic/waf fields
- `results_summary()` — cats entire results file
- `results_clear()` — resets file
- `results_count()` — counts by field (e.g., count VULNERABLE entries)
- `results_waf_stats()` — sums all blocked/bypassed from WAF field, returns "X blocked, Y bypassed"
- `results_status_for()` — returns status for a given module name (last entry)
- `results_is_vulnerable()` — checks if module has VULNERABLE or SUCCESS status
- `results_short_summary()` — prints formatted table of all 17 vectors with colored status + WAF stats
- `results_cve_summary()` — prints CVE-specific summary

**Verification:** `bash -n bait_n_break/attacker/lib_results.sh` exits 0

#### Task 5: attacker_console.sh — Whiptail Menu with Status

**File:** Modify `bait_n_break/tui/attacker_console.sh` (full rewrite)

**What to build:**
- Sources: lib_target, lib_engine, lib_traffic, lib_payloads, then all exploit libs, results
- `crawl_all()`, `malware_c2_all()`, `post_exploit_all()` wrapper functions
- `_build_menu()` — builds whiptail menu array, prepends `[+] ` / `[-] ` / `[ ] ` based on results_status_for() per vector
- `_do()` — clear screen, run function, show "Press Enter" prompt
- whiptail menu loop with 22 options (17 vectors + Run All + Run CVEs + Results + Target + Quit)
- Menu title shows `"Target: IP:PORT | WAF stats: X blocked, Y bypassed"`
- `R` key shows `results_short_summary()` table
- `_exec_one()` — dispatches single vector
- `_exec_all()` — full kill-chain with phase_banner() per phase
- `_exec_cves()` — runs all 8 CVEs with [CVE X/8] labels

**Verification:** `bash -n bait_n_break/tui/attacker_console.sh` exits 0

---

### Phase 3: Exploit Libraries (Parallel — 5 tasks after Phase 1+2)

> All 5 tasks can run in parallel. Each follows the same pattern: mission_brief → phase_banner → fake_shell → payload iteration with bar()+waf_tracker() → debrief_card. Reference spec section 7 for mapping, section 8 for execution flow.

#### Task 6: lib_web_exploit.sh — Web Exploitation (SQLi, CMDi, Webshell, XSS)

**File:** Modify `bait_n_break/attacker/lib_web_exploit.sh` (full rewrite, ~200 lines)

**Functions to rewrite (each with engine integration):**
1. `exploit_sqli()` — uses payloads_sqli_auth_bypass, traffic_form_post with "sqlmap" tool sig, checks response for "welcome|dashboard|admin|success", records WAF stats
2. `exploit_command_injection()` — uses payloads_cmdi_ping, traffic_curl with "sqlmap" sig, checks for "uid=|root:|Linux|GNU"
3. `exploit_webshell_deploy()` — creates temp shell script, uploads via curl, executes via /shell/{filename}?cmd=whoami, checks for "uid=|root"
4. `exploit_xss_poc()` — tests 7 XSS payloads (script, img, svg, quote-break) for reflected + stored XSS via /search and /comments

**Verification:** `bash -n bait_n_break/attacker/lib_web_exploit.sh` exits 0

#### Task 7: lib_cve_exploits.sh — CVE Exploits (8 CVEs)

**File:** Modify `bait_n_break/attacker/lib_cve_exploits.sh` (full rewrite, ~400 lines)

**Functions to rewrite:**
1. `exploit_apache_41773()` — uses payloads_apache_41773, traffic_curl with "metasploit" sig, tests path traversal then RCE via POST to /bin/sh
2. `exploit_shellshock_6271()` — uses payloads_shellshock_6271, traffic_curl with User-Agent header, tests echo then RCE via /usr/bin/id
3. `exploit_webmin_15107()` — POST to /password_change.cgi with backdoor payload, metasploit sig
4. `exploit_ghostcat_1938()` — Python AJP packet to read /WEB-INF/web.xml (keep existing Python code), adds waf_tracker
5. `exploit_log4shell_pattern()` — uses payloads_log4shell_jndi, traffic_json_post to /api/log with JSON
6. `exploit_spring4shell_pattern()` — POST to /api/server/config with parameter binding payload
7. `exploit_struts_upload_pattern()` — uploads webshell with path traversal filename, verifies via /shell/
8. `exploit_polkit_4034()` — uploads runner script, executes via /shell/ with --poc, checks for "Got root!|uid=0"

**Key:** Each function: mission_brief() at start, phase_banner(), fake_shell() showing msfconsole command, iterate payloads with bar() + waf_tracker(), debrief_card() at end. Use _engine_reset_waf() at top. Results recorded via results_record() with MITRE tactic tags.

**Verification:** `bash -n bait_n_break/attacker/lib_cve_exploits.sh` exits 0

#### Task 8: lib_recon.sh — Reconnaissance (nmap pattern)

**File:** Modify `bait_n_break/attacker/lib_recon.sh` (rewrite, ~80 lines)

**What to build:**
- `recon_scan()` — mission_brief "Reconnaissance" "TA0043" → phase_banner RECON → fake_shell nmap → real nmap -sV -sC -p common ports → fallback /dev/tcp probe → results_record

**Verification:** `bash -n bait_n_break/attacker/lib_recon.sh` exits 0

#### Task 9: lib_bruteforce.sh — Brute Force (hydra pattern)

**File:** Modify `bait_n_break/attacker/lib_bruteforce.sh` (rewrite, ~160 lines)

**What to build:**
- `bruteforce_ssh()` — uses payloads_bruteforce_creds, hydra if available else sshpass, with "hydra_ssh" tool sig, waf_tracker per attempt
- `bruteforce_ftp()` — same pattern, FTP port 2121
- `bruteforce_http()` — same pattern, POST to /login, check HTTP 200

**Verification:** `bash -n bait_n_break/attacker/lib_bruteforce.sh` exits 0

#### Task 10: lib_crawler.sh + lib_post_exploit.sh + lib_malware_c2.sh

**Files:** 3 files (can be done as sub-tasks in parallel):
- Modify `bait_n_break/attacker/lib_crawler.sh` — rewrite with gobuster tool sig, mission_brief + phase_banner COLLECTION TA0009, uses payloads_crawler_paths
- Modify `bait_n_break/attacker/lib_post_exploit.sh` — rewrite 10 post-exploit functions with engine integration
- Modify `bait_n_break/attacker/lib_malware_c2.sh` — rewrite with phase_banner IMPACT TA0040

**Verification:** Each file passes `bash -n`

---

### Phase 4: QA/QC

> After ALL tasks complete, run these checks:

- [ ] **Syntax check:** `for f in $(find bait_n_break/attacker -name '*.sh'); do bash -n "$f" || echo "FAIL: $f"; done`
- [ ] **Cross-reference:** All functions called in attacker_console.sh exist in sourced files
- [ ] **End-to-end test:** Run `./run.sh`, select Attacker, enter target IP, run Recon, verify output shows mission_brief + fake_shell + results
- [ ] **WAF tracking test:** Verify waf_tracker increments counters and debrief_card shows WAF stats
- [ ] **Results summary test:** Run multiple exploits, press R in menu, verify short_summary table renders correctly
- [ ] **Red-team review:** Verify kill-chain phase ordering is correct (Recon → Initial Access → Execution → Cred Access → Priv Esc → Collection → Lateral+Persist → Impact)
- [ ] **Traffic realism:** Run exploit, capture traffic with tcpdump, verify User-Agent matches tool_sig fingerprints
- [ ] **CRLF fix:** Convert all .sh files to LF line endings
- [ ] **Git commit + push**
