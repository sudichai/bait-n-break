#!/usr/bin/env bash
# docker compose wrapper for the vulnerable web app + decoy services.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

_webapp_docker() {
    if docker ps >/dev/null 2>&1; then
        docker "$@"
    else
        sudo docker "$@"
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
    ss -tulpn 2>/dev/null | grep -E ':(8080|2222|2121)\b' || echo "No matching ports found"
}
