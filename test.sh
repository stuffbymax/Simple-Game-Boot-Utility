#!/usr/bin/env bash

# -------------------------------
# XMB-STYLE GAME BOOT MENU (BASH)
# -------------------------------

# Colors
BOLD='\033[1m'
RESET='\033[0m'
CYAN='\033[96m'
YELLOW='\033[93m'
BG_CYAN='\033[46m'

# Controller Mapper Path
MAPPER="/usr/local/bin/ps3_to_keys.py"

# -------------------------------
# Detect DEs/WMs and RetroArch
# -------------------------------
detect_sessions() {
    local sessions=()
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [[ -n "$name" && -n "$exec" ]] && sessions+=("$name|$exec")
    done
    echo "${sessions[@]}"
}

detect_retroarch() {
    command -v retroarch >/dev/null && echo "RetroArch"
}

# -------------------------------
# System Info
# -------------------------------
get_system_info() {
    local mem=$(free -h --si | awk '/^Mem:/ {print $3 "/" $2}')
    local load=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4"%"}')
    local temp=$(sensors 2>/dev/null | grep "Package id 0" | awk '{print $4}' | sed 's/+//')
    [ -z "$temp" ] && temp="N/A"
    echo "Mem: $mem | Load: $load | CPU: $cpu | Temp: $temp"
}

# -------------------------------
# Start controller mapper
# -------------------------------
$MAPPER &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null' EXIT

# -------------------------------
# Build menu items dynamically
# -------------------------------
MENU_ITEMS=()
ACTIONS=()

# Auto-detect RetroArch
ra=$(detect_retroarch)
[ -n "$ra" ] && MENU_ITEMS+=("$ra") && ACTIONS+=("retroarch")

# Auto-detect DEs/WMs
for s in $(detect_sessions); do
    IFS='|' read -r name exec <<< "$s"
    MENU_ITEMS+=("Desktop: $name")
    ACTIONS+=("session:$exec")
done

# Always include Terminal, Reboot, Shutdown
MENU_ITEMS+=("Terminal" "Reboot" "Shutdown")
ACTIONS+=("shell" "reboot" "shutdown")

# Horizontal XMB menu variables
current=0
max_index=$((${#MENU_ITEMS[@]} - 1))

# -------------------------------
# Draw XMB menu
# -------------------------------
draw_menu() {
    clear
    SYSINFO=$(get_system_info)

    # Header
    echo -e "${CYAN}${BOLD}┌───────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}${BOLD}│              SIMPLE GAME BOOT                 │${RESET}"
    echo -e "${CYAN}${BOLD}│           Arch | Debian | Ubuntu | Fedora     │${RESET}"
    echo -e "${CYAN}${BOLD}│        $SYSINFO${CYAN} │${RESET}"
    echo -e "${CYAN}${BOLD}└───────────────────────────────────────────────┘${RESET}"
    echo

    # Horizontal XMB-style menu
    for i in "${!MENU_ITEMS[@]}"; do
        if [ "$i" -eq "$current" ]; then
            printf "${BG_CYAN}${BOLD}  %s  ${RESET}" "${MENU_ITEMS[$i]}"
        else
            printf "  %s  " "${MENU_ITEMS[$i]}"
        fi
    done
    echo
    echo
    echo -e "${YELLOW}Use Left/Right or D-pad to select, Enter/X to launch${RESET}"
}

# -------------------------------
# Main loop with smooth nav
# -------------------------------
ACTION=""
while true; do
    draw_menu

    # Read key input (keyboard or controller)
    read -rsn1 key1
    if [[ $key1 == $'\x1b' ]]; then
        read -rsn2 -t 0.01 key2
        case "$key2" in
            '[C') ((current++)) ;;  # Right
            '[D') ((current--)) ;;  # Left
        esac
    elif [[ $key1 == "" ]] || [[ $key1 == "x" ]] || [[ $key1 == "X" ]]; then
        ACTION="${ACTIONS[$current]}"
    elif [[ $key1 == "q" ]] || [[ $key1 == "Q" ]]; then
        kill $MAPPER_PID 2>/dev/null
        exit 0
    fi

    # Wrap-around
    ((current<0)) && current=$max_index
    ((current>max_index)) && current=0

    # Execute selected action
    if [[ -n "$ACTION" ]]; then
        case "$ACTION" in
            retroarch)
                kill $MAPPER_PID 2>/dev/null
                retroarch -f || read -p "Error starting RetroArch"
                $MAPPER & MAPPER_PID=$!
                ;;
            session:*)
                kill $MAPPER_PID 2>/dev/null
                echo "exec ${ACTION#session:}" > "$HOME/.xinitrc"
                startx || read -p "Error starting Desktop"
                $MAPPER & MAPPER_PID=$!
                ;;
            shell)
                clear; bash
                ;;
            reboot)
                sudo reboot
                ;;
            shutdown)
                sudo shutdown now
                ;;
        esac
        ACTION=""
    fi
done
