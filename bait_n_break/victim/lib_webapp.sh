#!/usr/bin/env bash
# docker compose wrapper for the vulnerable web app + decoy services.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

_webapp_docker() {
    local -a cmd=()
    if ! docker ps >/dev/null 2>&1; then
        cmd=(sudo)
    fi

    if [ "$1" = "compose" ]; then
        shift
        if docker compose version >/dev/null 2>&1; then
            cmd+=(docker compose)
        elif command -v docker-compose >/dev/null 2>&1; then
            cmd+=(docker-compose)
        else
            echo "ERROR: Neither docker compose nor docker-compose is available" >&2
            return 1
        fi
        "${cmd[@]}" "$@"
    else
        cmd+=(docker)
        "${cmd[@]}" "$@"
    fi
}

webapp_compose_file() {
    echo "${BNB_WEBAPP_DIR}/docker-compose.yml"
}

webapp_up() {
    ( cd "${BNB_WEBAPP_DIR}" && _webapp_docker compose -f "$(webapp_compose_file)" up -d --build )
}

webapp_down() {
    ( cd "${BNB_WEBAPP_DIR}" && _webapp_docker compose -f "$(webapp_compose_file)" down -v )
}

webapp_status() {
    ( cd "${BNB_WEBAPP_DIR}" && _webapp_docker compose -f "$(webapp_compose_file)" ps )
}

webapp_ports() {
    ss -tulpn 2>/dev/null | grep -E ':(8080|8081|8082|8083|2121|2122|2222|10000|8009)\b' || echo "No matching ports found"
}
