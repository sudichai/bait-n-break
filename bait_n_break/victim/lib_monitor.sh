#!/usr/bin/env bash
# Access & Incident Monitor: combines web app logs, auth.log, and a bait
# file access watcher into .state/incident_log.txt.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

monitor_watch_webapp() {
    ( cd "${BNB_WEBAPP_DIR}" && docker compose logs -f webapp ) 2>&1 | while IFS= read -r line; do
        state_incident_append "webapp" "$line"
    done &
}

monitor_watch_auth() {
    local authlog="/var/log/auth.log"
    if [ -f "$authlog" ]; then
        tail -F "$authlog" 2>/dev/null | while IFS= read -r line; do
            state_incident_append "auth" "$line"
        done &
    fi
}

monitor_watch_bait() {
    local paths=("${BNB_BAIT_BACKUPS_DIR}" "${BNB_BAIT_SECRETS_DIR}" "${BNB_BAIT_DECEPTION_DIR}")
    if command -v inotifywait >/dev/null 2>&1; then
        inotifywait -m -r -e access,open "${paths[@]}" 2>/dev/null | while IFS= read -r line; do
            state_incident_append "bait-access" "$line"
        done &
    else
        (
            while true; do
                for p in "${paths[@]}"; do
                    [ -d "$p" ] || continue
                    state_bait_marker_files_since "$p" | while IFS= read -r line; do
                        state_incident_append "bait-access" "$line"
                    done
                done
                state_bait_marker_touch
                sleep 5
            done
        ) &
        # Track the polling subshell's PID (in this same shell session) so
        # monitor_stop can kill it - pkill -f can't match it reliably since
        # it has no distinctive command-line string.
        BNB_MONITOR_BAIT_POLL_PID=$!
    fi
}

monitor_start() {
    monitor_watch_webapp
    monitor_watch_auth
    monitor_watch_bait
}

monitor_stop() {
    pkill -f "docker compose logs -f webapp" 2>/dev/null
    pkill -f "tail -F /var/log/auth.log" 2>/dev/null
    pkill -f "inotifywait -m -r" 2>/dev/null
    if [ -n "${BNB_MONITOR_BAIT_POLL_PID:-}" ]; then
        kill "${BNB_MONITOR_BAIT_POLL_PID}" 2>/dev/null
        unset BNB_MONITOR_BAIT_POLL_PID
    fi
    return 0
}

monitor_live_view() {
    tail -f "${BNB_INCIDENT_LOG}"
}
