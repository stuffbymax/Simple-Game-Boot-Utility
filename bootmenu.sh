#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar

# =========================
# CONFIGURATION
# =========================

# Colors (ANSI escape codes)
COLOR_RESET="\033[0m"
COLOR_BOLD="\033[1m"
COLOR_UNDERLINE="\033[4m"

CATEGORY_COLOR="\033[1;34m"       # Blue
ITEM_COLOR="\033[0;37m"           # Light gray
SELECTED_COLOR="\033[1;33m"       # Yellow

TITLE="🎮 Simple Game Boot 🎮"

# Emojis per category
EMOJI_GAMES="🎮"
EMOJI_DESKTOP="🖥"
EMOJI_SYSTEM="⚙"

ARROW="➤"

# Menu layout
CATS=("Games" "Desktops" "System")
CUR_CAT=0
CUR_ITEM=0

declare -A ITEMS
declare -A CMDS

# =========================
# FUNCTIONS
# =========================

# Detect installed desktops
detect_desktops() {
    local idx=0
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        local name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        local exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [ -n "$name" ] && [ -n "$exec" ] && {
            ITEMS["Desktops,$idx"]="$EMOJI_DESKTOP $name"
            CMDS["Desktops,$idx"]="$exec"
            ((idx++))
        }
    done
}

# Add games
add_games() {
    ITEMS["Games,0"]="$EMOJI_GAMES RetroArch"
    CMDS["Games,0"]="retroarch -f"
}

# Add system items
add_system() {
    ITEMS["System,0"]="$EMOJI_SYSTEM Shell"
    CMDS["System,0"]="bash"
    ITEMS["System,1"]="$EMOJI_SYSTEM Reboot"
    CMDS["System,1"]="sudo reboot"
    ITEMS["System,2"]="$EMOJI_SYSTEM Shutdown"
    CMDS["System,2"]="sudo shutdown now"
}

# Draw the XMB menu
draw() {
    clear
    echo -e "$COLOR_BOLD$TITLE$COLOR_RESET\n"

    # Draw categories (horizontal)
    for i in "${!CATS[@]}"; do
        if [ "$i" -eq "$CUR_CAT" ]; then
            printf "${SELECTED_COLOR}${COLOR_BOLD} ${CATS[i]} ${COLOR_RESET}   "
        else
            printf "${CATEGORY_COLOR} ${CATS[i]} ${COLOR_RESET}   "
        fi
    done
    echo -e "\n"

    # Draw items vertically
    local cat="${CATS[CUR_CAT]}"
    local idx=0
    while [ -n "${ITEMS["$cat,$idx"]+x}" ]; do
        local item="${ITEMS["$cat,$idx"]}"

        if [ "$idx" -eq "$CUR_ITEM" ]; then
            # Selected item: highlight, bold, extra spaces for “zoomed” effect
            echo -e "${SELECTED_COLOR}${COLOR_BOLD}${ARROW}  $item  ${COLOR_RESET}"
        else
            echo -e "   ${ITEM_COLOR}$item${COLOR_RESET}"
        fi
        ((idx++))
    done
}

# Capture arrow keys
read_input() {
    local key
    IFS= read -rsn1 key 2>/dev/null
    if [[ $key == $'\x1b' ]]; then
        IFS= read -rsn2 -t 0.1 key
        case "$key" in
            "[A") return 1 ;; # up
            "[B") return 2 ;; # down
            "[C") return 3 ;; # right
            "[D") return 4 ;; # left
        esac
    elif [[ $key == "" ]]; then
        return 5 # enter
    fi
    return 0
}

# =========================
# INIT
# =========================
add_games
detect_desktops
add_system

# =========================
# MAIN LOOP
# =========================
while true; do
    draw
    read_input
    case $? in
        1) # up
            ((CUR_ITEM--))
            [ "$CUR_ITEM" -lt 0 ] && CUR_ITEM=$(( $(printf "%s\n" "${!ITEMS[@]}" | grep "^${CATS[CUR_CAT]}" | wc -l)-1 ))
            ;;
        2) # down
            ((CUR_ITEM++))
            local max=$(( $(printf "%s\n" "${!ITEMS[@]}" | grep "^${CATS[CUR_CAT]}" | wc -l)-1 ))
            [ "$CUR_ITEM" -gt "$max" ] && CUR_ITEM=0
            ;;
        3) # right
            ((CUR_CAT++))
            [ "$CUR_CAT" -ge "${#CATS[@]}" ] && CUR_CAT=$((${#CATS[@]}-1))
            CUR_ITEM=0
            ;;
        4) # left
            ((CUR_CAT--))
            [ "$CUR_CAT" -lt 0 ] && CUR_CAT=0
            CUR_ITEM=0
            ;;
        5) # enter
            cmd="${CMDS[${CATS[CUR_CAT]},${CUR_ITEM}]}"
            [ -n "$cmd" ] && eval "$cmd"
            ;;
    esac
done
