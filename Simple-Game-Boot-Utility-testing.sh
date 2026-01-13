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

# Reload udev rules and trigger them
echo -e "${YELLOW}Reloading udev rules...${NC}"
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input
sudo udevadm trigger --subsystem-match=misc

# Verify udev is running
if systemctl is-active --quiet systemd-udevd; then
    echo -e "${GREEN}✓ udev is running${NC}"
else
    echo -e "${YELLOW}Starting udev service...${NC}"
    sudo systemctl start systemd-udevd
    sudo systemctl enable systemd-udevd
fi

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
# 4. XMB-STYLE BOOT MENU
# -------------------------------
echo -e "${YELLOW}Creating XMB Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
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
    cat > "$CONFIG_FILE" << THEME_EOF
BG_COLOR="$BG_COLOR"
WAVE_COLOR="$WAVE_COLOR"
TEXT_COLOR="$TEXT_COLOR"
THEME_EOF
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

echo -e "${GREEN}================================================"
echo -e "   INSTALLATION COMPLETE!"
echo -e "================================================${NC}"
echo ""
echo -e "${CYAN}What was installed:${NC}"
echo "  ✓ XMB-style boot menu with theme customization"
echo "  ✓ PS3 controller mapper (gamepad to keyboard)"
echo "  ✓ RetroArch and desktop session support"
echo "  ✓ Auto-login on TTY1"
echo "  ✓ udev rules for controller access"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Reboot your system for all changes to take effect"
echo "  2. After reboot, the XMB menu will launch automatically"
echo "  3. Use arrow keys or controller to navigate"
echo "  4. Customize themes in Settings menu"
echo ""
echo -e "${GREEN}Theme settings saved to: ~/.config/sgbu/theme.conf${NC}"
echo -e "${GREEN}Log file: $LOG_FILE${NC}"
echo ""
read -r -p "Press Enter to finish..."