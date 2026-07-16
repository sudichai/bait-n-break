# bait-n-break

> **Self-contained cybersecurity training lab** -- deploy intentionally vulnerable services + real CVE services, then attack them through a custom ANSI TUI. Built with pure Bash. Runs on stock Ubuntu and Kali.

---

## Quick Start

```bash
git clone https://github.com/sudichai/bait-n-break.git && cd bait-n-break && bash setup.sh && bash run.sh
```

> Do **not** use `sudo` with `git clone` -- it will break permissions. `setup.sh` handles everything automatically including dpkg lock conflicts.

```
+-----------------------------+
|        bait-n-break         |
|                             |
|  [1] Victim (Target)        |
|  [2] Attacker (Kali)        |
|  [3] Exit                   |
+-----------------------------+
```

---

## What's Inside

### Victim (Target) Node

| Component | Details |
|-----------|---------|
| **Vulnerable Web App** | Flask app with **54+ endpoints** exposing **68+ vulnerability classes** |
| **MySQL Database** | Port `3306`, weak credentials (`root:root`, `webapp:webapp123`) |
| **SSH Decoy** | Port `2222`, credentials `admin:admin123`, sudo access |
| **FTP Decoy** | Port `2121`, credentials `admin:admin123` |
| **6 Real CVE Services** | Dockerized vulnerable services with published exploits (see CVE table below) |
| **Bait Files** | 31 decoy files -- cloud creds, SSH keys, CI/CD secrets, browser profiles, VPN configs, password lists, source code, logs |
| **Live ANSI Dashboard** | Persistent 3-panel TUI: services + TCP connections, kill-chain vuln counts, real-time incident log (auto-refresh 2s) |
| **Live Monitor** | Tails webapp logs + auth.log + bait file access in real-time |
| **Malware Sim** | EICAR test file, sandboxed ransomware demo, C2 beacon check |

### Real CVE Services

| CVE | Service | Port | Vulnerability Class | Kill Chain |
|-----|---------|------|-------------------|------------|
| CVE-2021-41773 | Apache HTTPD 2.4.49 | `8081` | Path Traversal -> RCE via CGI | Initial Access |
| CVE-2014-6271 | Shellshock (Bash CGI) | `8082` | Env Injection -> RCE | Initial Access |
| CVE-2015-3306 | ProFTPD 1.3.5 mod_copy | `2122` | Unauthenticated File Copy -> RCE | Initial Access |
| CVE-2019-15107 | Webmin <=1.920 | `10000` | Auth Bypass -> Command Injection | Initial Access |
| CVE-2020-1938 | Tomcat Ghostcat (AJP) | `8083`/`8009` | AJP File Read -> RCE | Recon / Initial Access |
| CVE-2021-4034 | Polkit pkexec LPE | *(inside container)* | Argument Injection -> Root Shell | Privilege Escalation |

### Flask CVE-Patterned Endpoints

| Pattern | Endpoint | CVE Mimicked |
|---------|----------|-------------|
| Log4Shell-style JNDI Injection | `/api/log` | CVE-2021-44228 |
| Spring4Shell-style Param Binding | `/api/server/config` | CVE-2022-22965 |
| Struts2-style Path Traversal Upload | `/api/upload-archive` | CVE-2023-50164 |

### Vulnerabilities (Kill-Chain Mapped) -- 68+

| Phase | Vulnerabilities |
|-------|----------------|
| **Recon** | `/admin`, `/env`, `/debug`, `/robots.txt`, `/files/<area>/`, DNS info, Docker exposes ports 2222/2121/3306 |
| **Initial Access** | SQLi `/login`, Unrestricted upload `/upload`, Weak SSH (2222), Weak FTP (2121), Weak MySQL (3306), **CVE-2021-41773 Apache RCE**, **CVE-2014-6271 Shellshock**, **CVE-2015-3306 ProFTPD RCE**, **CVE-2019-15107 Webmin RCE**, **CVE-2020-1938 Tomcat Ghostcat**, **Log4Shell pattern JNDI**, **Spring4Shell pattern binding**, **Struts2 pattern upload** |
| **Execution** | CMDi `/ping`, LFI `/read`, SSRF `/fetch`, XXE `/parse`, Pickle deser `/pickle`, Open Redirect `/redirect`, Arbitrary file download `/download` |
| **Privilege Escalation** | SUID `find/awk/curl`, Sudo misconfig (`victim` NOPASSWD), Docker socket mounted (`/var/run/docker.sock`), **CVE-2021-4034 Polkit pkexec LPE** |
| **Persistence** | SSH key injection `/persist/ssh-key`, Cron backdoor `/persist/cron` |
| **Credential Access** | IDOR `/users/<id>` (SSN, role, password), LFI `/etc/passwd` + `/etc/shadow`, `/env` leak, JWT none-algorithm `/api/auth` |
| **Collection** | Bait files via `/files/<area>/<path>`, Reflected XSS `/search`, Stored XSS `/comments` |
| **Web App Vulns** | CSRF `/admin/transfer` + `/admin/password`, Mass Assignment `/api/profile/update`, Race Condition `/api/coupon/apply`, Weak Crypto `/reset` (predictable token), Session Fixation `/login?sid=`, HTTP Param Pollution `/api/search`, CORS wildcard `*`, Missing security headers, No rate limiting |
| **Exfiltration** | DNS tunneling `/exfil/dns`, HTTP exfil `/exfil/http` |
| **C2** | Beacon `/c2/beacon` with remote command execution |
| **Impact** | Ransomware demo `/admin/ransomware-demo`, Defacement `/admin/deface`, DB wipe `/admin/wipe-db`, Log clearing `/admin/clear-logs` |

### Attacker (Kali) Scenarios -- 25 modules + 3 chains

**Custom ANSI TUI**: persistent 3-panel dashboard (Attack Vectors | Vulnerabilities Found | Execute/Logs) with keyboard shortcuts and real-time streaming output. Falls back to whiptail/dialog on small terminals.

| Module | Kill-Chain Phase | OPSEC | Method |
|--------|-----------------|-------|--------|
| Recon scan | Recon | quiet | `nmap` top 1000 ports + service detection |
| SSH brute-force | Credential Access | loud | `hydra` / `sshpass` (15 credentials) |
| FTP brute-force | Credential Access | loud | `hydra` / `curl` (15 credentials) |
| HTTP brute-force | Credential Access | loud | `curl` POST (15 credentials) |
| MySQL brute-force | Credential Access | loud | `mysql` client |
| SQL injection | Execution | quiet | `sqlmap` + hand-rolled payloads (4 variants) |
| Command injection | Execution | loud | `curl` (5 payload variants) |
| Webshell deploy | Execution | loud | Upload + execute |
| LFI | Execution | loud | Path traversal (8 file targets) |
| SSRF | Execution | quiet | Internal endpoint enumeration |
| XXE | Execution | quiet | XML external entity (3 file targets) |
| IDOR | Credential Access | quiet | User enumeration (7 IDs) |
| Pickle deser | Execution | loud | Base64 pickle RCE |
| Credential harvest | Credential Access | quiet | Env dump + LFI + SSH key grab |
| Docker escape | Priv Esc | loud | Docker socket via `/docker` |
| Persistence (SSH/cron) | Persistence | loud | Key injection + cron backdoor |
| Crawler | Collection | quiet | 50-path wordlist with delay |
| C2 beacon | C2 | quiet | `curl` (3 attempts) |
| Ransomware trigger | Impact | loud | `POST /admin/ransomware-demo` |
| DNS exfiltration | Exfiltration | quiet | DNS tunneling |
| Defacement | Impact | loud | `POST /admin/deface` |
| DB wipe | Impact | loud | `POST /admin/wipe-db` |
| Log clearing | Impact | loud | `POST /admin/clear-logs` |
| **CVE-2021-41773 Apache RCE** | Initial Access | loud | Path traversal + CGI execution |
| **CVE-2014-6271 Shellshock** | Initial Access | loud | User-Agent header injection |
| **CVE-2015-3306 ProFTPD RCE** | Initial Access | quiet | SITE CPFR/CPTO file copy |
| **CVE-2019-15107 Webmin RCE** | Initial Access | medium | password_change.cgi injection |
| **CVE-2020-1938 Tomcat Ghostcat** | Recon / Init Access | medium | AJP binary packet (inline Python) |
| **Log4Shell Pattern JNDI** | Execution | medium | `${jndi:ldap://...}` resolution |
| **Spring4Shell Pattern** | Init Access | medium | Nested parameter binding -> file write |
| **Struts2 Pattern Upload** | Init Access | loud | `../` path traversal upload -> RCE |
| **CVE-2021-4034 Polkit LPE** | Priv Esc | quiet | pkexec argument injection -> root |

**Multi-Stage Attack Chains:**
| Chain | Path | Phases |
|-------|------|--------|
| **Chain A** | SQLi -> Cred Dump -> SSH -> Docker Escape | 6 stages, data flows between each |
| **Chain B** | CMDi -> Webshell -> Persistence -> Impact | 4 stages |
| **Chain C** | SSRF -> Internal Enum -> LFI -> DNS Exfil | 4 stages |

**Full Kill-Chain:** `Run All Scenarios` runs 8 phases: Recon -> CVE Initial Access -> Web Exploitation -> Brute Force -> CVE Privilege Escalation -> Post-Exploit -> Exfil -> Impact. `Run All CVEs` (hotkey `C`) chains all 9 CVE exploits in kill-chain order.

---

## Project Structure

```
bait-n-break/
+-- run.sh
+-- setup.sh
+-- bait_n_break/
|   +-- shared/
|   |   +-- config.sh
|   |   +-- lib_ui.sh
|   |   +-- lib_state.sh
|   +-- tui/
|   |   +-- ansi_tui.sh
|   |   +-- main_menu.sh
|   |   +-- victim_dashboard.sh
|   |   +-- victim_dashboard_fallback.sh
|   |   +-- attacker_console.sh
|   |   +-- attacker_console_fallback.sh
|   +-- victim/
|   |   +-- lib_bait.sh
|   |   +-- lib_webapp.sh
|   |   +-- lib_monitor.sh
|   |   +-- lib_malware_sim.sh
|   |   +-- lib_vuln_overview.sh
|   |   +-- lib_live_dashboard.sh
|   |   +-- webapp/
|   |       +-- app.py
|   |       +-- Dockerfile
|   |       +-- docker-compose.yml
|   |       +-- requirements.txt
|   |       +-- cve-services/
|   |           +-- apache-2.4.49/
|   |           +-- shellshock/
|   |           +-- proftpd-1.3.5/
|   |           +-- webmin-1.890/
|   |           +-- tomcat-ghostcat/
|   |           +-- polkit/
|   +-- attacker/
|       +-- lib_results.sh
|       +-- lib_target.sh
|       +-- lib_recon.sh
|       +-- lib_bruteforce.sh
|       +-- lib_web_exploit.sh
|       +-- lib_cve_exploits.sh
|       +-- lib_crawler.sh
|       +-- lib_malware_c2.sh
|       +-- lib_post_exploit.sh
|       +-- wordlists/
|           +-- common_paths.txt (50 paths)
+-- .state/ (runtime, gitignored)
```

---

## Safety

- **All credentials are dummy** -- `admin:admin123`, `root:toor`, fake AWS/GCP/Azure keys
- **All bait content is inert** -- no real secrets, safe to leave on disk
- **Malware sim is sandboxed** -- ransomware demo confined to `ransomware_target/`
- **Docker isolation** -- vulnerable services run in containers
- **Lab-only** -- never deploy outside an isolated training network

---

## Requirements

- **OS:** Ubuntu, Kali, or Debian
- **Dependencies:** Docker, Docker Compose (V2 plugin or legacy `docker-compose`), `whiptail` (or `dialog`)
- **Optional:** `hydra`, `sqlmap`, `nmap`, `sshpass`, `python3` -- installed by `setup.sh`, fallbacks built-in
- **TUI:** `bash` 4.x+, `tput` (ncurses-base, pre-installed on all supported distros)

---

## License

This project is for educational purposes only. Do not deploy outside an isolated lab environment.
