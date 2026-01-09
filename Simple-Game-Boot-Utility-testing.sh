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
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}╔════════════════════════════════════════════════╗"
echo -e "║   XMB-Style Game Boot System INSTALLER         ║"
echo -e "╚════════════════════════════════════════════════╝${NC}"
echo "Targeting: Arch, Debian, Ubuntu, Fedora"
echo "This program requires at least 8MB of RAM"
echo ""
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

# Udev rule: Allow 'input' group to use uinput
sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

# Ensure user is in the correct groups
sudo usermod -aG input "$USER_NAME" || true
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
# 4. XMB-STYLE BOOT MENU
# -------------------------------
echo -e "${YELLOW}Creating XMB-Style Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash

# XMB-Style Boot Menu with Icons and Categories
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

MAPPER="/usr/local/bin/ps3_to_keys.py"

# XMB-style icons using Unicode
ICON_GAME="🎮"
ICON_DESKTOP="🖥️ "
ICON_SETTINGS="⚙️ "
ICON_POWER="⚡"
ICON_TERMINAL="💻"
ICON_INFO="ℹ️ "

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
    echo "RAM: $mem | Load: $load | CPU: $cpu | Temp: $temp"
}

# Start mapper
$MAPPER &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null' EXIT

while true; do
    # Build categorized menu items
    ITEMS=()
    ACTIONS=()
    COLORS=()
    i=1

    # CATEGORY: Games
    if command -v retroarch >/dev/null; then
        ITEMS+=($i "$ICON_GAME RetroArch")
        ACTIONS+=("retroarch")
        COLORS+=("$CYAN")
        ((i++))
    fi

    # CATEGORY: Desktop Sessions
    while IFS='|' read -r name exec; do
        ITEMS+=($i "$ICON_DESKTOP $name")
        ACTIONS+=("session:$exec")
        COLORS+=("$BLUE")
        ((i++))
    done < <(detect_sessions)

    # CATEGORY: System
    ITEMS+=($i "$ICON_TERMINAL Terminal")
    ACTIONS+=("shell")
    COLORS+=("$GREEN")
    ((i++))

    ITEMS+=($i "$ICON_INFO System Info")
    ACTIONS+=("sysinfo")
    COLORS+=("$YELLOW")
    ((i++))

    # CATEGORY: Power
    ITEMS+=($i "$ICON_POWER Reboot")
    ACTIONS+=("reboot")
    COLORS+=("$YELLOW")
    ((i++))

    ITEMS+=($i "$ICON_POWER Shutdown")
    ACTIONS+=("shutdown")
    COLORS+=("$RED")
    ((i++))

    # Build dialog command with color tags
    DIALOG_ITEMS=()
    for idx in "${!ITEMS[@]}"; do
        if [ $((idx % 2)) -eq 0 ]; then
            DIALOG_ITEMS+=("${ITEMS[$idx]}")
        else
            color_idx=$((idx / 2))
            DIALOG_ITEMS+=("${COLORS[$color_idx]}${ITEMS[$idx]}${NC}")
        fi
    done

    SYSINFO=$(get_system_info)
    
    # Enhanced dialog with colors and custom backtitle
    CHOICE=$(dialog \
        --colors \
        --backtitle "╔═══════════════════════════════════════════════════════════════════════╗\n║ XrossMediaBar Boot System v1.0 | $SYSINFO ║\n╚═══════════════════════════════════════════════════════════════════════╝" \
        --title "║ Select Category > Item ║" \
        --menu "\nUse ↑↓ arrows and ENTER to select\nPress ESC to exit\n" \
        22 75 12 \
        "${DIALOG_ITEMS[@]}" \
        3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        retroarch)
            kill $MAPPER_PID 2>/dev/null
            clear
            echo -e "${CYAN}╔════════════════════════════════╗${NC}"
            echo -e "${CYAN}║   Starting RetroArch...        ║${NC}"
            echo -e "${CYAN}╚════════════════════════════════╝${NC}"
            sleep 1
            retroarch -f || {
                echo -e "${RED}Error starting RetroArch${NC}"
                read -p "Press ENTER to continue..."
            }
            $MAPPER & MAPPER_PID=$!
            ;;
        session:*)
            kill $MAPPER_PID 2>/dev/null
            clear
            echo -e "${BLUE}╔════════════════════════════════╗${NC}"
            echo -e "${BLUE}║   Starting Desktop Session...  ║${NC}"
            echo -e "${BLUE}╚════════════════════════════════╝${NC}"
            sleep 1
            echo "exec ${ACTION#session:}" > "$HOME/.xinitrc"
            startx || {
                echo -e "${RED}Error starting Desktop${NC}"
                read -p "Press ENTER to continue..."
            }
            $MAPPER & MAPPER_PID=$!
            ;;
        shell)
            clear
            echo -e "${GREEN}╔════════════════════════════════╗${NC}"
            echo -e "${GREEN}║   Terminal Mode                ║${NC}"
            echo -e "${GREEN}║   Type 'exit' to return        ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════╝${NC}"
            bash
            ;;
        sysinfo)
            dialog --colors --title "║ System Information ║" --msgbox "\n\
${CYAN}System Status:${NC}\n\
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n\
${GREEN}Hostname:${NC}    $(hostname)\n\
${GREEN}Kernel:${NC}      $(uname -r)\n\
${GREEN}Uptime:${NC}      $(uptime -p)\n\n\
${YELLOW}Resources:${NC}\n\
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\
$(free -h)\n\n\
${BLUE}Disk Usage:${NC}\n\
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\
$(df -h / | tail -n1)\n\n\
Press OK to return" 25 70
            ;;
        reboot)
            dialog --colors --title "${YELLOW}║ Reboot System ║${NC}" --yesno "\n${YELLOW}Are you sure you want to reboot?${NC}" 8 50
            if [ $? -eq 0 ]; then
                clear
                echo -e "${YELLOW}Rebooting...${NC}"
                sudo reboot
            fi
            ;;
        shutdown)
            dialog --colors --title "${RED}║ Shutdown System ║${NC}" --yesno "\n${RED}Are you sure you want to shutdown?${NC}" 8 50
            if [ $? -eq 0 ]; then
                clear
                echo -e "${RED}Shutting down...${NC}"
                sudo shutdown now
            fi
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
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"

TRIGGER='[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh'
if ! grep -q "bootmenu.sh" "$TARGET_PROFILE" 2>/dev/null; then
    echo -e "${YELLOW}Adding trigger to $TARGET_PROFILE...${NC}"
    echo "$TRIGGER" >> "$TARGET_PROFILE"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation Complete!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}What was installed:${NC}"
echo "  • XMB-Style boot menu with icons and colors"
echo "  • Controller mapper for gamepad navigation"
echo "  • Auto-login on TTY1"
echo "  • RetroArch and desktop session support"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Your user was added to 'input' and 'video' groups"
echo "  2. Reboot to activate the XMB interface"
echo "  3. Use arrow keys or gamepad to navigate"
echo ""
echo -e "${MAGENTA}Pro tip:${NC} Press ESC in the menu to exit to console"
echo ""
read -p "Press ENTER to finish..."
