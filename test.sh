#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# COLORS
# -------------------------------
BG_COLOR="\033[48;5;236m"
FG_COLOR="\033[38;5;15m"
SEL_BG_COLOR="\033[48;5;33m"
SEL_FG_COLOR="\033[38;5;231m"
RESET_COLOR="\033[0m"

# -------------------------------
# CONTROLLER MAPPER
# -------------------------------
MAPPER="/usr/local/bin/ps3_to_keys.py"
$MAPPER &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null; tput cnorm; echo -e "$RESET_COLOR"' EXIT

# -------------------------------
# HIDE CURSOR
# -------------------------------
tput civis
clear

# -------------------------------
# DETECT APPS + DESKTOPS
# -------------------------------
ITEMS=()
ACTIONS=()

# Desktop sessions
for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
    [ -f "$f" ] || continue
    name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
    exec_cmd=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
    [[ -n "$name" && -n "$exec_cmd" ]] || continue
    ITEMS+=("[Desktop] $name")
    ACTIONS+=("session:$exec_cmd")
done

# Applications
for f in /usr/share/applications/*.desktop; do
    [ -f "$f" ] || continue
    nodisplay=$(grep '^NoDisplay=' "$f" | cut -d= -f2)
    [[ "$nodisplay" == "true" ]] && continue
    name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
    exec_cmd=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
    [[ -n "$name" && -n "$exec_cmd" ]] || continue
    ITEMS+=("[App] $name")
    ACTIONS+=("app:$exec_cmd")
done

# System
ITEMS+=("[Shell] Terminal" "[System] Reboot" "[System] Shutdown")
ACTIONS+=("shell" "reboot" "shutdown")

# -------------------------------
# MENU STATE
# -------------------------------
SEL=0
draw_menu() {
    clear
    echo -e "${FG_COLOR}--- ASCII XMB Menu ---${RESET_COLOR}"
    for i in "${!ITEMS[@]}"; do
        if (( i == SEL )); then
            echo -e "${SEL_BG_COLOR}${SEL_FG_COLOR}> ${ITEMS[i]} <${RESET_COLOR}"
        else
            echo -e "  ${ITEMS[i]}"
        fi
    done
    echo -e "${FG_COLOR}Use ↑ ↓ to move, Enter to select, ESC to exit${RESET_COLOR}"
}

read_key() {
    IFS= read -rsn3 key
    echo "$key"
}

# -------------------------------
# MAIN LOOP
# -------------------------------
while true; do
    draw_menu
    key=$(read_key)
    case "$key" in
        $'\x1b[A') SEL=$(( (SEL-1+${#ITEMS[@]}) % ${#ITEMS[@]} )) ;;  # Up
        $'\x1b[B') SEL=$(( (SEL+1) % ${#ITEMS[@]} )) ;;  # Down
        "")  # Enter
            case "${ACTIONS[SEL]}" in
                app:*)
                    cmd="${ACTIONS[SEL]#app:}"
                    kill $MAPPER_PID 2>/dev/null
                    $cmd || read -p "App failed. Enter..."
                    $MAPPER & MAPPER_PID=$!
                    ;;
                session:*)
                    cmd="${ACTIONS[SEL]#session:}"
                    kill $MAPPER_PID 2>/dev/null
                    echo "exec $cmd" > "$HOME/.xinitrc"
                    startx || read -p "Desktop failed. Enter..."
                    $MAPPER & MAPPER_PID=$!
                    ;;
                shell)
                    clear; bash ;;
                reboot)
                    sudo reboot ;;
                shutdown)
                    sudo shutdown now ;;
            esac
            ;;
        $'\x1b') break ;;  # ESC
    esac
done

# -------------------------------
# CLEANUP
# -------------------------------
tput cnorm
echo -e "$RESET_COLOR"
