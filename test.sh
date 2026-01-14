#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# USER CUSTOMIZATION
# -------------------------------
# Use ANSI 256-color codes or standard ones (0–7 for standard)
BG_COLOR="\033[48;5;236m"       # Background color
FG_COLOR="\033[38;5;15m"        # Normal text color
SEL_BG_COLOR="\033[48;5;33m"    # Selection background
SEL_FG_COLOR="\033[38;5;231m"   # Selection foreground
RESET_COLOR="\033[0m"

# -------------------------------
# CONFIG
# -------------------------------
MAPPER="/usr/local/bin/ps3_to_keys.py"
$MAPPER &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null; tput cnorm; echo -e "$RESET_COLOR"' EXIT

# -------------------------------
# TERMINAL HELPERS
# -------------------------------
clear_screen() { tput clear; }
cursor_hide() { tput civis; }
cursor_show() { tput cnorm; }
move_cursor() { tput cup "$1" "$2"; }

# -------------------------------
# 1. DETECT APPS AND DESKTOPS
# -------------------------------
ITEMS=()
ACTIONS=()

# Desktop environments
for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
    [ -f "$f" ] || continue
    name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
    exec_cmd=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
    [[ -n "$name" && -n "$exec_cmd" ]] || continue
    ITEMS+=("💻 $name")
    ACTIONS+=("session:$exec_cmd")
done

# Apps
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

# Add system options
ITEMS+=("🖥️ Terminal" "🔄 Reboot" "⏻ Shutdown")
ACTIONS+=("shell" "reboot" "shutdown")

# -------------------------------
# 2. DRAW XMB HORIZONTAL MENU
# -------------------------------
SEL=0
OFFSET=0

draw_menu() {
    clear_screen
    cursor_hide
    row=$(( $(tput lines)/2 ))
    width=$(tput cols)
    display_items=()

    max_visible=$(( width / 15 ))
    if (( ${#ITEMS[@]} <= max_visible )); then
        display_items=("${ITEMS[@]}")
        OFFSET=0
    else
        if (( SEL < OFFSET )); then OFFSET=$SEL; fi
        if (( SEL >= OFFSET + max_visible )); then OFFSET=$((SEL - max_visible + 1)); fi
        display_items=("${ITEMS[@]:OFFSET:max_visible}")
    fi

    start_col=$(( (width - ${#display_items[@]}*15)/2 ))

    for i in "${!display_items[@]}"; do
        idx=$((OFFSET + i))
        col=$((start_col + i*15))
        move_cursor $row $col
        if (( idx == SEL )); then
            echo -ne "${SEL_BG_COLOR}${SEL_FG_COLOR}${display_items[i]}${RESET_COLOR}"
        else
            echo -ne "${BG_COLOR}${FG_COLOR}${display_items[i]}${RESET_COLOR}"
        fi
    done

    move_cursor $((row+2)) 0
    echo -e "${FG_COLOR}← → arrows or controller | Enter to select | ESC to exit${RESET_COLOR}"
}

# -------------------------------
# 3. HANDLE INPUT
# -------------------------------
read_key() {
    IFS= read -rsn1 key 2>/dev/null
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key2 2>/dev/null
        key+="$key2"
    fi
    case "$key" in
        $'\x1b[C') SEL=$(( (SEL+1) % ${#ITEMS[@]} )) ;; # Right
        $'\x1b[D') SEL=$(( (SEL-1 + ${#ITEMS[@]}) % ${#ITEMS[@]} )) ;; # Left
        '') return 0 ;;  # Enter
        $'\x1b') exit 0 ;; # ESC
    esac
}

# -------------------------------
# 4. MAIN LOOP
# -------------------------------
while true; do
    draw_menu
    read_key
    if [[ $key == "" ]]; then
        case "${ACTIONS[SEL]}" in
            app:*)
                cmd="${ACTIONS[SEL]#app:}"
                kill $MAPPER_PID 2>/dev/null
                $cmd || read -p "App failed, press Enter..."
                $MAPPER & MAPPER_PID=$!
                ;;
            session:*)
                cmd="${ACTIONS[SEL]#session:}"
                kill $MAPPER_PID 2>/dev/null
                echo "exec $cmd" > "$HOME/.xinitrc"
                startx || read -p "Desktop failed, press Enter..."
                $MAPPER & MAPPER_PID=$!
                ;;
            shell)
                clear; bash ;;
            reboot)
                sudo reboot ;;
            shutdown)
                sudo shutdown now ;;
        esac
    fi
done
