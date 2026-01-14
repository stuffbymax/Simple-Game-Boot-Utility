#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# COLORS (USER CUSTOMIZATION)
# -------------------------------
BG_COLOR="\033[48;5;236m"
FG_COLOR="\033[38;5;15m"
SEL_BG_COLOR="\033[48;5;33m"
SEL_FG_COLOR="\033[38;5;231m"
RESET_COLOR="\033[0m"

# -------------------------------
# START CONTROLLER MAPPER
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
    ITEMS+=("💻 $name")
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
    ITEMS+=("🛠️ $name")
    ACTIONS+=("app:$exec_cmd")
done

# System
ITEMS+=("🖥️ Terminal" "🔄 Reboot" "⏻ Shutdown")
ACTIONS+=("shell" "reboot" "shutdown")

# -------------------------------
# MENU STATE
# -------------------------------
SEL=0

draw_menu() {
    clear
    row=$(( $(tput lines)/2 ))
    col=2
    for i in "${!ITEMS[@]}"; do
        move_col=$((col + i*20))
        tput cup $row $move_col
        if (( i == SEL )); then
            echo -ne "${SEL_BG_COLOR}${SEL_FG_COLOR}${ITEMS[i]}${RESET_COLOR}"
        else
            echo -ne "${BG_COLOR}${FG_COLOR}${ITEMS[i]}${RESET_COLOR}"
        fi
    done
    tput cup $((row+2)) 0
    echo -e "${FG_COLOR}← → to move | Enter to select | ESC to exit${RESET_COLOR}"
}

read_key() {
    IFS= read -rsn1 k1
    if [[ $k1 == $'\x1b' ]]; then
        IFS= read -rsn2 k2
        k1+=$k2
    fi
    echo "$k1"
}

# -------------------------------
# MAIN LOOP
# -------------------------------
while true; do
    draw_menu
    key=$(read_key)
    case "$key" in
        $'\x1b[C') SEL=$(( (SEL+1) % ${#ITEMS[@]} )) ;;  # Right
        $'\x1b[D') SEL=$(( (SEL-1+${#ITEMS[@]}) % ${#ITEMS[@]} )) ;;  # Left
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
kill $MAPPER_PID 2>/dev/null
clear
exit 0
