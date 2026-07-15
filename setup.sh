#!/usr/bin/env bash
# Idempotent dependency installer. Detects OS, installs only what's missing.
# Does not deploy services - that is the TUI's "Deploy" action.

set -uo pipefail

log() { echo "[setup] $*"; }

wait_for_apt() {
    local waited=0
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        local holder
        holder="$(sudo fuser /var/lib/dpkg/lock-frontend 2>/dev/null | tr -d ' ') $(sudo fuser /var/lib/apt/lists/lock 2>/dev/null | tr -d ' ')"
        holder="$(echo "$holder" | tr -d ' ')"
        if [ "$waited" -ge 120 ]; then
            log "dpkg lock still held after 120s; giving up"
            log "lock holder PID(s): ${holder:-unknown}"
            log "You can wait or kill the holder: sudo kill ${holder:-}"
            return 1
        fi
        log "dpkg lock held by PID(s): ${holder:-unknown} — waiting (${waited}s/120s)..."
        sleep 5
        waited=$((waited + 5))
    done
    return 0
}

apt_install() {
    wait_for_apt || return 1
    sudo apt-get install -y "$@"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

ensure_pkg() {
    local pkg="$1"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        log "$pkg already installed"
    else
        log "installing $pkg"
        apt_install "$pkg"
    fi
}

main() {
    local os
    os="$(detect_os)"
    case "$os" in
        ubuntu|kali|debian)
            wait_for_apt
            sudo apt-get update
            ensure_pkg whiptail
            ensure_pkg inotify-tools
            ensure_pkg iproute2
            ensure_pkg hydra
            ensure_pkg sqlmap
            ensure_pkg nmap
            if ! command -v docker >/dev/null 2>&1; then
                log "installing docker.io"
                apt_install docker.io docker-compose-v2
                sudo systemctl enable --now docker || true
            else
                log "docker already installed"
            fi

            if ! docker compose version >/dev/null 2>&1; then
                log "docker compose plugin not found, trying legacy docker-compose"
                apt_install docker-compose || log "docker-compose also unavailable; only docker engine is installed"
            fi
            ;;
        *)
            log "Unsupported or undetected OS ($os). Please install docker, whiptail, inotify-tools, iproute2 manually."
            ;;
    esac
    log "Setup complete. Run ./run.sh to start bait-n-break."
}

main "$@"
