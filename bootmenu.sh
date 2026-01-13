#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# CONFIG
# --------------------------
DIALOG=dialog
command -v dialog >/dev/null || DIALOG=whiptail

MAPPER="/usr/local/bin/ps3_to_keys.py"

# Emojis for XMB feel
EMOJI_GAME="🎮"
EMOJI_DESKTOP="🖥"
EMOJI_TERM="⌨"
EMOJI_REBOOT="🔄"
EMOJI_SHUTDOWN="⏻"
ARROW="➤"

# Menu dimensions
HEIGHT=20
WIDTH=60
MENU_HEIGHT=10

# --------------------------
# HELPERS
# --------------------------

detect_sessions() {
    local f name exec
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [ -n "$name" ] && [ -n "$exec" ] && echo "$name|$exec"
    done < <(printf "%s\n" /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop)
}

sysinfo() {
    mem=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    load=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1)
    echo "Mem: $mem | Load: $load"
}

# --------------------------
# CONTROLLER MAPPER
# --------------------------

if [ -x "$MAPPER" ]; then
    "$MAPPER" &
    MPID=$!
    trap 'kill $MPID 2>/dev/null' EXIT
fi

# --------------------------
# MAIN LOOP
# --------------------------

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    # Horizontal Categories: Games | Desktop | System
    # We'll fake XMB by spacing names with emojis
    CATEGORY_LINE=""

    # ---- Games ----
    if command -v retroarch >/dev/null; then
        CATEGORY_LINE+="$EMOJI_GAME  RetroArch    "
        ITEMS+=("$i" "$EMOJI_GAME  RetroArch")
        ACTIONS+=("retro")
        ((i++))
    fi

    # ---- Desktop Sessions ----
    while IFS='|' read -r name exec; do
        CATEGORY_LINE+="$EMOJI_DESKTOP  $name    "
        ITEMS+=("$i" "$EMOJI_DESKTOP  $name")
        ACTIONS+=("session:$exec")
        ((i++))
    done < <(detect_sessions)

    # ---- System ----
    CATEGORY_LINE+="$EMOJI_TERM  Shell    $EMOJI_REBOOT  Reboot    $EMOJI_SHUTDOWN  Shutdown"
    ITEMS+=("$i" "$EMOJI_TERM  Shell")
    ACTIONS+=("shell")
    ((i++))
    ITEMS+=("$i" "$EMOJI_REBOOT  Reboot")
    ACTIONS+=("reboot")
    ((i++))
    ITEMS+=("$i" "$EMOJI_SHUTDOWN  Shutdown")
    ACTIONS+=("shutdown")
    ((i++))

    # --------------------------
    # SHOW MENU
    # --------------------------
    INFO=$(sysinfo)

    CHOICE=$($DIALOG \
        --clear \
        --backtitle "$CATEGORY_LINE | $INFO" \
        --title " XMB Boot Menu " \
        --menu "$ARROW  Select" \
        "$HEIGHT" "$WIDTH" "$MENU_HEIGHT" \
        "${ITEMS[@]}" \
        3>&1 1>&2 2>&3
    ) || exit 0

    # --------------------------
    # EXECUTE SELECTION
    # --------------------------
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

    # Restart mapper after returning
    if [ -x "$MAPPER" ]; then
        "$MAPPER" &
        MPID=$!
    fi
done
