#!/usr/bin/env bash
# Idempotent dependency installer. Detects OS, installs only what's missing.
# Does not deploy services - that is the TUI's "Deploy" action.

set -uo pipefail

log() { echo "[setup] $*"; }

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
        sudo apt-get install -y "$pkg"
    fi
}

main() {
    local os
    os="$(detect_os)"
    case "$os" in
        ubuntu|kali|debian)
            sudo apt-get update
            ensure_pkg whiptail
            ensure_pkg inotify-tools
            ensure_pkg iproute2
            ensure_pkg hydra
            ensure_pkg sqlmap
            ensure_pkg nmap
            if ! command -v docker >/dev/null 2>&1; then
                log "installing docker.io"
                sudo apt-get install -y docker.io docker-compose-v2
                sudo systemctl enable --now docker || true
            else
                log "docker already installed"
            fi

            if ! docker compose version >/dev/null 2>&1; then
                log "docker compose plugin not found, trying legacy docker-compose"
                sudo apt-get install -y docker-compose || log "docker-compose also unavailable; only docker engine is installed"
            fi
            ;;
        *)
            log "Unsupported or undetected OS ($os). Please install docker, whiptail, inotify-tools, iproute2 manually."
            ;;
    esac
    log "Setup complete. Run ./run.sh to start bait-n-break."
}

main "$@"
