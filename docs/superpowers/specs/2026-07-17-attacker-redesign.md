# Attacker Module Redesign — Realistic Attack Traffic for WAF Detection

**Date:** 2026-07-17
**Status:** Approved

## 1. Problem Statement

Current attacker module uses simple `curl` commands with one-shot payloads. The traffic is too clean and not representative of real attack patterns. A real WAF (which sits between attacker and victim) cannot detect these naive requests. The module needs to generate traffic that mimics real security tools (nmap, sqlmap, hydra, etc.) with realistic HTTP fingerprints, payload encoding variants, and WAF evasion attempts.

## 2. Success Criteria

- WAF between attacker and victim can detect and block realistic attack patterns
- Each attack vector generates traffic indistinguishable from real security tools
- Payload library includes encoding variants that real attackers use for evasion
- Attacker console shows WAF block/bypass status per payload attempt
- All 17 attack vectors mapped to MITRE ATT&CK kill-chain phases
- "Run All Scenarios" follows full kill-chain: Recon → Initial Access → Execution → Credential Access → Privilege Escalation → Collection → Lateral Movement/Persistence → Impact

## 3. Architecture

### 3.1 New File Structure
```
attacker/
  lib_engine.sh        NEW  — typewriter, fake_shell, waf_tracker, phase_banner, bar, tool_sig, ops
  lib_traffic.sh       NEW  — HTTP request factory with realistic headers/timing/tool fingerprints
  lib_payloads.sh      NEW  — payload library with encoding variants per vulnerability type
  lib_recon.sh         REWRITE
  lib_bruteforce.sh    REWRITE
  lib_web_exploit.sh   REWRITE
  lib_cve_exploits.sh  REWRITE
  lib_crawler.sh       REWRITE
  lib_post_exploit.sh  REWRITE
  lib_malware_c2.sh    REWRITE
  lib_results.sh       ENHANCE — add MITRE technique tag + WAF status fields
  lib_target.sh        KEEP — minor tweaks
  wordlists/           KEEP existing
```

### 3.2 Dependency Flow
```
attacker_console.sh         (whiptail menu)
  ├── lib_target.sh         (target IP/port)
  ├── lib_engine.sh         (rendering engine)
  ├── lib_traffic.sh        (HTTP request factory)
  ├── lib_payloads.sh       (payload variant library)
  └── [exploit libraries]   →→→ call engine + traffic + payloads + results
       ├── phase_banner()
       ├── fake_shell()
       ├── bar()
       ├── waf_tracker()
       └── ops()
```

## 4. Core Engine (`lib_engine.sh`)

| Function | Signature | Purpose |
|----------|-----------|---------|
| `twi` | `twi "text" [delay_ms]` | Typewriter effect — prints text character by character |
| `fake_shell` | `fake_shell "cmd"` | Prints `root@kali:~# cmd`, runs it, captures output |
| `phase_banner` | `phase_banner "INITIAL ACCESS" "TA0001"` | Kill-chain phase header with MITRE tag |
| `waf_tracker` | `waf_tracker <http_code> <payload_desc>` | Classifies response: BYPASSED (2xx), BLOCKED (403/406), ERROR (5xx) |
| `bar` | `bar <current> <total>` | Progress bar `[#####-----] 50%` |
| `tool_sig` | `tool_sig "sqlmap"` | Returns fingerprint (User-Agent, headers, timing) for given tool |
| `ops` | `ops "quiet\|medium\|loud"` | Records OPSEC detection risk level |

## 5. Traffic Library (`lib_traffic.sh`)

Generates HTTP requests that match real tool signatures:

| Tool | Fingerprint |
|------|------------|
| nmap -sV | `Mozilla/5.0 (compatible; Nmap Scripting Engine; https://nmap.org/book/nse.html)` |
| sqlmap | `sqlmap/1.8#stable (https://sqlmap.org)` |
| hydra (SSH) | Rapid connection attempts, 4 threads, credential cycling |
| hydra (HTTP) | POST with form data, varied timing |
| gobuster | `gobuster/3.6` UA, rapid HEAD/GET requests |
| nikto | `Mozilla/5.0 (Nikto/2.5.0)` UA, multiple plugin probes |
| metasploit | `Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)` UA |

## 6. Payload Library (`lib_payloads.sh`)

Each vulnerability type has payloads with multiple encoding variants:

```bash
sqli_auth_bypass_payloads=(
  "' OR '1'='1'--"              # plain
  "'+OR+'1'%3d'1'--"           # URL-encoded operators
  "admin'--"                     # comment-only bypass
  "' UNION SELECT 1,2,3--"      # union-based
  "'/**/OR/**/1=1--"            # comment-obfuscated
  "') OR ('1'='1'--"            # parenthesis variant
  "%27%20OR%20%271%27%3D%271%27--"  # full URL-encoded
)

cmdi_ping_payloads=(
  "127.0.0.1;id"                # semicolon
  "127.0.0.1|id"                # pipe
  "127.0.0.1\`id\`"             # backtick
  "127.0.0.1%0aid"              # newline injection
  "127.0.0.1%3Bid"             # URL-encoded semicolon
  "127.0.0.1||id"               # OR operator
  "127.0.0.1&&id"               # AND operator
)
```

## 7. Attack Vector Mapping

| # | Vector | Tool Pattern | Kill-Chain Phase | MITRE ID | Payload Variants |
|---|--------|-------------|-----------------|----------|-----------------|
| 1 | Recon | nmap -sV -sC --script vuln | Reconnaissance | TA0043 | — |
| 2 | Brute Force | hydra/medusa (SSH+FTP+HTTP) | Credential Access | TA0006 | 15 creds × 3 services |
| 3 | SQL Injection | sqlmap --level=3 --risk=2 | Initial Access | TA0001 | 40+ SQLi variants |
| 4 | Command Injection | commix | Execution | TA0002 | 15+ CMDi variants |
| 5 | Webshell Deploy | msfvenom + upload + exec | Execution | TA0002 | PHP/ASP/JSP shells |
| 6 | XSS PoC | xsser/BeEF (reflected+stored) | Initial Access | TA0001 | Reflected + Stored + DOM |
| 7 | CVE-2021-41773 | Apache path traversal + RCE | Initial Access | TA0001 | dot-dot-slash + double-encode |
| 8 | CVE-2014-6271 | Shellshock Bash CGI | Initial Access | TA0001 | 4 User-Agent payloads |
| 9 | CVE-2019-15107 | Webmin password_change.cgi RCE | Initial Access | TA0001 | 2 injection payloads |
| 10 | CVE-2020-1938 | Tomcat Ghostcat AJP LFI | Initial Access | TA0001 | AJP protocol packet |
| 11 | Log4Shell Pattern | JNDI injection (ldap/ldaps/dns) | Initial Access | TA0001 | 3 JNDI schemes |
| 12 | Spring4Shell | Parameter binding file write | Initial Access | TA0001 | 3 config variants |
| 13 | Struts2 Pattern | Path traversal upload → RCE | Execution | TA0002 | 3 traversal paths |
| 14 | Polkit LPE | pkexec PoC (post-foothold) | Privilege Escalation | TA0004 | — |
| 15 | Bait Crawler | gobuster/dirbuster (200 paths) | Collection | TA0009 | 200+ candidate paths |
| 16 | Post-Exploitation | LFI/SSRF/XXE/IDOR/deser/escape/persist | Lateral + Persistence | TA0008+TA0003 | 10 techniques |
| 17 | Malware/C2 | Ransomware beacon + C2 heartbeat | Impact | TA0040 | 3 simulation scenarios |

## 8. Execution Flow

### 8.1 Single Vector Selection
1. **Mission Briefing** (1-2s): Shows target, technique, MITRE ID, OPSEC risk, kill-chain phase
2. **Recon Phase** (if applicable): `fake_shell` running nmap/gobuster patterns against target
3. **Exploit Phase**: Iterates payload library with `waf_tracker` showing BLOCKED/BYPASSED per payload, `bar` showing progress
4. **Post-Exploit Phase**: Harvests credentials, accesses admin panels, collects bait files
5. **De-brief Card**: Summary showing status, WAF stats, credentials harvested, crown jewels accessed

### 8.2 Run All Scenarios (Full Kill-Chain)
```
Phase 1: Reconnaissance         [TA0043]  — nmap scan all ports
Phase 2: Initial Access         [TA0001]  — 11 exploit vectors
Phase 3: Execution              [TA0002]  — webshell/cmd injection results
Phase 4: Credential Access      [TA0006]  — SSH/FTP/HTTP brute force
Phase 5: Privilege Escalation   [TA0004]  — Polkit LPE
Phase 6: Collection             [TA0009]  — bait file crawler
Phase 7: Lateral + Persistence  [TA0008/3]— 10 post-exploit techniques
Phase 8: Impact                 [TA0040]  — malware/C2 simulation
```

### 8.3 Run All CVEs
Only CVEs (vectors 7-14): Apache, Shellshock, Webmin, Ghostcat, Log4Shell, Spring4Shell, Struts2, Polkit. No web exploits, brute force, or post-exploit.

## 9. Menu + Results

### 9.1 Whiptail Menu Enhancements
- Status icons next to each vector (KEY = exploited, LOCK = failed, WALL = all blocked by WAF, ● = not run)
- "Total: X/17 exploited | Crown Jewels: Y" counter
- "R — View Results Summary" option
- "WAF: Active" indicator next to target IP

### 9.2 Results Summary
```
┌──────────────────────────────────────────────┐
│  #  Vector              Status     WAF B/B  │
│  1  Recon               SUCCESS    —        │
│  3  SQL Injection       VULNERABLE 3/7      │
│  8  CVE-2014-6271       VULNERABLE 1/4      │
│ 11  Log4Shell Pattern   FAILED     7/7      │
│──────────────────────────────────────────────│
│  Total: 14/17 exploited | WAF bypass: 31%    │
└──────────────────────────────────────────────┘
```

### 9.3 Results File Format (Enhanced)
```
[2026-07-17 14:24:15] [exploit_sqli] [VULNERABLE] [TA0001] [OPSEC:medium] [WAF:3B/4P] auth bypass: admin:admin123
```

## 10. Non-Goals

- No WAF is installed on the victim machine (user has external WAF between machines)
- No modification to victim-side services or web app
- No new external dependencies beyond what already exists (nmap, sqlmap, hydra are optional)
- No Python/Node runtime for the shell layer (bash only for TUI/orchestration)
- No modification to `ansi_tui.sh`, `victim_dashboard.sh`, or `main_menu.sh`

## 11. Implementation Order

1. `lib_engine.sh` — core rendering utilities
2. `lib_traffic.sh` — HTTP request factory
3. `lib_payloads.sh` — payload variant library
4. `attacker_console.sh` — updated menu with status + results
5. Rewrite exploit libraries one by one (start with high-impact: recon, sqli, cmdi)
6. Full end-to-end QA with each exploit
7. Verify WAF detection by running from attacker machine through WAF to victim
