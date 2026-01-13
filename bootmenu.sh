#!/usr/bin/env bash
set -euo pipefail

### ==========================
### CONFIG (CUSTOMIZE ME)
### ==========================

TITLE="Simple Game Boot"
VERSION="0.1"
WIDTH=70
HEIGHT=20
MENU_HEIGHT=10

# Icons (best with Nerd Fonts, still OK without)
ICON_GAME="🎮"
ICON_DESKTOP="🖥"
ICON_TERM="⌨"
ICON_REBOOT="🔄"
ICON_SHUTDOWN="⏻"
ICON_ARROW="➤"

# Mapper
MAPPER="/usr/local/bin/ps3_to_keys.py"

# Dialog backend
DIALOG=dialog
command -v dialog >/dev/null || DIALOG=whiptail

### ==========================
### HELPERS
### ==========================

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [ -n "$name" ] && [ -n "$exec" ] && echo "$name|$exec"
    done
}

sysinfo() {
    mem=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    load=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1)
    echo "Mem $mem | Load $load"
}

### ==========================
### CONTROLLER MAPPER
### ==========================

if [ -x "$MAPPER" ]; then
    "$MAPPER" &
    MPID=$!
    trap 'kill $MPID 2>/dev/null' EXIT
fi

### ==========================
### MAIN LOOP
### ==========================

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    ### ---- Games ----
    if command -v retroarch >/dev/null; then
        ITEMS+=($i "$ICON_GAME  RetroArch")
        ACTIONS+=("retro")
        ((i++))
    fi

    ### ---- Desktops ----
    while IFS='|' read -r name exec; do
        ITEMS+=($i "$ICON_DESKTOP  $name")
        ACTIONS+=("session:$exec")
        ((i++))
    done < <(detect_sessions)

    ### ---- System ----
    ITEMS+=(
        $i "$ICON_TERM  Shell"
        $((i+1)) "$ICON_REBOOT  Reboot"
        $((i+2)) "$ICON_SHUTDOWN  Shutdown"
    )
    ACTIONS+=("shell" "reboot" "shutdown")

    INFO=$(sysinfo)

    CHOICE=$(
        $DIALOG \
        --clear \
        --backtitle "$TITLE v$VERSION | $INFO" \
        --title " XMB Menu " \
        --menu "$ICON_ARROW  Select" \
        "$HEIGHT" "$WIDTH" "$MENU_HEIGHT" \
        "${ITEMS[@]}" \
        3>&1 1>&2 2>&3
    ) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        retro)
            kill $MPID 2>/dev/null || true
            retroarch -f || read -rp "RetroArch exited. Press Enter."
            ;;
        session:*)
            kill $MPID 2>/dev/null || true
            echo "exec ${ACTION#session:}" > "$HOME/.xinitrc"
            startx || read -rp "Session failed. Press Enter."
            ;;
        shell)
            clear
            bash
            ;;
        reboot)
            sudo reboot
            ;;
        shutdown)
            sudo shutdown now
            ;;
    esac

    # Restart mapper after return
    if [ -x "$MAPPER" ]; then
        "$MAPPER" &
        MPID=$!
    fi
done
