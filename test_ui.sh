#!/usr/bin/env bash
set -euo pipefail

DIALOG_TOOL="dialog"
if ! command -v "$DIALOG_TOOL" >/dev/null 2>&1; then
    DIALOG_TOOL="whiptail"
fi

if ! command -v "$DIALOG_TOOL" >/dev/null 2>&1; then
    echo "The UI preview needs 'dialog' or 'whiptail' installed." >&2
    exit 1
fi

DIALOGRC_FILE=""
if [ "$DIALOG_TOOL" = "dialog" ]; then
    DIALOGRC_FILE=$(mktemp)
    cat > "$DIALOGRC_FILE" <<'DIALOGRC'
use_colors = ON
use_shadow = OFF
screen_color = (WHITE,BLUE,ON)
dialog_color = (WHITE,BLACK,OFF)
title_color = (CYAN,BLACK,ON)
border_color = (CYAN,BLACK,ON)
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (CYAN,BLACK,ON)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (BLACK,CYAN,ON)
button_active_color = (BLACK,CYAN,ON)
button_inactive_color = (WHITE,BLACK,OFF)
DIALOGRC
    export DIALOGRC="$DIALOGRC_FILE"
fi

cleanup() {
    if [ -n "$DIALOGRC_FILE" ]; then
        rm -f -- "$DIALOGRC_FILE"
    fi
}
trap cleanup EXIT

while true; do
    if ! choice=$("$DIALOG_TOOL" \
        --backtitle "PLAYSTATION 3 - GAME OS | SGBU | UI PREVIEW" \
        --title "XMB - GAME OS" \
        --menu "UI preview only - no apps or system actions will run." \
        22 76 14 \
        game "GAME     - RetroArch" \
        steam "GAME     - Steam (GamepadUI)" \
        desktop "SYSTEM   - Desktop: Example" \
        bluetooth "NETWORK  - Bluetooth Manager" \
        terminal "SYSTEM   - Terminal" \
        diagnostics "SYSTEM   - Run Diagnostics" \
        reboot "POWER    - Reboot" \
        shutdown "POWER    - Shutdown" \
        exit "Exit UI Preview" \
        3>&1 1>&2 2>&3); then
        break
    fi

    if [ "$choice" = "exit" ]; then
        break
    fi

    "$DIALOG_TOOL" \
        --backtitle "PLAYSTATION 3 - GAME OS | SGBU | UI PREVIEW" \
        --title "UI Preview" \
        --msgbox "Selected: $choice\n\nThis standalone preview does not launch applications or perform system actions." \
        9 64
done
