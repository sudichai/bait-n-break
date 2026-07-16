#!/usr/bin/env bash
# ANSI TUI rendering engine for bait-n-break attacker console.
# Uses tput + ANSI escape codes. No whiptail/dialog dependency.
# Sourced, not executed.

TUI_TERM_W=80
TUI_TERM_H=24
TUI_MIN_W=80
TUI_MIN_H=24
TUI_STTY_SAVED=""
TUI_RUNNING=0

declare -a TUI_PANEL_LEFT=()
declare -a TUI_PANEL_MID=()
declare -a TUI_PANEL_RIGHT=()
TUI_LEFT_TITLE="ATTACK VECTORS"
TUI_MID_TITLE="VULNERABILITIES FOUND"
TUI_RIGHT_TITLE="EXECUTE / LOGS"
TUI_HEADER_TITLE="bait-n-break"
TUI_HEADER_STATUS="Disconnected"
TUI_TARGET_IP=""
TUI_TARGET_TYPE=""
TUI_TARGET_NAT=""
TUI_CURSOR_VECTOR=0
TUI_VECTOR_COUNT=0
TUI_ACTIVE_VECTOR=""
TUI_FOOTER_TEXT=""
TUI_USE_ASCII_HEADER=0
TUI_PANEL_Y_OFFSET=4  # default: header(2) + gap(2) = start panels at y=4

tui_init() {
    TUI_TERM_W=$(tput cols 2>/dev/null || echo 80)
    TUI_TERM_H=$(tput lines 2>/dev/null || echo 24)
    if [ "$TUI_TERM_W" -lt "$TUI_MIN_W" ] || [ "$TUI_TERM_H" -lt "$TUI_MIN_H" ]; then
        echo "Terminal too small (${TUI_TERM_W}x${TUI_TERM_H}). Need at least ${TUI_MIN_W}x${TUI_MIN_H}."
        return 1
    fi
    TUI_STTY_SAVED="$(stty -g 2>/dev/null)"
    stty -echo -icanon min 0 time 0 2>/dev/null
    tput civis 2>/dev/null
    tput smcup 2>/dev/null
    clear
    TUI_RUNNING=1
}

tui_cleanup() {
    TUI_RUNNING=0
    tput rmcup 2>/dev/null
    tput cnorm 2>/dev/null
    [ -n "$TUI_STTY_SAVED" ] && stty "$TUI_STTY_SAVED" 2>/dev/null
    clear
}

tui_draw_header() {
    if [ "$TUI_USE_ASCII_HEADER" = "1" ]; then
        tui_draw_ascii_header
        return
    fi
    local title="${1:-$TUI_HEADER_TITLE}" status="${2:-$TUI_HEADER_STATUS}"
    local w="$TUI_TERM_W"
    local label="[${title}] - System Vulnerability Tool v1.0"
    local status_label="[Status: ${status}]"
    local padding=$((w - ${#label} - ${#status_label} - 2))
    [ "$padding" -lt 1 ] && padding=1

    tput cup 0 0
    printf '\033[7m\033[1m  %s%*s  %s\033[0m' "$label" "$padding" "" "$status_label"
}

tui_draw_ascii_header() {
    local w="$TUI_TERM_W"
    local lines=(
        "  _           _ _                      _                    _    "
        " | |         (_) |                    | |                  | |   "
        " | |__   __ _ _| |_ ______ _ __ ______| |__  _ __ ___  __ _| | __"
        " | '_ \\ / _\` | | __|______| '_ \\______| '_ \\| '__/ _ \\/ _\` | |/ /"
        " | |_) | (_| | | |_       | | | |     | |_) | | |  __/ (_| |   < "
        " |_.__/ \\__,_|_|\\__|      |_| |_|     |_.__/|_|  \\___|\\__,_|_|\\_\\"
        "                         sudichai/bait-n-break                     "
    )
    local i
    for ((i = 0; i < 7; i++)); do
        tput cup "$i" 0
        printf '\033[1m\033[32m%s\033[0m' "${lines[$i]}"
    done
}

tui_draw_target_bar() {
    local ip="${1:-$TUI_TARGET_IP}" tp="${2:-$TUI_TARGET_TYPE}" nat="${3:-$TUI_TARGET_NAT}"
    local status="${4:-$TUI_HEADER_STATUS}"
    local w="$TUI_TERM_W"
    local y=1
    [ "$TUI_USE_ASCII_HEADER" = "1" ] && y=8

    local line="  TARGET: ${ip}   [${tp}]"
    local tail="[${nat}]   Status: ${status}"

    tput cup "$y" 0
    printf '\033[7m%-*s\033[0m' "$w" "$line$(printf '%*s' $((w - ${#line})) '')"
    tput cup "$((y + 1))" 0
    printf ' %s%*s' "$tail" "$((w - ${#tail} - 1))" ""
}

tui_draw_footer() {
    local w="$TUI_TERM_W"
    local msg
    if [ -n "$TUI_FOOTER_TEXT" ]; then
        msg="$TUI_FOOTER_TEXT"
    else
        msg="  <H> HOME | <T> TARGETS | <C> RUN CVEs | <A> RUN ALL | <L> LOGS | <Esc> MENU | <Ctrl+C> EXIT"
    fi
    local padding=$((w - ${#msg}))
    [ "$padding" -lt 0 ] && msg="${msg:0:$((w-1))}" && padding=0

    tput cup $((TUI_TERM_H - 1)) 0
    printf '\033[7m%s%*s\033[0m' "$msg" "$padding" ""
}

tui_draw_panel() {
    local x="$1" y="$2" w="$3" h="$4" title="$5"
    shift 5
    local -n content_ref="$1" 2>/dev/null || return

    local title_line=" $title "
    local header_remain=$((w - ${#title_line} - 1))

    tput cup "$y" "$x"
    printf '\033[1m\033[37m\033[44m%s' "$title_line"
    local i
    for ((i = 0; i < header_remain; i++)); do printf ' '; done
    printf '\033[0m'

    for ((i = 1; i < h - 1; i++)); do
        tput cup $((y + i)) "$x"
        local idx=$((i - 1))
        local line=""
        if [ "$idx" -lt "${#content_ref[@]}" ]; then
            line="${content_ref[$idx]}"
        fi
        local line_w=$((w - 1))
        printf ' %-*s' "$line_w" "${line:0:$line_w}"
    done

    tput cup $((y + h - 1)) "$x"
    local j
    for ((j = 0; j < w; j++)); do printf ' '; done
}

tui_panel_append_left()  { TUI_PANEL_LEFT+=("$1"); }
tui_panel_append_mid()   { TUI_PANEL_MID+=("$1"); }
tui_panel_append_right() { TUI_PANEL_RIGHT+=("$1"); }
tui_panel_clear_left()   { TUI_PANEL_LEFT=(); }
tui_panel_clear_mid()    { TUI_PANEL_MID=(); }
tui_panel_clear_right()  { TUI_PANEL_RIGHT=(); }

tui_draw_layout() {
    tui_draw_header
    tui_draw_target_bar

    local panel_y=4
    [ "$TUI_USE_ASCII_HEADER" = "1" ] && panel_y=10

    local panel_w=$(( (TUI_TERM_W - 2) / 3 ))
    local panel_h=$(( TUI_TERM_H - panel_y - 1 ))
    local x1=0 x2=$((panel_w + 1)) x3=$((2 * panel_w + 2))

    tui_draw_panel "$x1" "$panel_y" "$panel_w" "$panel_h" "$TUI_LEFT_TITLE" TUI_PANEL_LEFT
    tui_draw_panel "$x2" "$panel_y" "$panel_w" "$panel_h" "$TUI_MID_TITLE" TUI_PANEL_MID
    tui_draw_panel "$x3" "$panel_y" "$panel_w" "$panel_h" "$TUI_RIGHT_TITLE" TUI_PANEL_RIGHT

    tui_draw_footer
}

tui_refresh() {
    tui_draw_layout
}

tui_read_key() {
    local key
    IFS= read -rsn1 -t 0.1 key 2>/dev/null || return 1
    if [ "$key" = $'\e' ]; then
        IFS= read -rsn2 -t 0.01 key2 2>/dev/null
        if [ "$key2" = "[A" ]; then echo "UP"
        elif [ "$key2" = "[B" ]; then echo "DOWN"
        elif [ "$key2" = "[C" ]; then echo "RIGHT"
        elif [ "$key2" = "[D" ]; then echo "LEFT"
        else echo "ESC"; fi
    elif [ "$key" = $'\n' ] || [ "$key" = "" ]; then
        echo "ENTER"
    else
        echo "$key"
    fi
}
