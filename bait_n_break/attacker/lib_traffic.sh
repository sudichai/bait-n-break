#!/usr/bin/env bash
# HTTP traffic factory — realistic tool-fingerprinted HTTP requests.
# Depends on: lib_engine.sh (tool_sig)
# Sourced, not executed.

traffic_curl() {
    local method="${1:-GET}"
    local url="$2"
    local data="$3"
    local extra_headers="$4"
    local tool="${5:-curl}"

    local ua
    ua="$(tool_sig "$tool")"

    local curl_args=(-s -w $'\n%{http_code}' -X "$method" -A "$ua" --connect-timeout 10)

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    if [[ -n "$extra_headers" ]]; then
        curl_args+=(-H "$extra_headers")
    fi

    curl_args+=("$url")

    curl "${curl_args[@]}"
}

traffic_extract_code() {
    printf '%s\n' "$1" | tail -1
}

traffic_extract_body() {
    printf '%s\n' "$1" | sed '$d'
}

traffic_json_post() {
    local url="$1"
    local json_data="$2"
    local tool="${3:-curl}"

    local ua
    ua="$(tool_sig "$tool")"

    curl -s -w $'\n%{http_code}' -X POST \
        -A "$ua" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -d "$json_data" \
        --connect-timeout 10 \
        "$url"
}

traffic_form_post() {
    local url="$1"
    local form_data="$2"
    local tool="${3:-curl}"

    local ua
    ua="$(tool_sig "$tool")"

    curl -s -w $'\n%{http_code}' -X POST \
        -A "$ua" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: text/html,*/*" \
        -d "$form_data" \
        --connect-timeout 10 \
        "$url"
}

traffic_nmap_scan() {
    local host="$1"
    local ports="${2:-1-10000}"

    if command -v nmap >/dev/null 2>&1; then
        nmap -sV -sC --min-rate 200 --max-rate 500 -T4 -p "$ports" "$host"
    else
        printf '[!] nmap not installed — run setup.sh to install\n'
    fi
}
