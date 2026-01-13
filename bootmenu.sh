#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar

# ----------------------------
# CONFIG
# ----------------------------
ESC=$(printf "\033")
RESET="${ESC}[0m"
HIGHLIGHT="${ESC}[7m"
TITLE="🎮 Simple Game Boot 🎮"

# Emojis
EMOJI_GAME="🎮"
EMOJI_DESKTOP="🖥"
EMOJI_TERM="⌨"
EMOJI_REBOOT="🔄"
EMOJI_SHUTDOWN="⏻"
ARROW="➤"

# Categories
CATS=("Games" "Desktops" "System")
CUR_CAT=0
CUR_ITEM=0

# Items per category (associative arrays)
declare -A ITEMS
declare -A CMDS

# ----------------------------
# FUNCTIONS
# ----------------------------

detect_desktops() {
    local idx=0
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        local name=$(grep '^Name=' "$f" | cut -d= -f2 | head -n1)
        local exec=$(grep '^Exec=' "$f" | cut -d= -f2 | head -n1)
        [ -n "$name" ] && [ -n "$exec" ] && {
            ITEMS["Desktops,$idx"]="$EMOJI_DESKTOP $name"
            CMDS["Desktops,$idx"]="$exec"
            ((idx++))
        }
    done
}

add_games() {
    ITEMS["Games,0"]="$EMOJI_GAME RetroArch"
    CMDS["Games,0"]="retroarch -f"
}

add_system() {
    ITEMS["System,0"]="$EMOJI_TERM Shell"
    CMDS["System,0"]="bash"
    ITEMS["System,1"]="$EMOJI_REBOOT Reboot"
    CMDS["System,1"]="sudo reboot"
    ITEMS["System,2"]="$EMOJI_SHUTDOWN Shutdown"
    CMDS["System,2"]="sudo shutdown now"
}

# Clear screen and draw XMB
draw() {
    clear
    echo -e "$TITLE\n"

    # Print categories (horizontal)
    for i in "${!CATS[@]}"; do
        if [ "$i" -eq "$CUR_CAT" ]; then
            printf "${HIGHLIGHT} ${CATS[i]} ${RESET}   "
        else
            printf " ${CATS[i]}   "
        fi
    done
    echo -e "\n"

    # Print items vertically
    local cat="${CATS[CUR_CAT]}"
    local idx=0
    while [ -n "${ITEMS["$cat,$idx"]+x}" ]; do
        if [ "$idx" -eq "$CUR_ITEM" ]; then
            echo -e "${HIGHLIGHT} ${ITEMS["$cat,$idx"]} ${RESET}"
        else
            echo " ${ITEMS["$cat,$idx"]}"
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

# ----------------------------
# INIT
# ----------------------------
add_games
detect_desktops
add_system

# ----------------------------
# MAIN LOOP
# ----------------------------
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
            [ "$CUR_CAT" -ge "${#CATS[@]}" ] && CUR_CAT=0
            CUR_ITEM=0
            ;;
        4) # left
            ((CUR_CAT--))
            [ "$CUR_CAT" -lt 0 ] && CUR_CAT=$((${#CATS[@]}-1))
            CUR_ITEM=0
            ;;
        5) # enter
            cmd="${CMDS[${CATS[CUR_CAT]},${CUR_ITEM}]}"
            [ -n "$cmd" ] && eval "$cmd"
            ;;
    esac
done
