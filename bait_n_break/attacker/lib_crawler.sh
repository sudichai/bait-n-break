#!/usr/bin/env bash
# Leaked-file crawler: iterates a wordlist of candidate paths against the
# target, and for any directory-listing page it finds, also enumerates and
# reports the files listed inside it. Real bait paths are mixed among
# plausible decoy paths in the wordlist, so this has to actually search.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

crawl_leaked_files() {
    target_ensure_set || { echo "[crawler] No target set."; return 1; }
    local base="http://${TARGET_IP}:${TARGET_PORT}"
    local wordlist="${BNB_ROOT}/bait_n_break/attacker/wordlists/common_paths.txt"
    local body_file found=0
    body_file="$(mktemp)"
    echo "=== Crawling ${base} for leaked files ==="
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        local url="${base}${path}"
        local code
        code="$(curl -s -o "$body_file" -w '%{http_code}' "$url")"
        if [ "$code" = "200" ]; then
            echo "[FOUND] ${path}"
            found=$((found + 1))
            if [[ "$path" == /files/*/ ]]; then
                grep -oE "href='[^']+'" "$body_file" | sed -E "s/^href='//;s/'\$//" | while IFS= read -r link; do
                    echo "    -> ${base}${link}"
                done
            fi
        fi
    done < "$wordlist"
    rm -f "$body_file"
    echo "=== Crawl complete: ${found} path(s) found ==="
    if [ "$found" -gt 0 ]; then
        results_record "crawler" "VULNERABLE" "quiet" "${found} leaked path(s) found via wordlist"
    else
        results_record "crawler" "FAILED" "quiet" "no leaked paths found via wordlist"
    fi
}
