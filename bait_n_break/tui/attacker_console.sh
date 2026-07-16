#!/usr/bin/env bash
# Attacker console — clean vector list, full-screen execute during attacks.
# Falls back to whiptail if terminal too small.
# Sourced, not executed.

attacker_console() {
    source "${BNB_ROOT}/bait_n_break/attacker/lib_target.sh"

    # --- IP Target Input ---
    if [ -z "${TARGET_IP:-}" ]; then
        local saved; saved="$(state_get_target 2>/dev/null)"
        [ -n "$saved" ] && { TARGET_IP="$(echo "$saved" | cut -d' ' -f1)"; TARGET_PORT="$(echo "$saved" | cut -d' ' -f2)"; }
    fi
    if [ -z "${TARGET_IP:-}" ]; then
        clear; echo ""; echo "  +-------------------------------------------+"
        echo "  |         bait-n-break Attacker Console      |"
        echo "  +-------------------------------------------+"; echo ""
        while true; do
            printf "  Enter Target IP: "; read -r target_ip
            if target_is_valid_ip "$target_ip"; then
                TARGET_IP="$target_ip"; TARGET_PORT="${TARGET_PORT:-8080}"
                state_set_target "$TARGET_IP" "${TARGET_PORT:-8080}"; break
            fi
            echo "  Invalid IPv4 address."; echo ""
        done; echo ""; echo "  Target set: ${TARGET_IP}:${TARGET_PORT:-8080}"; sleep 1
    fi

    # --- TUI Init ---
    source "${BNB_ROOT}/bait_n_break/tui/ansi_tui.sh"
    if ! tui_init; then
        source "${BNB_ROOT}/bait_n_break/tui/attacker_console_fallback.sh"; _attacker_console_fallback; return
    fi
    trap 'tui_cleanup' EXIT INT

    source "${BNB_ROOT}/bait_n_break/attacker/lib_recon.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_bruteforce.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_web_exploit.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_cve_exploits.sh" 2>/dev/null
    source "${BNB_ROOT}/bait_n_break/attacker/lib_crawler.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_post_exploit.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_malware_c2.sh"
    source "${BNB_ROOT}/bait_n_break/attacker/lib_results.sh"

    crawl_all() { crawl_leaked_files 2>/dev/null; }
    malware_c2_all() { c2_beacon_check 2>/dev/null; ransomware_trigger 2>/dev/null; }
    post_exploit_all() { exploit_lfi 2>/dev/null; exploit_ssrf 2>/dev/null; exploit_xxe 2>/dev/null; exploit_idor 2>/dev/null; exploit_pickle_deser 2>/dev/null; exploit_docker_escape 2>/dev/null; exploit_persist_ssh 2>/dev/null; exploit_persist_cron 2>/dev/null; exploit_cred_harvest 2>/dev/null; exploit_dns_exfil 2>/dev/null; }

    TUI_LEFT_TITLE="ATTACK VECTORS"; TUI_HEADER_TITLE="bait-n-break"; TUI_CURSOR_VECTOR=0

    local vectors=( "Reconnaissance (nmap)" "Brute Force (SSH/FTP/HTTP)" "SQL Injection" "Command Injection" "Webshell Deploy" "XSS PoC" "CVE-2021-41773 Apache" "CVE-2014-6271 Shellshock" "CVE-2019-15107 Webmin" "CVE-2020-1938 Ghostcat" "Log4Shell Pattern" "Spring4Shell Pattern" "Struts2 Upload" "CVE-2021-4034 Polkit" "Crawler / Bait Exfil" "Post-Exploitation" "Malware / C2" )
    local VEC_COUNT="${#vectors[@]}"

    _draw_vectors() {
        TUI_PANEL_LEFT=()
        local i; for ((i=0; i<VEC_COUNT; i++)); do
            local n; printf -v n '%2d' $((i+1))
            TUI_PANEL_LEFT+=("  ${n}. ${vectors[$i]}")
        done
        TUI_PANEL_LEFT+=(""); TUI_PANEL_LEFT+=("  [A] Run All Scenarios"); TUI_PANEL_LEFT+=("  [C] Run All CVEs")
        TUI_PANEL_LEFT+=(""); TUI_PANEL_LEFT+=("  [H] Back to Main Menu")
    }

    _hl() {
        local row="$1" y=$((5+row)) x=1
        local panel_w=$(( (TUI_TERM_W-2)/3 )); local line="${TUI_PANEL_LEFT[$row]:-}"
        tput cup "$y" "$x"; printf '\033[7m %-*s \033[0m' "$((panel_w-2))" "${line:0:$((panel_w-2))}"
    }

    _exec() {
        local title="$1"; shift
        clear
        local y=0; tput cup 0 0; printf '\033[7m%-*s\033[0m' "$TUI_TERM_W" "  [bait-n-break]  Attacking: ${title}  Target: ${TARGET_IP}"
        tput cup 2 0; echo "----------------------------------------"
        local line_nr=3
        while IFS= read -r line; do
            tput cup "$line_nr" 0; printf ' %s' "${line:0:$((TUI_TERM_W-2))}"; line_nr=$((line_nr+1))
            [ "$line_nr" -ge "$((TUI_TERM_H-2))" ] && { line_nr=3; tput cup 3 0; printf '%*s' "$TUI_TERM_W" ""; }
        done < <("$@" 2>&1)
        tput cup $((TUI_TERM_H-2)) 0; printf '\033[7m%-*s\033[0m' "$TUI_TERM_W" "  Press any key to continue..."
        read -r -n1 -s _
        clear; _draw_vectors; tui_draw_header; tui_draw_target_bar
        tui_draw_panel 0 4 "$(( (TUI_TERM_W-2)/3 ))" "$((TUI_TERM_H-5))" "$TUI_LEFT_TITLE" TUI_PANEL_LEFT
        tui_draw_footer; _hl "$TUI_CURSOR_VECTOR"
    }

    _exec_one() { case "$1" in
        1) recon_scan ;;  2) bruteforce_ssh 2>/dev/null; bruteforce_ftp 2>/dev/null; bruteforce_http 2>/dev/null ;;
        3) exploit_sqli ;;  4) exploit_command_injection ;;  5) exploit_webshell_deploy ;;  6) exploit_xss_poc ;;
        7) exploit_apache_41773 2>/dev/null || true ;;  8) exploit_shellshock_6271 2>/dev/null || true ;;
        9) exploit_webmin_15107 2>/dev/null || true ;;  10) exploit_ghostcat_1938 2>/dev/null || true ;;
        11) exploit_log4shell_pattern 2>/dev/null || true ;;  12) exploit_spring4shell_pattern 2>/dev/null || true ;;
        13) exploit_struts_upload_pattern 2>/dev/null || true ;;  14) exploit_polkit_4034 2>/dev/null || true ;;
        15) crawl_all 2>/dev/null || true ;;  16) post_exploit_all 2>/dev/null || true ;;  17) malware_c2_all 2>/dev/null || true ;;
    esac; }

    _exec_all() {
        echo "[Phase 1/5] Reconnaissance"; recon_scan
        echo; echo "[Phase 2/5] CVE Initial Access"
        for fn in exploit_ghostcat_1938 exploit_shellshock_6271 exploit_apache_41773 exploit_webmin_15107 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern; do timeout 15 $fn >/dev/null 2>&1 || true; done
        echo; echo "[Phase 3/5] Web Exploitation"
        for fn in exploit_sqli exploit_command_injection exploit_webshell_deploy exploit_xss_poc; do timeout 15 $fn >/dev/null 2>&1 || true; done
        echo; echo "[Phase 4/5] Brute Force"
        for fn in bruteforce_ssh bruteforce_ftp bruteforce_http; do timeout 15 $fn >/dev/null 2>&1 || true; done
        echo; echo "[Phase 5/5] PrivEsc + Post-Exploit"
        for fn in exploit_polkit_4034 crawl_all post_exploit_all malware_c2_all; do timeout 15 $fn >/dev/null 2>&1 || true; done
        echo; echo "[DONE] All scenarios complete"
    }

    _exec_cves() {
        local i=1; for fn in exploit_ghostcat_1938 exploit_shellshock_6271 exploit_apache_41773 exploit_webmin_15107 exploit_log4shell_pattern exploit_spring4shell_pattern exploit_struts_upload_pattern exploit_polkit_4034; do echo "[CVE ${i}/8]"; timeout 15 $fn >/dev/null 2>&1 || true; i=$((i+1)); done
        echo "[DONE] All CVEs complete"
    }

    # --- Init ---
    if [ -f "${BNB_TARGET_FILE}" ]; then
        local s; s="$(cat "${BNB_TARGET_FILE}")"; TUI_TARGET_IP="$(echo "$s"|cut -d' ' -f1)"; TARGET_PORT="$(echo "$s"|cut -d' ' -f2)"; TARGET_IP="$TUI_TARGET_IP"; TUI_TARGET_NAT="${TUI_TARGET_IP}"; TUI_HEADER_STATUS="Connected"
    fi
    TUI_FOOTER_TEXT="  <UP/DOWN> Navigate  <ENTER> Execute  <A> Run All  <C> Run CVEs  <T> Target  <Q> Back"
    _draw_vectors; tui_refresh; _hl "$TUI_CURSOR_VECTOR"

    # --- Event Loop ---
    while [ "$TUI_RUNNING" -eq 1 ]; do
        local key; key="$(tui_read_key)" || { sleep 0.05; continue; }
        case "$key" in
            UP)   [ "$TUI_CURSOR_VECTOR" -gt 0 ] && { TUI_CURSOR_VECTOR=$((TUI_CURSOR_VECTOR-1)); tui_refresh; _hl "$TUI_CURSOR_VECTOR"; } ;;
            DOWN) [ "$TUI_CURSOR_VECTOR" -lt "$((VEC_COUNT+2))" ] && { TUI_CURSOR_VECTOR=$((TUI_CURSOR_VECTOR+1)); tui_refresh; _hl "$TUI_CURSOR_VECTOR"; } ;;
            ENTER)
                [ "$TUI_CURSOR_VECTOR" -lt "$VEC_COUNT" ] && _exec "${vectors[$TUI_CURSOR_VECTOR]}" _exec_one $((TUI_CURSOR_VECTOR+1))
                [ "$TUI_CURSOR_VECTOR" = "$VEC_COUNT" ] && _exec "Run All Scenarios" _exec_all
                [ "$TUI_CURSOR_VECTOR" = "$((VEC_COUNT+1))" ] && _exec "Run All CVEs" _exec_cves
                [ "$TUI_CURSOR_VECTOR" = "$((VEC_COUNT+2))" ] && { tui_cleanup; return; }
                ;;
            [1-9]) local n="$key"; [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le 9 ] 2>/dev/null && { TUI_CURSOR_VECTOR=$((n-1)); tui_refresh; _hl "$TUI_CURSOR_VECTOR"; _exec "${vectors[$((n-1))]}" _exec_one "$n"; } ;;
            A|a) _exec "Run All Scenarios" _exec_all ;;
            C|c) _exec "Run All CVEs" _exec_cves ;;
            T|t) tui_cleanup; target_prompt || true; tui_init || return; TUI_HEADER_STATUS="Connected"
                if [ -f "${BNB_TARGET_FILE}" ]; then s="$(cat "${BNB_TARGET_FILE}")"; TUI_TARGET_IP="$(echo "$s"|cut -d' ' -f1)"; TARGET_PORT="$(echo "$s"|cut -d' ' -f2)"; TARGET_IP="$TUI_TARGET_IP"; TUI_TARGET_NAT="${TUI_TARGET_IP}"; fi
                _draw_vectors; tui_refresh; _hl "$TUI_CURSOR_VECTOR" ;;
            H|h|ESC|Q|q) tui_cleanup; return ;;
        esac
    done
}
