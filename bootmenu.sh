#!/usr/bin/env bash

DIALOG=dialog
command -v dialog >/dev/null || DIALOG=whiptail

MAPPER="/usr/local/bin/ps3_to_keys.py"

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | cut -d= -f2 | head -n1)
        exec=$(grep '^Exec=' "$f" | cut -d= -f2 | head -n1)
        echo "$name|$exec"
    done
}

$MAPPER &
MPID=$!
trap 'kill $MPID 2>/dev/null' EXIT

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    command -v retroarch >/dev/null && {
        ITEMS+=($i "RetroArch")
        ACTIONS+=("retro")
        ((i++))
    }

    while IFS='|' read -r n e; do
        ITEMS+=($i "Desktop: $n")
        ACTIONS+=("session:$e")
        ((i++))
    done < <(detect_sessions)

    ITEMS+=($i "Shell" $((i+1)) "Reboot" $((i+2)) "Shutdown")
    ACTIONS+=("shell" "reboot" "shutdown")

    CHOICE=$($DIALOG --menu "Simple Game Boot" 20 60 10 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit

    case "${ACTIONS[$((CHOICE-1))]}" in
        retro) kill $MPID; retroarch -f ;;
        session:*) kill $MPID; echo "exec ${ACTIONS[$((CHOICE-1))]#session:}" > ~/.xinitrc; startx ;;
        shell) clear; bash ;;
        reboot) sudo reboot ;;
        shutdown) sudo shutdown now ;;
    esac

    $MAPPER & MPID=$!
done
