#!/usr/bin/env bash
# Core rendering engine - typewriter, fake_shell, http_result, progress bar, tool signatures, mission briefing

BNB_ENGINE_BLOCKED=0
BNB_ENGINE_PASSED=0
BNB_ENGINE_PAYLOAD_TOTAL=0

_engine_reset_tracker() {
    BNB_ENGINE_BLOCKED=0
    BNB_ENGINE_PASSED=0
    BNB_ENGINE_PAYLOAD_TOTAL=0
}

twi() {
    local text="$1"
    local delay_ms="${2:-30}"
    local delay_sec
    delay_sec="$(printf '%.2f' "$(awk "BEGIN {print $delay_ms/1000}")" 2>/dev/null || printf '0.03')"
    local i
    for ((i = 0; i < ${#text}; i++)); do
        printf '%s' "${text:$i:1}"
        sleep "$delay_sec" 2>/dev/null || sleep 0.03
    done
}

fake_shell() {
    local cmd="$1"
    local GREEN='\033[1;32m'
    local BOLD='\033[1m'
    local RESET='\033[0m'
    printf "${GREEN}root@kali:~#${RESET} ${BOLD}%s${RESET}\n" "$cmd"
    eval "$cmd" 2>/dev/null || true
}

phase_banner() {
    local phase_name="$1"
    local tactic_id="$2"
    local BLUE_BG='\033[44m'
    local WHITE_BOLD='\033[1;37m'
    local RESET='\033[0m'
    local line
    line="  ${phase_name}  [${tactic_id}]  "
    local width=${#line}
    local i
    printf '\n'
    for ((i = 0; i < width; i++)); do
        printf "${BLUE_BG} ${RESET}"
    done
    printf '\n'
    printf "${BLUE_BG}${WHITE_BOLD}%s${RESET}\n" "$line"
    for ((i = 0; i < width; i++)); do
        printf "${BLUE_BG} ${RESET}"
    done
    printf '\n\n'
}

http_result() {
    local http_code="$1"
    local payload_desc="$2"
    local GREEN='\033[1;32m'
    local RED='\033[1;31m'
    local YELLOW='\033[1;33m'
    local DIM='\033[1;30m'
    local RESET='\033[0m'

    BNB_ENGINE_PAYLOAD_TOTAL=$((BNB_ENGINE_PAYLOAD_TOTAL + 1))

    case "$http_code" in
        2*)
            BNB_ENGINE_PASSED=$((BNB_ENGINE_PASSED + 1))
            printf '\r  ${GREEN}%s${RESET}  %s  โ’  HTTP %s\n' "[+]" "$payload_desc" "$http_code"
            ;;
        403|406)
            BNB_ENGINE_BLOCKED=$((BNB_ENGINE_BLOCKED + 1))
            printf '\r  ${RED}%s${RESET}  %s  โ’  HTTP %s (blocked)\n' "[!]" "$payload_desc" "$http_code"
            ;;
        5*)
            printf '\r  ${YELLOW}%s${RESET}  %s  โ’  HTTP %s\n' "[?]" "$payload_desc" "$http_code"
            ;;
        *)
            printf '\r  ${DIM}%s${RESET}  %s  โ’  HTTP %s\n' "[.]" "$payload_desc" "$http_code"
            ;;
    esac
}

bar() {
    local current="$1"
    local total="$2"
    local width=20
    local pct filled empty i fill_str empty_str
    pct=$((current * 100 / total))
    filled=$((current * width / total))
    empty=$((width - filled))

    fill_str=""
    for ((i = 0; i < filled; i++)); do
        fill_str="${fill_str}#"
    done

    empty_str=""
    for ((i = 0; i < empty; i++)); do
        empty_str="${empty_str}-"
    done

    printf '\r  [%s%s] %d%%\n' "$fill_str" "$empty_str" "$pct"
}

tool_sig() {
    local tool="$1"
    case "$tool" in
        nmap_sV)
            printf '%s\n' "Mozilla/5.0 (compatible; Nmap Scripting Engine; https://nmap.org/book/nse.html)"
            ;;
        sqlmap)
            printf '%s\n' "sqlmap/1.8#stable (https://sqlmap.org)"
            ;;
        hydra_ssh)
            printf '%s\n' "Mozilla/5.0 (Hydra v9.5)"
            ;;
        gobuster)
            printf '%s\n' "gobuster/3.6"
            ;;
        nikto)
            printf '%s\n' "Mozilla/5.0 (Nikto/2.5.0)"
            ;;
        metasploit)
            printf '%s\n' "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)"
            ;;
        *)
            printf '%s\n' "curl/8.0"
            ;;
    esac
}

ops() {
    local level="$1"
    local GREEN='\033[1;32m'
    local YELLOW='\033[1;33m'
    local RED='\033[1;31m'
    local RESET='\033[0m'

    case "$level" in
        quiet)
            printf "${GREEN}[OPSEC: quiet]${RESET}\n"
            ;;
        medium)
            printf "${YELLOW}[OPSEC: medium]${RESET}\n"
            ;;
        loud)
            printf "${RED}[OPSEC: loud]${RESET}\n"
            ;;
        *)
            printf "${YELLOW}[OPSEC: medium]${RESET}\n"
            ;;
    esac
}

mission_brief() {
    local title="$1"
    local technique="$2"
    local tactic="$3"
    local ops_risk="$4"
    local DIM='\033[1;30m'
    local WHITE_BOLD='\033[1;37m'
    local RESET='\033[0m'
    local target_display="${TARGET_IP:-not set}:${TARGET_PORT:-8080}"

    printf '\n'
    printf '+------------------------------------------------+\n'
    printf '| %-46s |\n' "$title"
    printf '+------------------------------------------------+\n'
    printf '|  Technique : %-33s |\n' "$technique"
    printf '|  Tactic    : %-33s |\n' "$tactic"
    printf '|  Target    : %-33s |\n' "$target_display"
    printf '|  OPSEC Risk: %-33s |\n' "$ops_risk"
    printf '+------------------------------------------------+\n'
    printf '\n'
}

debrief_card() {
    local status="$1"
    local technique="$2"
    local ops_risk="$3"
    local DIM='\033[1;30m'
    local GREEN='\033[1;32m'
    local RED='\033[1;31m'
    local YELLOW='\033[1;33m'
    local RESET='\033[0m'
    local status_color

    case "$status" in
        SUCCESS|VULNERABLE) status_color="$GREEN" ;;
        FAILED)              status_color="$RED" ;;
        *)                   status_color="$YELLOW" ;;
    esac

    printf '\n'
    printf '================================================\n'
    printf '  %s -- COMPLETE\n' "${1}"
    printf '================================================\n'
    printf '  Status:     %b%s%b\n' "$status_color" "$status" "$RESET"
    [ -n "$technique" ] && printf '  Technique:  %s\n' "$technique"
    [ -n "$ops_risk" ] && printf '  OPSEC:      %s\n' "$ops_risk"
    printf '  Payloads:   %d tested\n' "${BNB_ENGINE_PAYLOAD_TOTAL}"
    printf '================================================\n'
    printf '\n'

    _engine_reset_tracker
}
