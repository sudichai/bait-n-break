# 🔐 bait-n-break

> **Self-contained cybersecurity training lab** — deploy intentionally vulnerable services + real CVE services, then attack them through a custom ANSI TUI. Built with pure Bash. Runs on stock Ubuntu and Kali.

---

## 🚀 Quick Start

```bash
git clone https://github.com/sudichai/bait-n-break.git && cd bait-n-break && bash setup.sh && bash run.sh
```

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

```
┌──────────────────────────────────────────────────────────────┐
│                      bait-n-break Lab                        │
│                                                              │
│  ┌─────────────────────┐      ┌─────────────────────────┐    │
│  │   VICTIM (Target)   │      │    ATTACKER (Kali)      │    │
│  │                     │      │                         │    │
│  │  Flask Web App      │      │  ANSI TUI Dashboard     │    │
│  │  MySQL 5.7          │      │  Recon (nmap)           │    │
│  │  SSH Decoy          │ ───▶ │  32 Attack Modules      │    │
│  │  FTP Decoy          │      │  9 CVE Exploits         │    │
│  │  6 CVE Services     │      │  3 Attack Chains        │    │
│  │  31 Bait Files      │      │  Results + Scoring      │    │
│  │  Live Monitor       │      │                         │    │
│  └─────────────────────┘      └─────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

---

### 🎯 Victim (Target) Node

| 🧩 Component | 📋 Details |
|:-------------|:-----------|
| 🐍 **Flask Web App** | **54+ endpoints** exposing **68+ vuln classes** |
| 🛢️ **MySQL Database** | Port `3306` · `root:root` / `webapp:webapp123` |
| 🔓 **SSH Decoy** | Port `2222` · `admin:admin123` · sudo access |
| 🔓 **FTP Decoy** | Port `2121` · `admin:admin123` |
| 🐳 **6 Real CVE Services** | Dockerized with published exploits → see table below |
| 🍯 **Bait Files** | **31 decoy files** · cloud creds · SSH keys · CI/CD secrets · VPN configs · DB dumps |
| 🖥️ **Live ANSI Dashboard** | 3-panel TUI: services + connections · vuln counts · incidents (refresh 2s) |
| 📡 **Live Monitor** | Real-time webapp + auth + bait file access log tailing |
| 💣 **Malware Sim** | EICAR test file · sandboxed ransomware demo · C2 beacon |

---

### 🐳 Real CVE Services (Dockerized)

| 🔖 CVE | 🏷️ Service | 🔌 Port | 🧬 Class | ⛓️ Kill Chain |
|:-------|:-----------|:-------|:---------|:-------------|
| **CVE-2021-41773** | Apache HTTPD 2.4.49 | `8081` | Path Traversal → RCE via CGI | Initial Access |
| **CVE-2014-6271** | Shellshock (Bash CGI) | `8082` | Env Injection → RCE | Initial Access |
| **CVE-2015-3306** | ProFTPD 1.3.5 mod_copy | `2122` | Unauth File Copy → RCE | Initial Access |
| **CVE-2019-15107** | Webmin ≤1.920 | `10000` | Auth Bypass → CMDi | Initial Access |
| **CVE-2020-1938** | Tomcat Ghostcat (AJP) | `8083`/`8009` | AJP LFI → RCE | Recon / Initial Access |
| **CVE-2021-4034** | Polkit pkexec LPE | `(local)` | Arg Injection → Root | Priv Escalation |

---

### 🧪 Flask CVE-Patterned Endpoints

| 🎭 Pattern | 🔗 Endpoint | 🎯 CVE Mimicked |
|:-----------|:-----------|:---------------|
| Log4Shell JNDI Injection | `/api/log` | CVE-2021-44228 |
| Spring4Shell Param Binding | `/api/server/config` | CVE-2022-22965 |
| Struts2 Path Traversal Upload | `/api/upload-archive` | CVE-2023-50164 |

---

### 🧬 Vulnerabilities — Kill-Chain Mapped (68+)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           KILL CHAIN MAP                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  🔍 RECON (5)                                                               │
│      /admin  /env  /debug  /robots.txt  /files/<area>/                       │
│                                                                              │
│  🔑 INITIAL ACCESS (14)                                                      │
│      SQLi /login  |  Upload /upload  |  SSH :2222  |  FTP :2121             │
│      MySQL :3306  |  6x CVE Services  |  3x Flask CVE patterns               │
│                                                                              │
│  ⚡ EXECUTION (8)                                                            │
│      CMDi /ping  |  LFI /read  |  SSRF /fetch  |  XXE /parse                │
│      Pickle deser  |  Open Redirect  |  File Download                        │
│                                                                              │
│  👑 PRIVILEGE ESCALATION (4)                                                 │
│      SUID find/awk/curl  |  Sudo misconfig  |  Docker socket escape          │
│      CVE-2021-4034 Polkit pkexec LPE                                         │
│                                                                              │
│  📌 PERSISTENCE (2)                                                          │
│      SSH key injection /persist/ssh-key  |  Cron backdoor /persist/cron      │
│                                                                              │
│  🔐 CREDENTIAL ACCESS (5)                                                    │
│      IDOR /users/<id>  |  LFI /etc/passwd+shadow  |  JWT none-alg            │
│      /env leak  |  Stack trace info disclosure                               │
│                                                                              │
│  📂 COLLECTION (6)                                                           │
│      Bait files /files/<area>/  |  Reflected XSS  |  Stored XSS              │
│                                                                              │
│  🕸️ WEB APP VULNS (9)                                                       │
│      CSRF 2x  |  Mass Assignment  |  Race Condition  |  Weak Crypto          │
│      Session Fixation  |  Param Pollution  |  CORS wildcard                  │
│      Missing security headers  |  No rate limiting                           │
│                                                                              │
│  📤 EXFILTRATION (2)  |  🦠 C2 (1)  |  🔥 IMPACT (5)                        │
│      DNS tunnel /exfil/dns   |   /c2/beacon   |   Ransomware  Defacement    │
│      HTTP exfil /exfil/http  |                |   DB Wipe     Log Clear      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

### 💥 Attacker (Kali) — 25 Modules + 3 Chains

**🖥️ Custom ANSI TUI**: persistent 3-panel dashboard with live streaming output and keyboard shortcuts.

```
┌─────────────────────┬─────────────────────┬─────────────────────┐
│  ATTACK VECTORS     │  VULNS FOUND        │  EXECUTE / LOGS     │
│                     │                     │                     │
│  [1] Recon          │  > CVE-2021-41773   │  Executing...       │
│  [2] Brute Force    │  > Shellshock RCE   │  Payload sent...    │
│  [3] SQL Injection  │  > Webmin RCE       │  Result: SUCCESS    │
│  [4] CMD Injection  │  > SQLi bypass      │                     │
│  [5] Webshell       │                     │                     │
│  ...                │                     │                     │
│  [A] Run All        │                     │                     │
│  [C] Run All CVEs   │                     │                     │
└─────────────────────┴─────────────────────┴─────────────────────┘
```

| 🔢 # | ⚔️ Module | ⛓️ Phase | 🫧 OPSEC | 🛠️ Method |
|:-----|:----------|:---------|:--------|:----------|
| 1 | 🔍 Recon scan | Recon | quiet | `nmap` top 1000 ports + service detection |
| 2 | 🔓 SSH brute-force | Cred Access | loud | `hydra` / `sshpass` (15 creds) |
| 3 | 🔓 FTP brute-force | Cred Access | loud | `hydra` / `curl` (15 creds) |
| 4 | 🔓 HTTP brute-force | Cred Access | loud | `curl` POST (15 creds) |
| 5 | 🛢️ MySQL brute-force | Cred Access | loud | `mysql` client |
| 6 | 💉 SQL injection | Execution | quiet | `sqlmap` + hand-rolled (4 variants) |
| 7 | 💉 Command injection | Execution | loud | `curl` (5 payload variants) |
| 8 | 🐚 Webshell deploy | Execution | loud | Upload + execute |
| 9 | 📄 LFI | Execution | loud | Path traversal (8 targets) |
| 10 | 🔄 SSRF | Execution | quiet | Internal endpoint enum |
| 11 | 📝 XXE | Execution | quiet | XML entity (3 targets) |
| 12 | 🆔 IDOR | Cred Access | quiet | User enum (7 IDs) |
| 13 | 🥒 Pickle deser | Execution | loud | Base64 pickle RCE |
| 14 | 🔑 Cred harvest | Cred Access | quiet | Env dump + LFI + SSH keys |
| 15 | 🐳 Docker escape | Priv Esc | loud | Docker socket `/docker` |
| 16 | 📌 Persistence | Persistence | loud | SSH key + cron backdoor |
| 17 | 🕷️ Crawler | Collection | quiet | 50-path wordlist |
| 18 | 🦠 C2 beacon | C2 | quiet | `curl` (3 attempts) |
| 19 | 🔒 Ransomware | Impact | loud | `POST /admin/ransomware-demo` |
| 20 | 📤 DNS exfil | Exfil | quiet | DNS tunneling |
| 21 | 💀 Defacement | Impact | loud | `POST /admin/deface` |
| 22 | 🗑️ DB wipe | Impact | loud | `POST /admin/wipe-db` |
| 23 | 🧹 Log clear | Impact | loud | `POST /admin/clear-logs` |
| 24 | 🐳 **CVE-2021-41773** | Init Access | loud | Path traversal + CGI RCE |
| 25 | 💣 **CVE-2014-6271** | Init Access | loud | User-Agent injection |
| 26 | 📁 **CVE-2015-3306** | Init Access | quiet | SITE CPFR/CPTO copy |
| 27 | 🕸️ **CVE-2019-15107** | Init Access | medium | password_change.cgi CMDi |
| 28 | 👻 **CVE-2020-1938** | Init Access | medium | AJP binary packet (Python) |
| 29 | 🪵 **Log4Shell Pattern** | Execution | medium | `${jndi:ldap://...}` resolve |
| 30 | 🌱 **Spring4Shell Pattern** | Init Access | medium | Nested param → file write |
| 31 | 📦 **Struts2 Pattern** | Init Access | loud | `../` upload → RCE |
| 32 | 👑 **CVE-2021-4034** | Priv Esc | quiet | pkexec arg injection → root |

---

### 🔗 Multi-Stage Attack Chains

```
┌──────────────────────────────────────────────────────────────┐
│  CHAIN A:  SQLi ──▶ Cred Dump ──▶ SSH ──▶ Docker Escape      │
│  CHAIN B:  CMDi ──▶ Webshell ──▶ Persist ──▶ Impact          │
│  CHAIN C:  SSRF ──▶ Enum ──▶ LFI ──▶ DNS Exfil              │
└──────────────────────────────────────────────────────────────┘
```

### ⛓️ Run All Scenarios (Full Kill-Chain)

```
 Recon  -->  CVE Init Access  -->  Web Exploit  -->  Brute Force
                                                    │
   Impact  <--  Exfil  <--  Post-Exploit  <--  CVE Priv Esc
```

`A` hotkey runs all 8 phases. `C` hotkey chains all 9 CVE exploits.

---

## 📁 Project Structure

```
bait-n-break/
├── run.sh                          🚀 Single entry point
├── setup.sh                        📦 Dependency installer
├── bait_n_break/
│   ├── shared/
│   │   ├── config.sh               ⚙️  Paths + port constants
│   │   ├── lib_ui.sh               🖥️  TUI helpers (whiptail/dialog)
│   │   └── lib_state.sh            💾 State persistence
│   ├── tui/
│   │   ├── ansi_tui.sh             🎨 ANSI TUI rendering engine
│   │   ├── main_menu.sh            🏠 Role selection menu
│   │   ├── victim_dashboard.sh     🎯 Victim live ANSI dashboard
│   │   ├── victim_dashboard_fallback.sh  ⬇️  Whiptail fallback
│   │   ├── attacker_console.sh     💥 Attacker ANSI TUI
│   │   └── attacker_console_fallback.sh  ⬇️  Whiptail fallback
│   ├── victim/
│   │   ├── lib_bait.sh             🍯 Bait file generator
│   │   ├── lib_webapp.sh           🐳 Docker compose wrapper
│   │   ├── lib_monitor.sh          📡 Access + incident monitor
│   │   ├── lib_malware_sim.sh      💣 Malware simulation
│   │   ├── lib_vuln_overview.sh    🧬 Static vulnerability overview
│   │   ├── lib_live_dashboard.sh   📊 Live data-gathering (ports, conns, vulns)
│   │   └── webapp/
│   │       ├── app.py              🐍 Flask vulnerable web app
│   │       ├── Dockerfile          🏗️  Webapp container build
│   │       ├── docker-compose.yml  🐳 All services orchestration
│   │       ├── requirements.txt    📦 Flask==3.0.3
│   │       └── cve-services/       🐳 Real CVE Docker services
│   │           ├── apache-2.4.49/  CVE-2021-41773
│   │           ├── shellshock/     CVE-2014-6271
│   │           ├── proftpd-1.3.5/  CVE-2015-3306
│   │           ├── webmin-1.890/   CVE-2019-15107
│   │           ├── tomcat-ghostcat/ CVE-2020-1938
│   │           └── polkit/         CVE-2021-4034
│   └── attacker/
│       ├── lib_results.sh          📊 Results tracking + CVE scoring
│       ├── lib_target.sh           🎯 Target IP/port config
│       ├── lib_recon.sh            🔍 Reconnaissance (nmap + /dev/tcp)
│       ├── lib_bruteforce.sh       🔓 SSH/FTP/HTTP brute force
│       ├── lib_web_exploit.sh      💉 SQLi / CMDi / Webshell / XSS
│       ├── lib_cve_exploits.sh     🧬 9 CVE exploit functions
│       ├── lib_crawler.sh          🕷️ Bait file crawler
│       ├── lib_malware_c2.sh       🦠 Malware + C2 simulation
│       ├── lib_post_exploit.sh     🔗 Post-exploit (LFI/SSRF/XXE/IDOR/chains)
│       └── wordlists/
│           └── common_paths.txt    📋 50 common web paths
└── .state/                         💾 Runtime state (gitignored)
```

---

## 🛡️ Safety

| ✅ Safe | ❌ Not Safe |
|:--------|:-----------|
| All credentials are **dummy** (`admin:admin123`, `root:toor`) | Never deploy outside isolated lab |
| All bait content is **inert** — fake AWS/GCP/Azure keys | Not for production use |
| Malware sim is **sandboxed** — confined to `ransomware_target/` | Not for attacking real targets |
| Vulnerable services run in **Docker containers** | Requires isolated network |

---

## 📋 Requirements

| 📦 Package | 📝 Notes |
|:-----------|:---------|
| **Docker** | + Compose (V2 plugin or legacy `docker-compose`) |
| **whiptail** | Or `dialog` — for fallback TUI |
| **bash** 4.x+ | Standard on Ubuntu/Kali |
| **tput** | From ncurses-base (pre-installed) |
| **hydra** *(opt)* | SSH/FTP brute force — fallback built-in |
| **sqlmap** *(opt)* | SQL injection — hand-rolled fallback |
| **nmap** *(opt)* | Port scanning — `/dev/tcp` fallback |
| **sshpass** *(opt)* | SSH login — hydra fallback |
| **python3** *(opt)* | Ghostcat AJP exploit — pre-installed on Kali |

> `setup.sh` installs all missing packages automatically.

---

## 📄 License

This project is for **educational purposes only**. Do not deploy outside an isolated lab environment.
