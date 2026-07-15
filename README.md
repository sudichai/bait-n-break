# 🔐 bait-n-break

> **Self-contained cybersecurity training lab** — deploy intentionally vulnerable services, then attack them through a menu-driven TUI. Built with pure Bash. Runs on stock Ubuntu and Kali.

---

## 🚀 Quick Start

```bash
git clone https://github.com/sudichai/bait-n-break.git && cd bait-n-break && bash setup.sh && bash run.sh
```

> Do **not** use `sudo` with `git clone` — it will break permissions. `setup.sh` handles everything automatically including dpkg lock conflicts.

```
┌─────────────────────────────┐
│        bait-n-break         │
│                             │
│  [1] Victim (Target)        │
│  [2] Attacker (Kali)        │
│  [3] Exit                   │
└─────────────────────────────┘
```

---

## 🎯 What's Inside

### Victim (Target) Node

| Component | Details |
|-----------|---------|
| 🐍 **Vulnerable Web App** | Flask app with 42+ endpoints exposing 50+ vulnerability classes |
| 🛢️ **MySQL Database** | Port `3306`, weak credentials (`root:root`, `webapp:webapp123`) |
| 🔓 **SSH Decoy** | Port `2222`, credentials `admin:admin123`, sudo access |
| 🔓 **FTP Decoy** | Port `2121`, credentials `admin:admin123` |
| 🍯 **Bait Files** | 31 decoy files — cloud creds, SSH keys, CI/CD secrets, browser profiles, VPN configs, password lists, source code, logs |
| 👁️ **Live Monitor** | Tails webapp logs + auth.log + bait file access in real-time |
| 📊 **Vulnerability Overview** | Dynamic live check showing which vulns are active right now |
| 💣 **Malware Sim** | EICAR test file, sandboxed ransomware demo, C2 beacon check |

### Vulnerabilities (Kill-Chain Mapped) — 50+

| Phase | Vulnerabilities |
|-------|----------------|
| **Recon** | `/admin`, `/env`, `/debug`, `/robots.txt`, `/files/<area>/`, DNS info, Docker exposes ports 2222/2121/3306 |
| **Initial Access** | SQLi `/login`, Unrestricted upload `/upload`, Weak SSH (2222), Weak FTP (2121), Weak MySQL (3306) |
| **Execution** | CMDi `/ping`, LFI `/read`, SSRF `/fetch`, XXE `/parse`, Pickle deser `/pickle`, Open Redirect `/redirect`, Arbitrary file download `/download` |
| **Privilege Escalation** | SUID `find/awk/curl`, Sudo misconfig (`victim` NOPASSWD), Docker socket mounted (`/var/run/docker.sock`) |
| **Persistence** | SSH key injection `/persist/ssh-key`, Cron backdoor `/persist/cron` |
| **Credential Access** | IDOR `/users/<id>` (SSN, role, password), LFI `/etc/passwd` + `/etc/shadow`, `/env` leak, JWT none-algorithm `/api/auth` |
| **Collection** | Bait files via `/files/<area>/<path>`, Reflected XSS `/search`, Stored XSS `/comments` |
| **Web App Vulns** | CSRF `/admin/transfer` + `/admin/password`, Mass Assignment `/api/profile/update`, Race Condition `/api/coupon/apply`, Weak Crypto `/reset` (predictable token), Session Fixation `/login?sid=`, HTTP Param Pollution `/api/search`, CORS wildcard `*`, Missing security headers, No rate limiting |
| **Exfiltration** | DNS tunneling `/exfil/dns`, HTTP exfil `/exfil/http` |
| **C2** | Beacon `/c2/beacon` with remote command execution |
| **Impact** | Ransomware demo `/admin/ransomware-demo`, Defacement `/admin/deface`, DB wipe `/admin/wipe-db`, Log clearing `/admin/clear-logs` |

### Attacker (Kali) Scenarios — 16 modules + 3 chains

| Module | Kill-Chain Phase | Method |
|--------|-----------------|--------|
| Recon scan | Recon | `nmap` top 1000 ports + service detection |
| SSH brute-force | Credential Access | `hydra` / `sshpass` (15 credentials) |
| FTP brute-force | Credential Access | `hydra` / `curl` (15 credentials) |
| HTTP brute-force | Credential Access | `curl` POST (15 credentials) |
| MySQL brute-force | Credential Access | `mysql` client |
| SQL injection | Execution | `sqlmap` + hand-rolled payloads (4 variants) |
| Command injection | Execution | `curl` (5 payload variants) |
| Webshell deploy | Execution | Upload + execute |
| LFI | Execution | Path traversal (8 file targets) |
| SSRF | Execution | Internal endpoint enumeration |
| XXE | Execution | XML external entity (3 file targets) |
| IDOR | Credential Access | User enumeration (7 IDs) |
| Pickle deser | Execution | Base64 pickle RCE |
| Credential harvest | Credential Access | Env dump + LFI + SSH key grab |
| Docker escape | Priv Esc | Docker socket via `/docker` |
| Persistence (SSH/cron) | Persistence | Key injection + cron backdoor |
| Crawler | Collection | 50-path wordlist with delay |
| C2 beacon | C2 | `curl` (3 attempts) |
| Ransomware trigger | Impact | `POST /admin/ransomware-demo` |
| DNS exfiltration | Exfiltration | DNS tunneling |
| Defacement | Impact | `POST /admin/deface` |
| DB wipe | Impact | `POST /admin/wipe-db` |
| Log clearing | Impact | `POST /admin/clear-logs` |

**Multi-Stage Attack Chains:**
| Chain | Path | Phases |
|-------|------|--------|
| **Chain A** | SQLi → Cred Dump → SSH → Docker Escape | 6 stages, data flows between each |
| **Chain B** | CMDi → Webshell → Persistence → Impact | 4 stages |
| **Chain C** | SSRF → Internal Enum → LFI → DNS Exfil | 4 stages |

**Full Kill-Chain:** `Run All Scenarios` runs 9 phases with realistic delays between each.

---

## 📁 Project Structure

```
bait-n-break/
├── run.sh
├── setup.sh
├── bait_n_break/
│   ├── shared/
│   │   ├── config.sh
│   │   ├── lib_ui.sh
│   │   └── lib_state.sh
│   ├── tui/
│   │   ├── main_menu.sh
│   │   ├── victim_dashboard.sh
│   │   └── attacker_console.sh
│   ├── victim/
│   │   ├── lib_bait.sh
│   │   ├── lib_webapp.sh
│   │   ├── lib_monitor.sh
│   │   ├── lib_malware_sim.sh
│   │   ├── lib_vuln_overview.sh
│   │   └── webapp/
│   │       ├── app.py
│   │       ├── Dockerfile
│   │       ├── docker-compose.yml
│   │       └── requirements.txt
│   └── attacker/
│       ├── lib_results.sh
│       ├── lib_target.sh
│       ├── lib_recon.sh
│       ├── lib_bruteforce.sh
│       ├── lib_web_exploit.sh
│       ├── lib_crawler.sh
│       ├── lib_malware_c2.sh
│       ├── lib_post_exploit.sh
│       └── wordlists/
│           └── common_paths.txt (50 paths)
└── .state/ (runtime, gitignored)
```

---

## 🛡️ Safety

- **All credentials are dummy** — `admin:admin123`, `root:toor`, fake AWS/GCP/Azure keys
- **All bait content is inert** — no real secrets, safe to leave on disk
- **Malware sim is sandboxed** — ransomware demo confined to `ransomware_target/`
- **Docker isolation** — vulnerable services run in containers
- **Lab-only** — never deploy outside an isolated training network

---

## 📋 Requirements

- **OS:** Ubuntu, Kali, or Debian
- **Dependencies:** Docker, Docker Compose v2, `whiptail` (or `dialog`)
- **Optional:** `hydra`, `sqlmap`, `nmap`, `sshpass` — installed by `setup.sh`, fallbacks built-in

---

## 📄 License

This project is for educational purposes only. Do not deploy outside an isolated lab environment.
