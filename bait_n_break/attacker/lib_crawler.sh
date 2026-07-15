#!/usr/bin/env bash
# Leaked-file crawler: iterates a wordlist of candidate paths against the
# target, and for any directory-listing page it finds, also enumerates and
# reports the files listed inside it. Adds realistic request pacing.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

crawl_leaked_files() {
    target_ensure_set || { echo "[crawler] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    local wordlist="${BNB_ROOT}/bait_n_break/attacker/wordlists/common_paths.txt"
    local body_file found=0 scanned=0 total
    total="$(wc -l < "$wordlist")"
    body_file="$(mktemp)"
    echo ""
    echo "=============================================="
    echo "  BAIT FILE CRAWLER: ${base}"
    echo "  Wordlist: ${total} paths"
    echo "=============================================="
    echo ""
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        scanned=$((scanned + 1))
        local url="${base}${path}"
        local code
        printf "    [%3d/%3d] %s " "$scanned" "$total" "$path"
        code="$(curl -s -o "$body_file" -w '%{http_code}' --connect-timeout 3 "$url")"
        if [ "$code" = "200" ]; then
            echo "-> FOUND (${code})"
            found=$((found + 1))
            if [[ "$path" == /files/*/ ]]; then
                grep -oE "href='[^']+'" "$body_file" | sed -E "s/^href='//;s/'\$//" | while IFS= read -r link; do
                    echo "        -> ${base}${link}"
                done
            fi
        else
            echo "-> ${code}"
        fi
        sleep 0.3
    done < "$wordlist"
    rm -f "$body_file"
    echo ""
    echo "=============================================="
    echo "  CRAWL COMPLETE: ${found} path(s) found out of ${scanned} scanned"
    echo "=============================================="
    if [ "$found" -gt 0 ]; then
        results_record "crawler" "VULNERABLE" "quiet" "${found} leaked path(s) found via wordlist"
    else
        results_record "crawler" "FAILED" "quiet" "no leaked paths found via wordlist"
    fi
}
