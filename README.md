# 🔐 bait-n-break

> **Self-contained cybersecurity training lab** — deploy intentionally vulnerable services, then attack them through a menu-driven TUI.

Built with pure Bash. Runs on stock Ubuntu and Kali. No Python/Node/venvs needed for the orchestration layer.

---

## 🚀 Quick Start

```bash
git clone https://github.com/sudichai/bait-n-break.git && cd bait-n-break && bash setup.sh && bash run.sh
```

> Do **not** use `sudo` with `git clone` — it will break permissions. `setup.sh` handles everything automatically including dpkg lock conflicts.

```
┌──────────────────────────┐
│       bait-n-break       │
│                          │
│  [1] Victim (Target)     │
│  [2] Attacker (Kali)     │
│  [3] Exit                │
└──────────────────────────┘
```

- **`[1] Victim`** — Deploy the vulnerable target node (web app + SSH/FTP decoys + bait files + monitor)
- **`[2] Attacker`** — Run exploit scripts against the target (recon → brute-force → web exploits → crawler → malware/C2)
- **`[3] Exit`** — Clean exit

---

## 🎯 What's Inside

### Victim (Target) Node

| Component | Details |
|-----------|---------|
| 🐍 **Vulnerable Web App** | Flask app with 13 endpoints exposing 8 vulnerability classes |
| 🔓 **SSH Decoy** | Port `2222`, credentials `admin:admin123` |
| 🔓 **FTP Decoy** | Port `2121`, credentials `admin:admin123` |
| 🍯 **Bait Files** | 7 decoy files — `.env`, `passwords.txt`, `shadow.bak`, `production_dump.sql`, `website_backup.tar.gz`, `payroll_2025.csv`, `employee_records.db` |
| 👁️ **Live Monitor** | Tails webapp logs + auth.log + bait file access in real-time |
| 💣 **Malware Sim** | EICAR test file, sandboxed ransomware demo, C2 beacon check |

### Vulnerabilities (Kill-Chain Mapped)

| # | Endpoint | Vulnerability | Phase |
|---|----------|--------------|-------|
| 1 | `/admin`, `/files/<area>/` | Exposed admin panel + directory listing | Recon |
| 2 | `/login` | SQL injection (auth bypass) | Initial Access |
| 3 | SSH port 2222 | Weak credentials (`admin:admin123`) | Initial Access |
| 4 | FTP port 2121 | Weak credentials (`admin:admin123`) | Initial Access |
| 5 | `/ping` | Command injection (`;id`) | Execution |
| 6 | `/upload` → `/shell/<file>` | Unrestricted upload → webshell | Execution/Persistence |
| 7 | `/search` | Reflected XSS | Collection |
| 8 | `/comments` | Stored XSS | Collection |
| 9 | `/c2/beacon` | Mock C2 beacon | C2 |
| 10 | `/admin/ransomware-demo` | Remote ransomware trigger | Impact |

### Attacker (Kali) Scenarios

| Scenario | Kill-Chain Phase | Tool |
|----------|-----------------|------|
| 🔍 Recon scan | Reconnaissance | `nmap` → `/dev/tcp` + banner grab |
| 🔑 SSH brute-force | Initial Access | `hydra` → `sshpass` |
| 🔑 FTP brute-force | Initial Access | `hydra` → `curl` |
| 🔑 HTTP login brute-force | Initial Access | `curl` |
| 💉 SQL injection | Initial Access | `sqlmap` → hand-rolled payload |
| ⚡ Command injection | Execution | `curl` |
| 🐚 Webshell deploy | Execution/Persistence | curl upload + execute |
| ✖️ XSS (reflected + stored) | Collection | `curl` |
| 🕷️ Bait file crawler | Collection | Wordlist-based path scanner |
| 📡 C2 beacon | C2 | `curl` |
| 🔒 Ransomware trigger | Impact | `POST /admin/ransomware-demo` |
| ⚡ **Run All Scenarios** | Recon → Impact | Full kill-chain automation |

---

## 📁 Project Structure

```
bait-n-break/
├── run.sh                              # Single entry point
├── setup.sh                            # Idempotent dependency installer
├── bait_n_break/
│   ├── shared/
│   │   ├── config.sh                   # Path constants, TARGET_IP/PORT
│   │   ├── lib_ui.sh                   # UI abstraction (whiptail → dialog → plain)
│   │   └── lib_state.sh               # Sole reader/writer of .state/*
│   ├── tui/
│   │   ├── main_menu.sh               # Role selection menu
│   │   ├── victim_dashboard.sh         # Victim submenu
│   │   └── attacker_console.sh         # Attacker submenu
│   ├── victim/
│   │   ├── lib_bait.sh                 # Bait file generator
│   │   ├── lib_webapp.sh               # Docker Compose wrapper
│   │   ├── lib_monitor.sh              # Log + file access monitor
│   │   ├── lib_malware_sim.sh          # EICAR, ransomware, C2 sim
│   │   └── webapp/
│   │       ├── app.py                  # Flask app (vulnerable by design)
│   │       ├── Dockerfile
│   │       ├── docker-compose.yml      # webapp + SSH decoy + FTP decoy
│   │       └── requirements.txt
│   └── attacker/
│       ├── lib_results.sh              # Attack results tracker
│       ├── lib_target.sh               # Target IP/port config
│       ├── lib_recon.sh                # Port scan + banner grab
│       ├── lib_bruteforce.sh           # SSH/FTP/HTTP brute-force
│       ├── lib_web_exploit.sh          # SQLi, CMDi, webshell, XSS
│       ├── lib_crawler.sh              # Leaked file crawler
│       ├── lib_malware_c2.sh           # C2 beacon + ransomware trigger
│       └── wordlists/
│           └── common_paths.txt        # Crawler wordlist
├── docs/
│   └── superpowers/
│       ├── plans/                      # Implementation plans
│       └── specs/                      # Design specifications
└── .state/                             # Runtime state (gitignored)
```

---

## 🛡️ Safety

- **All credentials are dummy** — `admin:admin123`, `root:toor`, fake AWS keys, etc.
- **All bait content is inert** — no real secrets, safe to leave on disk
- **Malware sim is sandboxed** — ransomware demo confined to `ransomware_target/`
- **Docker isolation** — vulnerable services run in containers, not on bare host
- **Lab-only** — never deploy outside an isolated training network

---

## 📋 Requirements

- **OS:** Ubuntu, Kali, or Debian
- **Dependencies:** Docker, Docker Compose, `whiptail` (or `dialog`)
- **Optional (attacker):** `hydra`, `sqlmap`, `nmap`, `sshpass` — installed best-effort by `setup.sh`, but all attack scripts have hand-rolled fallbacks

---

## 🔧 Development

```bash
# All runtime state lives under .state/
.state/
├── victim_status            # "deployed" or "not_deployed"
├── bait_manifest.txt        # List of generated bait files
├── incident_log.txt         # Timestamped security events
├── bait_access.log          # Bait file access tracker
├── attack_results.txt       # Attacker scenario results
├── attacker_target          # Persisted TARGET_IP:TARGET_PORT
└── bait/                    # Generated bait files
    ├── backups/             # passwords.txt, shadow.bak, etc.
    ├── secrets/             # payroll.csv, employee_records.db
    └── deception/           # .env, eicar_test.txt, ransomware_target/
```

- Every library file is a pure function collection, sourced not executed
- `shared/lib_state.sh` and `attacker/lib_results.sh` are the sole readers/writers of their respective `.state/*` files — other modules call their functions
- Code comments in English

---

## 📄 License

This project is for educational purposes only. Do not deploy outside an isolated lab environment.
