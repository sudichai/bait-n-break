#!/usr/bin/env bash
# Dynamic vulnerability overview: checks actual live ports, containers,
# and bait files, then displays a kill-chain-organized summary.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

victim_vuln_overview() {
    echo ""
    echo "=============================================="
    echo "  LIVE VULNERABILITY OVERVIEW"
    echo "  Host: $(hostname 2>/dev/null || echo unknown)"
    echo "=============================================="
    echo ""

    local ports8080=0 ports2222=0 ports2121=0 ports3306=0
    local found=""

    echo "[*] Scanning active ports..."
    echo ""

    if command -v ss >/dev/null 2>&1; then
        ss -tulpn 2>/dev/null | grep -q ':8080\b' && ports8080=1
        ss -tulpn 2>/dev/null | grep -q ':2222\b' && ports2222=1
        ss -tulpn 2>/dev/null | grep -q ':2121\b' && ports2121=1
        ss -tulpn 2>/dev/null | grep -q ':3306\b' && ports3306=1
    else
        (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null && ports8080=1; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
        (exec 3<>/dev/tcp/127.0.0.1/2222) 2>/dev/null && ports2222=1; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
        (exec 3<>/dev/tcp/127.0.0.1/2121) 2>/dev/null && ports2121=1; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
        (exec 3<>/dev/tcp/127.0.0.1/3306) 2>/dev/null && ports3306=1; exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi

    local bait_count=0
    bait_count="$(find "${BNB_STATE_DIR}/bait" -type f 2>/dev/null | wc -l)"
    local vuln_count=0

    echo "=== ACTIVE SERVICES ==="
    echo ""
    [ "$ports8080" -eq 1 ] && echo "  [ACTIVE] Port 8080/tcp -> HTTP  (webapp)        Flask + 50 endpoints"
    [ "$ports2222" -eq 1 ] && echo "  [ACTIVE] Port 2222/tcp -> SSH   (ssh-decoy)     Brute-force target"
    [ "$ports2121" -eq 1 ] && echo "  [ACTIVE] Port 2121/tcp -> FTP   (ftp-decoy)     Brute-force target"
    [ "$ports3306" -eq 1 ] && echo "  [ACTIVE] Port 3306/tcp -> MySQL (db)            Weak root password"
    echo ""

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [1] RECONNAISSANCE ==="
        echo "  /admin          Exposed admin panel"
        echo "  /env            Environment variable dump"
        echo "  /debug          Debug console (Flask DEBUG=True)"
        echo "  /robots.txt     Disallowed paths leak"
        echo "  /files/*/       Directory listing (no index)"
        vuln_count=$((vuln_count + 5))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ] || [ "$ports2222" -eq 1 ] || [ "$ports2121" -eq 1 ] || [ "$ports3306" -eq 1 ]; then
        echo "=== [2] INITIAL ACCESS ==="
        [ "$ports8080" -eq 1 ] && echo "  /login          SQL Injection (auth bypass)"
        [ "$ports8080" -eq 1 ] && echo "  /upload         Unrestricted file upload -> webshell"
        [ "$ports2222" -eq 1 ] && echo "  SSH:2222        Weak credentials (admin:admin123)"
        [ "$ports2121" -eq 1 ] && echo "  FTP:2121        Weak credentials (admin:admin123)"
        [ "$ports3306" -eq 1 ] && echo "  MySQL:3306      Weak root (root:root)"
        [ "$ports3306" -eq 1 ] && echo "  MySQL:3306      Weak user (webapp:webapp123)"
        vuln_count=$((vuln_count + 6))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [3] EXECUTION ==="
        echo "  /ping           Command Injection (;id, ;whoami)"
        echo "  /read           LFI - Local File Inclusion"
        echo "  /fetch          SSRF - Server-Side Request Forgery"
        echo "  /parse          XXE - XML External Entity"
        echo "  /pickle         Insecure Deserialization (RCE)"
        echo "  /redirect       Open Redirect"
        echo "  /download       Arbitrary File Download"
        echo "  /api/search     HTTP Parameter Pollution"
        vuln_count=$((vuln_count + 8))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [4] PRIVILEGE ESCALATION ==="
        echo "  SUID:           /usr/bin/find, /usr/bin/awk, /usr/bin/curl"
        echo "  Sudo:           victim can run find/curl/wget as root"
        echo "  Docker:         /var/run/docker.sock mounted (escape to host)"
        echo "  /docker         Docker command execution"
        vuln_count=$((vuln_count + 4))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [5] PERSISTENCE ==="
        echo "  /persist/ssh-key    SSH authorized_keys injection"
        echo "  /persist/cron       Cron job backdoor"
        vuln_count=$((vuln_count + 2))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [6] CREDENTIAL ACCESS ==="
        echo "  LFI -> /etc/passwd, /etc/shadow, ~/.ssh/id_rsa"
        echo "  IDOR -> /users/{id} exposes SSN, role, password"
        echo "  IDOR -> /employees exposes salary, SSN, dept"
        echo "  /env     -> environment variable leak"
        echo "  /api/error -> stack trace leak (info disclosure)"
        vuln_count=$((vuln_count + 5))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [7] COLLECTION ==="
        echo "  /files/backups/*       passwords.txt, shadow.bak, SQL dump, tarball"
        echo "  /files/secrets/*       payroll CSV, employee DB, SSH keys, browser creds"
        echo "  /files/deception/*     .env, EICAR test file"
        echo "  /search (XSS)          Reflected Cross-Site Scripting"
        echo "  /comments (XSS)        Stored Cross-Site Scripting"
        echo "  /api/auth (JWT)        Token tampering (none algorithm)"
        vuln_count=$((vuln_count + 6))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [8] WEB APPLICATION VULNS ==="
        echo "  /admin/transfer    CSRF (no CSRF token)"
        echo "  /admin/password    CSRF (password change)"
        echo "  /api/profile       Mass Assignment (role/SSN)"
        echo "  /api/coupon        Race Condition (double use)"
        echo "  /reset             Weak Crypto (predictable token)"
        echo "  ALL endpoints      Missing CSP, HSTS, X-Frame-Options"
        echo "  /login             Session Fixation (?sid=...)"
        echo "  ALL API            CORS Misconfiguration (*)"
        echo "  /login             No Rate Limiting"
        vuln_count=$((vuln_count + 9))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [9] EXFILTRATION ==="
        echo "  /exfil/dns        DNS tunneling"
        echo "  /exfil/http       HTTP data exfiltration"
        vuln_count=$((vuln_count + 2))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [10] C2 ==="
        echo "  /c2/beacon        C2 beacon + remote cmd execution"
        vuln_count=$((vuln_count + 1))
        echo ""
    fi

    if [ "$ports8080" -eq 1 ]; then
        echo "=== [11] IMPACT ==="
        echo "  /admin/ransomware-demo    Remote ransomware trigger"
        echo "  /admin/deface             Website defacement"
        echo "  /admin/wipe-db            Database destruction"
        echo "  /admin/clear-logs         Log clearing (anti-forensics)"
        echo "  /api/coupon               Denial of Service (race abuse)"
        vuln_count=$((vuln_count + 5))
        echo ""
    fi

    echo "=== BAIT FILES ==="
    echo "  Total bait files deployed: ${bait_count}"
    echo "  Locations:"
    echo "    backups/   - passwords, shadow, SQL dump, tarball"
    echo "    secrets/   - payroll, employee DB, SSH keys, browser, bash history"
    echo "    secrets/   - AWS creds, Azure tokens, GCP SA, Docker config"
    echo "    secrets/   - kubeconfig, PGP key, KeePass DB"
    echo "    secrets/   - CI/CD files (.gitlab-ci.yml, Jenkinsfile, .npmrc)"
    echo "    deception/ - .env, EICAR test file"
    echo ""

    local active_svcs=0
    [ "$ports8080" -eq 1 ] && active_svcs=$((active_svcs + 1))
    [ "$ports2222" -eq 1 ] && active_svcs=$((active_svcs + 1))
    [ "$ports2121" -eq 1 ] && active_svcs=$((active_svcs + 1))
    [ "$ports3306" -eq 1 ] && active_svcs=$((active_svcs + 1))

    echo "=============================================="
    echo "  ${vuln_count} vulnerabilities | ${active_svcs} services active | ${bait_count} bait files"
    echo "=============================================="
    echo ""
    echo "Attack chains available:"
    echo "  Chain A: SQLi -> Cred Dump -> SSH -> Docker Escape"
    echo "  Chain B: CMDi  -> Webshell -> Persistence -> Impact"
    echo "  Chain C: SSRF  -> Internal Enum -> DB Exploit -> Exfil"
    echo ""
}
