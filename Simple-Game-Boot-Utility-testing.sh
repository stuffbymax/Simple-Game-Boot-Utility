#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# CONFIGURATION & PATHS
# -------------------------------
USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
LOG_FILE="$HOME/install_log.txt"

# Colors for terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "   Simple Game Boot INSTALLER"
echo -e "================================================${NC}"
echo "Targeting: Arch, Debian, Ubuntu, Fedora"
echo "this program requires at least 8MB of RAM"
echo "the program may not install PKGs for other distros than debian"
read -r -p "This script modifies system files. Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# 1. DETECT PACKAGE MANAGER & MAP NAMES
# -------------------------------
declare -A PKGS

if command -v pacman >/dev/null; then
    PM="pacman"
    INSTALL="sudo pacman -Sy --needed --noconfirm"
    PKGS=(
        [xorg]="xorg-server xorg-xinit xorg-xinput"
        [py_evdev]="python-evdev"
        [py_uinput]="python-uinput"
        [retro]="retroarch retroarch-assets"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
elif command -v apt-get >/dev/null; then
    PM="apt"
    INSTALL="sudo apt-get update && sudo apt-get install -y"
    PKGS=(
        [xorg]="xinit xserver-xorg-core xserver-xorg-input-all"
        [py_evdev]="python3-evdev"
        [py_uinput]="python3-uinput"
        [retro]="retroarch"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
elif command -v dnf >/dev/null; then
    PM="dnf"
    INSTALL="sudo dnf install -y"
    PKGS=(
        [xorg]="xorg-x11-server-Xorg xorg-x11-xinit"
        [py_evdev]="python3-evdev"
        [py_uinput]="python3-uinput"
        [retro]="retroarch"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
else
    echo -e "${RED}Error: Unsupported distribution.${NC}"
    exit 1
fi

echo -e "${YELLOW}Detected $PM. Installing packages...${NC}"
$INSTALL ${PKGS[xorg]} ${PKGS[py_evdev]} ${PKGS[py_uinput]} ${PKGS[retro]} ${PKGS[utils]} || echo "Some packages failed, continuing..."

# -------------------------------
# 2. UINPUT & PERMISSIONS
# -------------------------------
echo -e "${YELLOW}Configuring uinput permissions...${NC}"
sudo modprobe uinput || true

# Persistence for module loading
if [ -d /etc/modules-load.d ]; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
fi

# Udev rule: Allow 'input' group to use uinput (Standard distro practice)
sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

# Ensure user is in the correct groups
sudo usermod -aG input "$USER_NAME" || true
# Some distros (Debian/Ubuntu) use 'video' for Xorg access
sudo usermod -aG video "$USER_NAME" || true

# -------------------------------
# 3. CONTROLLER MAPPER (Python)
# -------------------------------
echo -e "${YELLOW}Creating Controller Mapper...${NC}"
sudo tee "$PS3_PYTHON" >/dev/null << 'EOF'
#!/usr/bin/env python3
import evdev, uinput, sys, time

def get_device():
    try:
        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
        for d in devices:
            # Look for a device with buttons (Gamepads usually have BTN_SOUTH)
            if evdev.ecodes.EV_KEY in d.capabilities():
                return d
    except: return None
    return None

device = get_device()
if not device: sys.exit(0)

events = [
    uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
    uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT
]

try:
    ui = uinput.Device(events)
    # Map typical Gamepad buttons to Keyboard
    # 304=A/Cross, 305=B/Circle, 307=X/Square, 308=Y/Triangle
    BTN_MAP = {304: uinput.KEY_ENTER, 305: uinput.KEY_ESC, 307: uinput.KEY_BACKSPACE, 308: uinput.KEY_SPACE}

    device.grab()
    for e in device.read_loop():
        if e.type == evdev.ecodes.EV_KEY and e.code in BTN_MAP:
            ui.emit(BTN_MAP[e.code], e.value)
        elif e.type == evdev.ecodes.EV_ABS:
            if e.code == evdev.ecodes.ABS_HAT0Y:
                key = uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN
                if e.value != 0: 
                    ui.emit(key, 1); ui.emit(key, 0)
            elif e.code == evdev.ecodes.ABS_HAT0X:
                key = uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT
                if e.value != 0:
                    ui.emit(key, 1); ui.emit(key, 0)
except:
    sys.exit(0)
EOF
sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# 4. ENHANCED BOOT MENU
# -------------------------------
echo -e "${YELLOW}Creating Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash

#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# CONFIG
# ----------------------------
ESC=$(printf "\033")
RESET="${ESC}[0m"
BOLD="${ESC}[1m"

CATEGORY_COLOR="${ESC}[1;34m"   # Blue categories
ITEM_COLOR="${ESC}[0;37m"       # Gray items
SELECTED_COLOR="${ESC}[1;33m"   # Yellow selected
TITLE="🎮 Simple Game Boot 🎮"
ARROW="➤"

CATS=("Games" "Desktops" "System")
CUR_CAT=0
CUR_ITEM=0

declare -A ITEMS
declare -A CMDS

MAPPER="/usr/local/bin/ps3_to_keys.py"

# ----------------------------
# INITIALIZE ITEMS
# ----------------------------
add_games() {
    command -v retroarch >/dev/null && {
        ITEMS["Games,0"]="🎮 RetroArch"
        CMDS["Games,0"]="retroarch -f"
    }
}

detect_desktops() {
    local idx=0 f name exec
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [ -n "$name" ] && [ -n "$exec" ] && {
            ITEMS["Desktops,$idx"]="🖥 $name"
            CMDS["Desktops,$idx"]="$exec"
            ((idx++))
        }
    done
}

add_system() {
    ITEMS["System,0"]="⌨ Shell"
    CMDS["System,0"]="bash"
    ITEMS["System,1"]="🔄 Reboot"
    CMDS["System,1"]="sudo reboot"
    ITEMS["System,2"]="⏻ Shutdown"
    CMDS["System,2"]="sudo shutdown now"
}

# ----------------------------
# DRAW XMB
# ----------------------------
draw() {
    clear
    echo -e "$BOLD$TITLE$RESET\n"

    # Categories (horizontal)
    for i in "${!CATS[@]}"; do
        if [ "$i" -eq "$CUR_CAT" ]; then
            printf "${SELECTED_COLOR}${BOLD} ${CATS[i]} ${RESET}   "
        else
            printf "${CATEGORY_COLOR} ${CATS[i]} ${RESET}   "
        fi
    done
    echo -e "\n"

    # Items (vertical)
    local cat="${CATS[CUR_CAT]}"
    local idx=0
    while [ -n "${ITEMS["$cat,$idx"]+x}" ]; do
        if [ "$idx" -eq "$CUR_ITEM" ]; then
            echo -e "${SELECTED_COLOR}${BOLD}${ARROW}  ${ITEMS["$cat,$idx"]}${RESET}"
        else
            echo -e "   ${ITEM_COLOR}${ITEMS["$cat,$idx"]}${RESET}"
        fi
        ((idx++))
    done
}

# ----------------------------
# READ ARROWS
# ----------------------------
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
# START CONTROLLER MAPPER
# ----------------------------
if [ -x "$MAPPER" ]; then
    "$MAPPER" &
    MPID=$!
    trap 'kill $MPID 2>/dev/null' EXIT
fi

# ----------------------------
# INIT ITEMS
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

EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# 5. AUTOLOGIN (SYSTEMD)
# -------------------------------
if command -v systemctl >/dev/null; then
    echo -e "${YELLOW}Configuring TTY1 Autologin...${NC}"
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reload
fi

# -------------------------------
# 6. SHELL TRIGGER
# -------------------------------
# Arch/Fedora use .bash_profile, Ubuntu/Debian use .profile
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"

TRIGGER='[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh'
if ! grep -q "bootmenu.sh" "$TARGET_PROFILE" 2>/dev/null; then
    echo -e "${YELLOW}Adding trigger to $TARGET_PROFILE...${NC}"
    echo "$TRIGGER" >> "$TARGET_PROFILE"
fi

echo -e "${GREEN}DONE! Setup complete.${NC}"
echo "1. Your user was added to the 'input' group for the controller mapper."
echo "2. Please reboot for all group changes and autologin to take effect."
