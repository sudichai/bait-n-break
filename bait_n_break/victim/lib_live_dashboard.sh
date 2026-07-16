#!/usr/bin/env bash
# Live data-gathering functions for the victim ANSI TUI dashboard.
# Provides port probing, vuln counting, incident reading.
# Sourced, not executed.

LIVE_SERVICES=(
    "webapp:8080"
    "ssh-decoy:2222"
    "ftp-decoy:2121"
    "db:3306"
    "apache-41773:${BNB_CVE_APACHE_41773_PORT:-8081}"
    "shellshock:${BNB_CVE_SHELLSHOCK_PORT:-8082}"
    "webmin:${BNB_CVE_WEBMIN_PORT:-10000}"
    "tomcat:${BNB_CVE_TOMCAT_HTTP_PORT:-8083}"
)

live_probe_services() {
    local -n result="$1" 2>/dev/null || return 1
    result=()

    for svc_entry in "${LIVE_SERVICES[@]}"; do
        local name="${svc_entry%%:*}"
        local port="${svc_entry##*:}"
        local status="DOWN"
        local conns="0"

        if ss -tulpn 2>/dev/null | grep -q ":${port}\b"; then
            status="UP"
        elif (exec 3<>/dev/tcp/127.0.0.1/${port}) 2>/dev/null; then
            status="UP"
            exec 3<&- 2>/dev/null
            exec 3>&- 2>/dev/null
        fi

        if [ "$status" = "UP" ]; then
            conns="$(ss -tn state established sport = ":${port}" 2>/dev/null | wc -l)"
            conns=$((conns - 1))
            [ "$conns" -lt 0 ] && conns=0
        fi

        result+=("${name}|${port}|${status}|${conns}")
    done
}

live_count_vulns() {
    local webapp_up=0
    local cve41773_up=0
    local cve6271_up=0
    local cve15107_up=0
    local cve1938_up=0

    if ss -tulpn 2>/dev/null | grep -q ':8080\b' || (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null; then
        webapp_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_APACHE_41773_PORT:-8081}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_APACHE_41773_PORT:-8081}) 2>/dev/null; then
        cve41773_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_SHELLSHOCK_PORT:-8082}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_SHELLSHOCK_PORT:-8082}) 2>/dev/null; then
        cve6271_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_WEBMIN_PORT:-10000}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_WEBMIN_PORT:-10000}) 2>/dev/null; then
        cve15107_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    if ss -tulpn 2>/dev/null | grep -q ":${BNB_CVE_TOMCAT_HTTP_PORT:-8083}\b" || (exec 3<>/dev/tcp/127.0.0.1/${BNB_CVE_TOMCAT_HTTP_PORT:-8083}) 2>/dev/null; then
        cve1938_up=1
        exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
    fi

    printf '%s\n' \
        "RECON|5|$webapp_up" \
        "INIT ACCESS|6|$webapp_up" \
        "EXECUTION|8|$webapp_up" \
        "PRIV ESC|4|$webapp_up" \
        "PERSIST|2|$webapp_up" \
        "CRED|5|$webapp_up" \
        "COLLECT|6|$webapp_up" \
        "WEB VULNS|9|$webapp_up" \
        "EXFIL|2|$webapp_up" \
        "C2|1|$webapp_up" \
        "IMPACT|5|$webapp_up" \
        "CVE-41773|1|$cve41773_up" \
        "CVE-6271|1|$cve6271_up" \
        "CVE-15107|1|$cve15107_up" \
        "CVE-1938|1|$cve1938_up" \
        "FLASK CVE|3|$webapp_up"
}

live_tail_incidents() {
    local lines="${1:-15}"
    if [ -f "${BNB_INCIDENT_LOG}" ] && [ -s "${BNB_INCIDENT_LOG}" ]; then
        tail -n "$lines" "${BNB_INCIDENT_LOG}" 2>/dev/null
    else
        echo "No attacker activity detected yet"
    fi
}

live_get_bait_count() {
    find "${BNB_STATE_DIR}/bait" -type f 2>/dev/null | wc -l
}

live_get_hostname() {
    hostname 2>/dev/null || echo "victim-lab"
}

live_get_service_count() {
    local -a svc_data
    live_probe_services svc_data
    local count=0
    for entry in "${svc_data[@]}"; do
        local status="${entry##*|}"
        status="${status%%|*}"
        [ "$status" = "UP" ] && count=$((count + 1))
    done
    echo "$count"
}
