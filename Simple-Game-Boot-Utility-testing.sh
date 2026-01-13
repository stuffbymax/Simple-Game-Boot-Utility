#!/usr/bin/env bash

# Colors for XMB-style interface
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration file for background color
CONFIG_DIR="$HOME/.config/sgbu"
CONFIG_FILE="$CONFIG_DIR/theme.conf"

# Controller Mapper Path
MAPPER="/usr/local/bin/ps3_to_keys.py"

# Default background color (can be changed in settings)
load_theme() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        BG_COLOR="\033[44m"  # Blue background (PS3 default)
        WAVE_COLOR="\033[46m"  # Cyan for wave effect
        TEXT_COLOR="\033[1;37m"  # White text
    fi
}

save_theme() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
BG_COLOR="$BG_COLOR"
WAVE_COLOR="$WAVE_COLOR"
TEXT_COLOR="$TEXT_COLOR"
EOF
}

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [[ -n "$name" && -n "$exec" ]] && echo "$name|$exec"
    done
}

get_system_info() {
    local mem=$(free -h --si | awk '/^Mem:/ {print $3 "/" $2}')
    local load=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4"%"}' 2>/dev/null || echo "N/A")
    local temp=$(sensors 2>/dev/null | grep "Package id 0" | awk '{print $4}' | sed 's/+//' || echo "N/A")
    echo "$mem | Load: $load | CPU: $cpu | Temp: $temp"
}

# Draw XMB-style interface
draw_xmb_header() {
    clear
    echo -e "${BG_COLOR}\033[2J\033[H"  # Clear screen with background
    
    # Top bar with wave pattern
    local cols=$(tput cols)
    echo -e "${WAVE_COLOR}"
    printf '%.0s▀' $(seq 1 $cols)
    echo -e "${BG_COLOR}"
    echo ""
    
    # System info bar
    local sysinfo=$(get_system_info)
    local date_time=$(date "+%A, %B %d, %Y  %H:%M")
    echo -e "${TEXT_COLOR}  SGBU ${GRAY}v0.0.3    ${TEXT_COLOR}${date_time}${NC}"
    echo -e "${BG_COLOR}${GRAY}  System: $sysinfo${NC}"
    echo ""
}

draw_xmb_footer() {
    local cols=$(tput cols)
    echo ""
    echo -e "${WAVE_COLOR}"
    printf '%.0s▄' $(seq 1 $cols)
    echo -e "${BG_COLOR}"
    echo -e "${TEXT_COLOR}  [△] Select  [○] Back  [□] Options  [✕] Cancel${NC}"
}

# XMB-style menu selection
show_xmb_menu() {
    local -n items=$1
    local -n descriptions=$2
    local title=$3
    local selected=0
    local total=${#items[@]}
    
    while true; do
        draw_xmb_header
        echo -e "${TEXT_COLOR}${BOLD}  ◆ $title${NC}"
        echo ""
        
        # Draw menu items
        for i in "${!items[@]}"; do
            if [ $i -eq $selected ]; then
                # Selected item - highlighted with arrow
                echo -e "${BG_COLOR}${TEXT_COLOR}  ${BOLD}▶ ${items[$i]}${NC}"
                [ -n "${descriptions[$i]}" ] && echo -e "${BG_COLOR}${GRAY}      ${descriptions[$i]}${NC}"
            else
                # Unselected items
                echo -e "${BG_COLOR}${GRAY}    ${items[$i]}${NC}"
            fi
            echo ""
        done
        
        draw_xmb_footer
        
        # Read input
        read -rsn1 key
        case "$key" in
            $'\x1b')  # Escape sequence
                read -rsn2 key
                case "$key" in
                    '[A') ((selected--)); [ $selected -lt 0 ] && selected=$((total-1)) ;;  # Up
                    '[B') ((selected++)); [ $selected -ge $total ] && selected=0 ;;  # Down
                esac
                ;;
            '') return $selected ;;  # Enter
            'q'|'Q') return 255 ;;  # Quit
        esac
    done
}

# Theme customization menu
customize_theme() {
    while true; do
        local items=("Background Color" "Wave Color" "Text Color" "Reset to Default" "Back")
        local descriptions=("Change main background" "Change wave accent" "Change text color" "Restore PS3 blue theme" "Return to main menu")
        
        show_xmb_menu items descriptions "Theme Settings"
        local choice=$?
        
        case $choice in
            0)  # Background Color
                local bg_items=("Blue (PS3 Default)" "Black" "Dark Gray" "Purple" "Dark Green" "Dark Red")
                local bg_descs=("Classic PlayStation blue" "Pure black" "Dark gray" "Purple theme" "Dark green" "Dark red")
                show_xmb_menu bg_items bg_descs "Background Color"
                case $? in
                    0) BG_COLOR="\033[44m" ;;
                    1) BG_COLOR="\033[40m" ;;
                    2) BG_COLOR="\033[100m" ;;
                    3) BG_COLOR="\033[45m" ;;
                    4) BG_COLOR="\033[42m" ;;
                    5) BG_COLOR="\033[41m" ;;
                esac
                save_theme
                ;;
            1)  # Wave Color
                local wave_items=("Cyan (PS3 Default)" "White" "Yellow" "Green" "Magenta" "Blue")
                local wave_descs=("Classic cyan waves" "White accent" "Yellow accent" "Green accent" "Magenta accent" "Blue accent")
                show_xmb_menu wave_items wave_descs "Wave Accent Color"
                case $? in
                    0) WAVE_COLOR="\033[46m" ;;
                    1) WAVE_COLOR="\033[47m" ;;
                    2) WAVE_COLOR="\033[43m" ;;
                    3) WAVE_COLOR="\033[42m" ;;
                    4) WAVE_COLOR="\033[45m" ;;
                    5) WAVE_COLOR="\033[44m" ;;
                esac
                save_theme
                ;;
            2)  # Text Color
                local text_items=("White (Default)" "Cyan" "Yellow" "Green")
                local text_descs=("Bright white" "Cyan text" "Yellow text" "Green text")
                show_xmb_menu text_items text_descs "Text Color"
                case $? in
                    0) TEXT_COLOR="\033[1;37m" ;;
                    1) TEXT_COLOR="\033[1;36m" ;;
                    2) TEXT_COLOR="\033[1;33m" ;;
                    3) TEXT_COLOR="\033[1;32m" ;;
                esac
                save_theme
                ;;
            3)  # Reset to default
                BG_COLOR="\033[44m"
                WAVE_COLOR="\033[46m"
                TEXT_COLOR="\033[1;37m"
                save_theme
                ;;
            *) break ;;
        esac
    done
}

# Main menu
main_menu() {
    load_theme
    
    # Start controller mapper
    $MAPPER &
    MAPPER_PID=$!
    trap 'kill $MAPPER_PID 2>/dev/null; clear' EXIT
    
    while true; do
        local items=()
        local descriptions=()
        local actions=()
        
        # RetroArch
        if command -v retroarch >/dev/null; then
            items+=("Games")
            descriptions+=("Launch RetroArch emulation station")
            actions+=("retroarch")
        fi
        
        # Desktop sessions
        while IFS='|' read -r name exec; do
            items+=("Desktop: $name")
            descriptions+=("Start $name desktop environment")
            actions+=("session:$exec")
        done < <(detect_sessions)
        
        # System options
        items+=("Terminal" "Settings" "Reboot" "Shutdown")
        descriptions+=("Open bash shell" "Customize theme and settings" "Restart system" "Power off system")
        actions+=("shell" "settings" "reboot" "shutdown")
        
        show_xmb_menu items descriptions "Main Menu"
        choice=$?
        
        [ $choice -eq 255 ] && break
        
        action="${actions[$choice]}"
        
        case "$action" in
            retroarch)
                kill $MAPPER_PID 2>/dev/null
                clear
                retroarch -f
                read -p "Press Enter to return..."
                $MAPPER & MAPPER_PID=$!
                ;;
            session:*)
                kill $MAPPER_PID 2>/dev/null
                clear
                echo "exec ${action#session:}" > "$HOME/.xinitrc"
                startx
                read -p "Press Enter to return..."
                $MAPPER & MAPPER_PID=$!
                ;;
            shell)
                clear
                echo -e "${GREEN}Entering shell. Type 'exit' to return.${NC}"
                bash
                ;;
            settings)
                customize_theme
                ;;
            reboot)
                clear
                echo -e "${YELLOW}Rebooting...${NC}"
                sudo reboot
                ;;
            shutdown)
                clear
                echo -e "${YELLOW}Shutting down...${NC}"
                sudo shutdown now
                ;;
        esac
    done
    
    clear
}

# Run main menu
main_menu