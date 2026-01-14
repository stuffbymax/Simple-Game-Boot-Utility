#!/usr/bin/env bash
set -euo pipefail

# Controller mapper path
MAPPER="/usr/local/bin/ps3_to_keys.py"

# Start the mapper in the background
$MAPPER &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null' EXIT

# Menu items
ITEMS=("🎮 RetroArch" "💻 Desktop" "🖥️ Terminal" "🔄 Reboot" "⏻ Shutdown")
ACTIONS=("retroarch" "desktop" "shell" "reboot" "shutdown")
SEL=0

# Terminal control functions
clear_screen() { tput clear; }
cursor_hide() { tput civis; }
cursor_show() { tput cnorm; }
move_cursor() { tput cup "$1" "$2"; }

draw_menu() {
    clear_screen
    cursor_hide
    local row=$(( $(tput lines)/2 ))
    local col_start=$(( ($(tput cols) - ${#ITEMS[@]}*15)/2 ))
    for i in "${!ITEMS[@]}"; do
        local col=$(( col_start + i*15 ))
        move_cursor $row $col
        if [[ $i -eq $SEL ]]; then
            tput rev
            echo -n "${ITEMS[i]}"
            tput sgr0
        else
            echo -n "${ITEMS[i]}"
        fi
    done
    move_cursor $((row+2)) 0
    echo "Use ← → arrows or controller. Enter to select. ESC to exit."
}

# Detect desktop sessions
detect_desktop() {
    local sessions=()
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec_cmd=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [[ -n "$name" && -n "$exec_cmd" ]] && sessions+=("$name|$exec_cmd")
    done
    echo "${sessions[@]}"
}

# Key reading (arrow keys and enter)
read_key() {
    IFS= read -rsn1 key 2>/dev/null
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key2 2>/dev/null
        key+="$key2"
    fi
    case "$key" in
        $'\x1b[C') SEL=$(( (SEL+1) % ${#ITEMS[@]} )) ;;  # Right arrow
        $'\x1b[D') SEL=$(( (SEL-1 + ${#ITEMS[@]}) % ${#ITEMS[@]} )) ;; # Left arrow
        '') return 0 ;;  # Enter
        $'\x1b') exit 0 ;; # ESC
    esac
}

# Map RetroArch and desktop dynamically if found
for sess in $(detect_desktop); do
    name="${sess%%|*}"
    exec_cmd="${sess##*|}"
    ITEMS+=("💻 $name")
    ACTIONS+=("session:$exec_cmd")
done

# Main loop
while true; do
    draw_menu
    read_key
    # Execute action on Enter
    if [[ $key == "" ]]; then
        case "${ACTIONS[SEL]}" in
            retroarch)
                kill $MAPPER_PID 2>/dev/null
                retroarch -f || read -p "RetroArch error"
                $MAPPER & MAPPER_PID=$!
                ;;
            session:*)
                kill $MAPPER_PID 2>/dev/null
                echo "exec ${ACTIONS[SEL]#session:}" > "$HOME/.xinitrc"
                startx || read -p "Desktop error"
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
