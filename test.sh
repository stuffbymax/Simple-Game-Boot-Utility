#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# COLORS
# -------------------------------
RESET='\033[0m'
BOLD='\033[1m'

# Define category colors (background + foreground)
declare -A CAT_BG
declare -A CAT_FG
CAT_BG=( ["Games"]=44 ["Apps"]=42 ["System"]=45 )  # Blue, Green, Magenta
CAT_FG=( ["Games"]=97 ["Apps"]=30 ["System"]=97 )  # White/Black

# Highlight colors
SEL_BG='\033[103m' # Yellow background
SEL_FG='\033[30m'  # Black foreground

# -------------------------------
# CATEGORIES
# -------------------------------
CATEGORIES=("Games" "Apps" "System")
declare -A ITEMS

# Games
ITEMS["Games"]=""
[ -x "$(command -v retroarch)" ] && ITEMS["Games"]+="RetroArch\n"
# Add any other known games if desired

# Apps: detect .desktop files
ITEMS["Apps"]=$(ls /usr/share/applications/*.desktop 2>/dev/null | xargs -n1 basename | sed 's/\.desktop//')

# System: detect DMs, WMs, utilities
DM_WM=()
[ -x "$(command -v startx)" ] && DM_WM+=("StartX")
[ -x "$(command -v dwm)" ] && DM_WM+=("dwm")
[ -x "$(command -v i3)" ] && DM_WM+=("i3")
[ -x "$(command -v bspwm)" ] && DM_WM+=("bspwm")
[ -x "$(command -v xfce4-session)" ] && DM_WM+=("XFCE")
[ -x "$(command -v gnome-session)" ] && DM_WM+=("GNOME")
[ -x "$(command -v kdeinit5)" ] && DM_WM+=("KDE")
ITEMS["System"]="Terminal\nReboot\nShutdown"
ITEMS["System"]+=$(printf "\n%s" "${DM_WM[@]}")

# -------------------------------
# FUNCTIONS
# -------------------------------
draw_menu() {
    clear
    echo -e "${BOLD}=== ASCII XMB Menu ===${RESET}\n"

    # Horizontal categories
    for i in "${!CATEGORIES[@]}"; do
        CAT_NAME="${CATEGORIES[i]}"
        BG="\033[${CAT_BG[$CAT_NAME]}m"
        FG="\033[${CAT_FG[$CAT_NAME]}m"
        if (( i == CAT )); then
            echo -ne "${SEL_BG}${SEL_FG} $CAT_NAME ${RESET}  "
        else
            echo -ne "${BG}${FG} $CAT_NAME ${RESET}  "
        fi
    done
    echo -e "\n"

    # Vertical items
    IFS=$'\n' read -rd '' -a ITEMS_ARRAY <<< "${ITEMS[${CATEGORIES[CAT]}]}"
    for i in "${!ITEMS_ARRAY[@]}"; do
        ITEM="${ITEMS_ARRAY[i]}"
        if (( i == SEL )); then
            echo -e "${SEL_BG}${SEL_FG}> ${ITEM} <${RESET}"
        else
            echo "  ${ITEM}"
        fi
    done

    echo -e "\nUse ← → to change category, ↑ ↓ to move, Enter to select, ESC to exit"
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
                    clear; echo "Launching RetroArch..."; sleep 1; retroarch -f ;;
                Terminal)
                    clear; bash ;;
                Reboot)
                    echo "Rebooting..."; sleep 1; sudo reboot ;;
                Shutdown)
                    echo "Shutting down..."; sleep 1; sudo shutdown now ;;
                StartX|dwm|i3|bspwm|XFCE|GNOME|KDE)
                    echo "Launching $CHOICE..."; sleep 1; exec $CHOICE ;;
                *)
                    # Try launching .desktop apps
                    if [[ -f "/usr/share/applications/$CHOICE.desktop" ]]; then
                        exec $(grep '^Exec=' "/usr/share/applications/$CHOICE.desktop" | cut -d= -f2)
                    fi ;;
            esac ;;
        $'\x1b') break ;; # ESC
    esac
done

clear
echo -e "$RESET"
