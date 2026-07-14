#!/usr/bin/env bash
# UI abstraction: whiptail -> dialog -> plain select/read fallback.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

ui_backend() {
    if command -v whiptail >/dev/null 2>&1; then
        echo "whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        echo "dialog"
    else
        echo "plain"
    fi
}

# ui_menu TITLE PROMPT TAG1 ITEM1 [TAG2 ITEM2 ...]
# Prints the chosen TAG to stdout. Returns non-zero if cancelled/no choice.
ui_menu() {
    local title="$1" prompt="$2"
    shift 2
    local backend
    backend="$(ui_backend)"

    case "$backend" in
        whiptail)
            whiptail --title "$title" --menu "$prompt" 20 70 10 "$@" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --menu "$prompt" 20 70 10 "$@" 3>&1 1>&2 2>&3
            ;;
        plain)
            echo "== $title ==" >&2
            echo "$prompt" >&2
            local i=1 tag item tags=()
            while [ $# -gt 0 ]; do
                tag="$1"; item="$2"; shift 2
                tags+=("$tag")
                echo "  [$i] $tag - $item" >&2
                i=$((i + 1))
            done
            local choice
            read -r -p "Select number: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#tags[@]}" ]; then
                echo "${tags[$((choice - 1))]}"
                return 0
            fi
            return 1
            ;;
    esac
}

ui_msgbox() {
    local title="$1" text="$2"
    local backend
    backend="$(ui_backend)"
    case "$backend" in
        whiptail) whiptail --title "$title" --msgbox "$text" 15 70 ;;
        dialog) dialog --title "$title" --msgbox "$text" 15 70 ;;
        plain)
            echo "== $title ==" >&2
            echo "$text" >&2
            read -r -p "Press Enter to continue..." _
            ;;
    esac
}

ui_error() {
    ui_msgbox "Error: $1" "$2"
}

ui_yesno() {
    local title="$1" text="$2"
    local backend
    backend="$(ui_backend)"
    case "$backend" in
        whiptail) whiptail --title "$title" --yesno "$text" 10 70 ;;
        dialog) dialog --title "$title" --yesno "$text" 10 70 ;;
        plain)
            local ans
            read -r -p "$text [y/N]: " ans
            [[ "$ans" =~ ^[Yy]$ ]]
            ;;
    esac
}
