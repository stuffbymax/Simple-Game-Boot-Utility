#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# COLORS
# -------------------------------
FG='\033[97m'      # White
BG='\033[40m'      # Black background
SEL_FG='\033[30m'  # Black
SEL_BG='\033[106m' # Cyan background
RESET='\033[0m'

# -------------------------------
# CATEGORIES AND ITEMS
# -------------------------------
CATEGORIES=("Games" "Apps" "System")
declare -A ITEMS
ITEMS["Games"]="RetroArch\nDoom\nQuake"
ITEMS["Apps"]=$(ls /usr/share/applications/*.desktop 2>/dev/null | xargs -n1 basename | sed 's/\.desktop//')
ITEMS["System"]="Terminal\nReboot\nShutdown"

# -------------------------------
# UTILS
# -------------------------------
draw_menu() {
    clear
    echo -e "${FG}${BG}=== ASCII XMB Menu ===${RESET}"
    
    # Horizontal categories
    for i in "${!CATEGORIES[@]}"; do
        if (( i == CAT )); then
            echo -ne "${SEL_BG}${SEL_FG} ${CATEGORIES[i]} ${RESET}  "
        else
            echo -ne " ${CATEGORIES[i]}  "
        fi
    done
    echo -e "\n"

    # Vertical items
    IFS=$'\n' read -rd '' -a ITEMS_ARRAY <<< "${ITEMS[${CATEGORIES[CAT]}]}"
    for i in "${!ITEMS_ARRAY[@]}"; do
        if (( i == SEL )); then
            echo -e "${SEL_BG}${SEL_FG}> ${ITEMS_ARRAY[i]} <${RESET}"
        else
            echo "  ${ITEMS_ARRAY[i]}"
        fi
    done

    echo -e "${FG}${BG}Use ← → to change category, ↑ ↓ to move, Enter to select, ESC to exit${RESET}"
}

read_key() {
    IFS= read -rsn3 key
    echo "$key"
}

# -------------------------------
# MAIN LOOP
# -------------------------------
CAT=0
SEL=0

while true; do
    draw_menu
    key=$(read_key)
    case "$key" in
        $'\x1b[A') SEL=$(( (SEL-1 + ${#ITEMS_ARRAY[@]}) % ${#ITEMS_ARRAY[@]} )) ;; # Up
        $'\x1b[B') SEL=$(( (SEL+1) % ${#ITEMS_ARRAY[@]} )) ;; # Down
        $'\x1b[C') CAT=$(( (CAT+1) % ${#CATEGORIES[@]} )); SEL=0 ;; # Right
        $'\x1b[D') CAT=$(( (CAT-1 + ${#CATEGORIES[@]}) % ${#CATEGORIES[@]} )); SEL=0 ;; # Left
        "")  # Enter
            CHOICE="${ITEMS_ARRAY[SEL]}"
            case "$CHOICE" in
                RetroArch)
                    clear
                    echo "Launching RetroArch..."
                    sleep 1
                    ;;
                Terminal)
                    clear
                    bash
                    ;;
                Reboot)
                    echo "Rebooting..."
                    sleep 1
                    ;;
                Shutdown)
                    echo "Shutting down..."
                    sleep 1
                    ;;
                *)
                    if [[ -f "/usr/share/applications/$CHOICE.desktop" ]]; then
                        exec $(grep '^Exec=' "/usr/share/applications/$CHOICE.desktop" | cut -d= -f2)
                    fi
                    ;;
            esac
            ;;
        $'\x1b') break ;; # ESC
    esac
done

clear
echo -e "$RESET"
