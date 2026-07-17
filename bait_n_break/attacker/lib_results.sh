#!/usr/bin/env bash
# Enhanced results tracker with MITRE ATT&CK tags and TOTAL stat support.
# Pipe-delimited format: timestamp|module|status|ops_level|tactic|payload_stats|detail
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
RESET='\033[0m'
BOLD='\033[1m'

results_init() {
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        printf 'sep=|\n' > "${BNB_ATTACK_RESULTS}"
    elif ! grep -q '^sep=|' "${BNB_ATTACK_RESULTS}"; then
        local tmp_content
        tmp_content="$(cat "${BNB_ATTACK_RESULTS}" 2>/dev/null)"
        printf 'sep=|\n%s\n' "$tmp_content" > "${BNB_ATTACK_RESULTS}"
    fi
}

results_record() {
    local module="$1" status="$2" ops_level="$3" tactic="$4" payload_stats="$5" detail="$6"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    results_init
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$ts" "$module" "$status" "$ops_level" "$tactic" "$payload_stats" "$detail" >> "${BNB_ATTACK_RESULTS}"
}

results_record_simple() {
    local module="$1" status="$2" ops_level="$3" detail="$4"
    results_record "$module" "$status" "$ops_level" "" "" "$detail"
}

results_summary() {
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        return
    fi
    grep -v '^sep=|' "${BNB_ATTACK_RESULTS}"
}

results_clear() {
    printf 'sep=|\n' > "${BNB_ATTACK_RESULTS}"
}

results_count() {
    local field_number="${1:-3}"
    local value="${2:-VULNERABLE}"
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        printf '0\n'
        return
    fi
    local count
    count="$(grep -v '^sep=|' "${BNB_ATTACK_RESULTS}" | awk -F'|' -v f="$field_number" -v v="$value" '$f == v {c++} END {print c+0}')"
    printf '%s\n' "$count"
}

results_stats() {
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        echo "no results"
        return
    fi
    local total=0 vuln=0
    total="$(grep -v '^sep=|' "${BNB_ATTACK_RESULTS}" 2>/dev/null | wc -l)"
    vuln="$(grep -v '^sep=|' "${BNB_ATTACK_RESULTS}" 2>/dev/null | awk -F'|' '$3 ~ /VULNERABLE|SUCCESS/ {c++} END {print c+0}')"
    printf '%d/%d exploited' "$vuln" "$total"
}

results_status_for() {
    local module="$1"
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        return
    fi
    local status
    status="$(grep -v '^sep=|' "${BNB_ATTACK_RESULTS}" | awk -F'|' -v m="$module" '$2 == m {s=$3} END {print s}')"
    printf '%s' "$status"
}

results_is_vulnerable() {
    local module="$1"
    local status
    status="$(results_status_for "$module")"
    case "$status" in
        "VULNERABLE"|"SUCCESS") return 0 ;;
        *) return 1 ;;
    esac
}

results_short_summary() {
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        printf 'No attack results yet.\n'
        return
    fi

    printf '\n'
    printf '==============================================\n'
    printf '  ATTACK RESULTS SUMMARY\n'
    printf '==============================================\n'
    printf '\n'

    local modules=(
        "recon:Reconnaissance"
        "bruteforce_ssh:Brute Force (SSH)"
        "bruteforce_ftp:Brute Force (FTP)"
        "bruteforce_http:Brute Force (HTTP)"
        "exploit_sqli:SQL Injection"
        "exploit_command_injection:Command Injection"
        "exploit_webshell_deploy:Webshell Deploy"
        "exploit_xss_reflected:XSS PoC"
        "exploit_apache_41773:CVE-2021-41773"
        "exploit_shellshock_6271:CVE-2014-6271"
        "exploit_webmin_15107:CVE-2019-15107"
        "exploit_ghostcat_1938:CVE-2020-1938"
        "exploit_log4shell_pattern:Log4Shell Pattern"
        "exploit_spring4shell_pattern:Spring4Shell"
        "exploit_struts_upload_pattern:Struts2 Pattern"
        "exploit_polkit_4034:Polkit LPE"
        "crawler:Bait Crawler"
        "post_exploit:Post-Exploitation"
        "malware_c2:Malware/C2"
    )

    local total_vuln=0 total_success=0 total_failed=0 total_other=0
    local i=1
    local entry

    for entry in "${modules[@]}"; do
        local mod="${entry%%:*}"
        local name="${entry##*:}"
        local status
        status="$(grep -v '^sep=|' "${BNB_ATTACK_RESULTS}" | awk -F'|' -v m="$mod" '$2 == m {s=$3} END {print s}')"

        local waf_str=""
        local TOTAL
        TOTAL="$(grep -v '^sep=|' "${BNB_ATTACK_RESULTS}" | awk -F'|' -v m="$mod" '$2 == m {s=$6} END {print s}')"
        if [ -n "$TOTAL" ]; then
            waf_str="  TOTAL: $TOTAL"
        fi

        local color="$RESET"
        case "$status" in
            "VULNERABLE")
                color="$GREEN"
                total_vuln=$((total_vuln + 1))
                ;;
            "SUCCESS")
                color="$GREEN"
                total_success=$((total_success + 1))
                ;;
            "FAILED")
                color="$RED"
                total_failed=$((total_failed + 1))
                ;;
            *)
                color="$YELLOW"
                total_other=$((total_other + 1))
                ;;
        esac

        if [ -z "$status" ]; then
            printf '  %2d. %-28s %b[  --  ]%b%s\n' "$i" "$name" "$YELLOW" "$RESET" ""
        else
            printf '  %2d. %-28s %b[%-7s]%b%s\n' "$i" "$name" "$color" "$status" "$RESET" "$waf_str"
        fi

        i=$((i + 1))
    done

    printf '\n'
    printf '==============================================\n'
    printf '  Totals: '
    printf '%b%d VULNERABLE%b  |  ' "$GREEN" "$total_vuln" "$RESET"
    printf '%b%d SUCCESS%b  |  ' "$GREEN" "$total_success" "$RESET"
    printf '%b%d FAILED%b  |  ' "$RED" "$total_failed" "$RESET"
    printf '%b%d Other%b' "$YELLOW" "$total_other" "$RESET"
    printf '\n'
    local waf_summary
    waf_summary="$(results_stats)"
    printf '  TOTAL: %s\n' "$waf_summary"
    printf '==============================================\n'
    printf '\n'
}

results_cve_summary() {
    if [ ! -f "${BNB_ATTACK_RESULTS}" ]; then
        printf 'No attack results yet.\n'
        return
    fi

    printf '\n'
    printf '==============================================\n'
    printf '  CVE EXPLOIT RESULTS SUMMARY\n'
    printf '==============================================\n'

    local cve_count=0 cve_success=0
    local module status detail

    while IFS='|' read -r _ module status _ _ _ detail; do
        case "$module" in
            *CVE-*|*Log4Shell*|*Spring4Shell*|*Struts2*|*Polkit*)
                cve_count=$((cve_count + 1))
                case "$status" in
                    "VULNERABLE"|"SUCCESS")
                        printf '  %b[+VULN]%b %s | %s | %s\n' "$GREEN" "$RESET" "$module" "$status" "${detail:-}"
                        cve_success=$((cve_success + 1))
                        ;;
                    *)
                        printf '  %b[-----]%b %s | %s | %s\n' "$RED" "$RESET" "$module" "$status" "${detail:-}"
                        ;;
                esac
                ;;
        esac
    done < "${BNB_ATTACK_RESULTS}"

    printf '  CVE score: %b%d/%d exploited%b\n' "$GREEN" "$cve_success" "$cve_count" "$RESET"
    printf '\n'
}
