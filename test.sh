#!/usr/bin/env bash
set -euo pipefail

# Controller mapper path
MAPPER="/usr/local/bin/ps3_to_keys.py"

# Start mapper
$MAPPER &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null' EXIT

# Base menu items (emoji + name)
ITEMS=("🎮 RetroArch" "💻 Desktop" "🖥️ Terminal" "🔄 Reboot" "⏻ Shutdown")
ACTIONS=("retroarch" "desktop" "shell" "reboot" "shutdown")
SEL=0  # Selected item
OFFSET=0  # For horizontal scrolling

# Terminal control functions
clear_screen() { tput clear; }
cursor_hide() { tput civis; }
cursor_show() { tput cnorm; }
move_cursor() { tput cup "$1" "$2"; }

# Detect desktop sessions and append to menu
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

for sess in $(detect_desktop); do
    name="${sess%%|*}"
    exec_cmd="${sess##*|}"
    ITEMS+=("💻 $name")
    ACTIONS+=("session:$exec_cmd")
done

# Draw menu with horizontal scrolling
draw_menu() {
    clear_screen
    cursor_hide
    local row=$(( $(tput lines)/2 ))
    local width=$(tput cols)
    local display_items=()

    # Determine visible items
    local max_visible=$(( width / 15 ))
    if (( ${#ITEMS[@]} <= max_visible )); then
        display_items=("${ITEMS[@]}")
        OFFSET=0
    else
        # Adjust offset if selection is outside visible range
        if (( SEL < OFFSET )); then OFFSET=$SEL; fi
        if (( SEL >= OFFSET + max_visible )); then OFFSET=$((SEL - max_visible + 1)); fi
        display_items=("${ITEMS[@]:OFFSET:max_visible}")
    fi

    # Center the visible items
    local start_col=$(( (width - ${#display_items[@]}*15)/2 ))

    for i in "${!display_items[@]}"; do
        local idx=$((OFFSET + i))
        local col=$((start_col + i*15))
        move_cursor $row $col
        if (( idx == SEL )); then
            tput rev
            echo -n "${display_items[i]}"
            tput sgr0
        else
            echo -n "${display_items[i]}"
        fi
    done

    move_cursor $((row+2)) 0
    echo "Use ← → arrows or controller. Enter to select. ESC to exit."
}

# Read key function (arrow keys + enter + esc)
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

# Main loop
while true; do
    draw_menu
    read_key
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