#!/usr/bin/env bash
#created BY marinP/stuffbymax
#description: Installer script for Simple Game Boot Utility (SGBU)
#License MIT
#version 0.0.3.1 - Added Bluetooth support and controller pairing instructions
set -euo pipefail

# -------------------------------
# CONFIGURATION & PATHS
# -------------------------------
USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
DIAGNOSTIC="/usr/local/bin/diagnostic.sh"
LOG_FILE="$HOME/install_log.txt"

# Colors for terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "   Simple Game Boot INSTALLER v0.0.3"
echo -e "================================================${NC}"
echo "Targeting: Arch, Debian, Ubuntu, Fedora"
echo "This program requires at least 8MB of RAM"
echo "Includes Bluetooth Support & Controller Mapping"
read -r -p "This script modifies system files. Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# 1. DETECT PACKAGE MANAGER & MAP NAMES
# -------------------------------
detect_pm() {
    for pm in pacman apt dnf zypper xbps-install apk; do
        command -v "$pm" >/dev/null && echo "$pm" && return
    done
    echo "unsupported"
}

PM="$(detect_pm)"
echo "Detected package manager: $PM"

install_packages() {
    case "$PM" in
        pacman)
            sudo pacman -Syu --needed --noconfirm \
            bluez bluez-utils \
            retroarch retroarch-assets \
            xorg-server xorg-xinit xorg-xinput \
            dialog antimicrox onboard \
            python-evdev python-uinput \
            wget curl unzip sudo neovim tmux || echo "Some packages failed"
            ;;
        apt)
            sudo apt update
            # Core X packages
            sudo apt install -y \
                xinit xserver-xorg-core xserver-xorg-input-all \
                x11-xserver-utils x11-utils bluetooth bluez bluez-tools rfkill || echo "X packages failed"
            
            # RetroArch
            sudo apt install -y retroarch || echo -e "${YELLOW}RetroArch failed, continuing...${NC}"
            
            # Dialog
            sudo apt install -y dialog || echo "Dialog failed"
            
            # Python dependencies
            sudo apt install -y python3 python3-pip python3-evdev || echo "Python packages failed"
            
            # uinput - might need manual module
            sudo apt install -y python3-uinput 2>/dev/null || {
                echo -e "${YELLOW}python3-uinput not available, will use pip...${NC}"
                sudo pip3 install python-uinput 2>/dev/null || echo "pip uinput failed"
            }
            
            # Qt5 libraries for antimicrox
            sudo apt install -y \
                libqt5core5a libqt5gui5 libqt5widgets5 libqt5network5 \
                2>/dev/null || echo "Qt5 libraries install attempt"
            
            # AntiMicroX
            if ! sudo apt install -y antimicrox 2>/dev/null; then
                echo -e "${YELLOW}AntiMicroX not in repos, trying alternatives...${NC}"
                if command -v flatpak >/dev/null; then
                    flatpak install -y flathub io.github.antimicrox.antimicrox 2>/dev/null || echo "Flatpak failed"
                fi
            fi
            
            # Onboard & Utilities
            sudo apt install -y onboard xfce4-panel xfce4-indicator-plugin wget curl unzip sudo neovim tmux || echo "Utilities failed"
            ;;
        dnf)
            sudo dnf install -y \
                retroarch \
                xorg-x11-server-Xorg xorg-x11-xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux bluez bluez-tools || echo "Some packages failed"
            ;;
        zypper)
            sudo zypper install -y \
                retroarch \
                xorg-x11-server xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux bluez || echo "Some packages failed"
            ;;
        xbps-install)
            sudo xbps-install -Sy \
                retroarch \
                xorg-minimal xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux bluez || echo "Some packages failed"
            ;;
        apk)
            sudo apk add --no-cache \
                retroarch \
                xorg-server xinit \
                dialog antimicrox onboard \
                py3-evdev py3-uinput \
                wget curl unzip sudo neovim tmux bluez || echo "Some packages failed"
            ;;
        *)
            echo -e "${RED}No supported package manager found${NC}"
            exit 1
            ;;
    esac
}

echo -e "${YELLOW}Installing packages...${NC}"
install_packages

# -------------------------------
# 2. UINPUT & PERMISSIONS
# -------------------------------
echo -e "${YELLOW}Configuring uinput permissions...${NC}"
sudo modprobe uinput || true

if [ -d /etc/modules-load.d ]; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
fi

sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

# Add user to bluetooth group if it exists
if getent group bluetooth >/dev/null; then
    sudo usermod -aG bluetooth "$USER_NAME" || true
fi
sudo usermod -aG input "$USER_NAME" || true
sudo usermod -aG video "$USER_NAME" || true

sudo udevadm control --reload-rules || true
sudo udevadm trigger || true

# -------------------------------
# 3. CONTROLLER MAPPER (Python)
# -------------------------------
echo -e "${YELLOW}Creating Controller Mapper...${NC}"
sudo tee "$PS3_PYTHON" >/dev/null << 'EOF'
#!/usr/bin/env python3
'''
created BY marinP/stuffbymax
description: a tool that allows user to use gamepad as keyboard
License MIT
'''
import evdev
import uinput
import sys
import time

def find_controller():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if evdev.ecodes.EV_KEY in device.capabilities():
            return device
    print("No controller found.")
    sys.exit(1)

try:
    device = find_controller()
    print(f"Using device: {device.path} ({device.name})")
except Exception as e:
    print(f"Error finding controller: {e}")
    sys.exit(1)

events = [
    uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
    uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT
]

try:
    ui = uinput.Device(events)
except Exception as e:
    print(f"Error creating uinput device: {e}")
    sys.exit(1)

# Button mappings
BTN_MAP_COMMON = {
    304: uinput.KEY_ENTER,      # A / Cross
    305: uinput.KEY_ESC,        # B / Circle
    307: uinput.KEY_BACKSPACE,  # X / Square
    308: uinput.KEY_SPACE,      # Y / Triangle
    544: uinput.KEY_UP,
    545: uinput.KEY_DOWN,
    546: uinput.KEY_LEFT,
    547: uinput.KEY_RIGHT
}

# Generic D-pad handler for Xbox controllers often mapping to ABS_HAT0
try:
    device.grab()
    print("Controller grabbed. Press Ctrl+C to stop.")
    
    for event in device.read_loop():
        if event.type == evdev.ecodes.EV_KEY:
            key = BTN_MAP_COMMON.get(event.code)
            if key is not None:
                ui.emit(key, event.value)
        elif event.type == evdev.ecodes.EV_ABS:
            if event.code == evdev.ecodes.ABS_HAT0Y:
                if event.value == -1:
                    ui.emit(uinput.KEY_UP, 1); ui.emit(uinput.KEY_UP, 0)
                elif event.value == 1:
                    ui.emit(uinput.KEY_DOWN, 1); ui.emit(uinput.KEY_DOWN, 0)
            elif event.code == evdev.ecodes.ABS_HAT0X:
                if event.value == -1:
                    ui.emit(uinput.KEY_LEFT, 1); ui.emit(uinput.KEY_LEFT, 0)
                elif event.value == 1:
                    ui.emit(uinput.KEY_RIGHT, 1); ui.emit(uinput.KEY_RIGHT, 0)
except KeyboardInterrupt:
    pass
finally:
    device.ungrab()
EOF
sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# 4. ENHANCED BOOT MENU (Fixed)
# -------------------------------
echo -e "${YELLOW}Creating Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DIALOG_TOOL="dialog"
command -v dialog >/dev/null || DIALOG_TOOL="whiptail"
MAPPER="/usr/local/bin/ps3_to_keys.py"

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [[ -n "$name" && -n "$exec" ]] && echo "$name|$exec"
    done
}

detect_steam() {
    for steam_path in "$HOME/.steam/steam/steam.sh" "/usr/bin/steam" "/usr/games/steam"; do
        [ -x "$steam_path" ] && echo "$steam_path" && return 0
    done
    return 1
}

get_system_info() {
    local mem=$(free -h --si 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')
    echo "Mem: $mem"
}

# Start mapper
if [ -x "$MAPPER" ]; then
    $MAPPER &
    MAPPER_PID=$!
    trap 'kill $MAPPER_PID 2>/dev/null' EXIT
fi

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    if command -v retroarch >/dev/null; then
        ITEMS+=($i "RetroArch")
        ACTIONS+=("retroarch")
        ((i++))
    fi

    STEAM=$(detect_steam)
    if [ -n "$STEAM" ]; then
        ITEMS+=($i "Steam Big Picture")
        ACTIONS+=("steam:$STEAM")
        ((i++))
    fi

    while IFS='|' read -r name exec; do
        ITEMS+=($i "Desktop: $name")
        ACTIONS+=("session:$exec")
        ((i++))
    done < <(detect_sessions)

    ITEMS+=($i "Bluetooth Manager")
    ACTIONS+=("bluetooth")
    ((i++))

    ITEMS+=($i "Terminal")
    ACTIONS+=("shell")
    ((i++))
    
    ITEMS+=($i "Run Diagnostics")
    ACTIONS+=("diagnostic")
    ((i++))
    
    ITEMS+=($i "Reboot")
    ACTIONS+=("reboot")
    ((i++))
    
    ITEMS+=($i "Shutdown")
    ACTIONS+=("shutdown")

    SYSINFO=$(get_system_info)
    CHOICE=$($DIALOG_TOOL --backtitle "SGBU | v0.0.3 | $SYSINFO" --menu "Select Action" 20 70 12 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        steam:*)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            xinit ${ACTION#steam:} -bigpicture -- :0 vt$XDG_VTNR 2>&1 | tee -a "$HOME/steam.log"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        retroarch)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            retroarch -f 2>&1 | tee -a "$HOME/retroarch.log"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        bluetooth)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            clear
            if command -v bluetoothctl >/dev/null; then
                echo -e "${CYAN}--- Bluetooth Manager ---${NC}"
                echo "1. Put your controller in pairing mode."
                echo "2. Type 'scan on' to find devices."
                echo "3. Type 'pair <MAC>' to pair."
                echo "4. Type 'trust <MAC>' to auto-connect later."
                echo "5. Type 'connect <MAC>' to connect."
                echo "Type 'exit' to return to menu."
                echo ""
                bluetoothctl
            else
                echo -e "${RED}bluetoothctl not found. Is BlueZ installed?${NC}"
                read -p "Press Enter..."
            fi
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        session:*)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            cat > "$HOME/.xinitrc" << XINITRC
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=\$HOME/.Xauthority
if command -v antimicrox >/dev/null; then antimicrox --hidden & fi
if command -v onboard >/dev/null; then onboard & fi
exec ${ACTION#session:}
XINITRC
            chmod +x "$HOME/.xinitrc"
            startx 2>&1 | tee -a "$HOME/xsession.log"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        shell)
            clear
            echo -e "${CYAN}Entering shell. Type 'exit' to return.${NC}"
            bash
            ;;
        diagnostic)
            clear
            [ -x /usr/local/bin/diagnostic.sh ] && /usr/local/bin/diagnostic.sh || echo "Not found"
            read -p "Press Enter to continue..."
            ;;
        reboot) sudo reboot ;;
        shutdown) sudo shutdown now ;;
    esac
done
EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# 5. DIAGNOSTIC SCRIPT (Updated for BT)
# -------------------------------
echo -e "${YELLOW}Creating Diagnostic Script...${NC}"
sudo tee "$DIAGNOSTIC" >/dev/null << 'EOF'
#!/usr/bin/env bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}SYSTEM DIAGNOSTICS${NC}"

# Bluetooth Check
echo -e "\n${CYAN}[Bluetooth Check]${NC}"
if command -v bluetoothctl >/dev/null; then
    echo -e "${GREEN}✓${NC} BlueZ installed"
    if systemctl is-active --quiet bluetooth; then
        echo -e "${GREEN}✓${NC} Bluetooth service running"
    else
        echo -e "${RED}✗${NC} Bluetooth service NOT running"
        echo "  Try: sudo systemctl start bluetooth"
    fi
    # Check controller
    if echo "info" | bluetoothctl | grep -q "Device"; then
        echo -e "${GREEN}✓${NC} Bluetooth device paired"
    else
        echo -e "${YELLOW}!${NC} No Bluetooth devices paired currently"
    fi
else
    echo -e "${RED}✗${NC} BlueZ not found"
fi

# Xorg Check
echo -e "\n${CYAN}[X Server Check]${NC}"
command -v Xorg >/dev/null && echo -e "${GREEN}✓${NC} Xorg installed" || echo -e "${RED}✗${NC} Xorg missing"

# Controller Check
echo -e "\n${CYAN}[Controller Check]${NC}"
if ls /dev/input/event* >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Input devices detected"
else
    echo -e "${RED}✗${NC} No input devices found"
fi

echo -e "\n${CYAN}Done.${NC}"
EOF
sudo chmod +x "$DIAGNOSTIC"

# -------------------------------
# 6. AUTOLOGIN & SYSTEM SETUP
# -------------------------------
if command -v systemctl >/dev/null; then
    echo -e "${YELLOW}Configuring Autologin...${NC}"
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reload
    
    # Disable Display Managers
    for dm in gdm gdm3 sddm lightdm lxdm; do
        if systemctl is-active "$dm" >/dev/null 2>&1; then
            sudo systemctl disable "$dm" 2>/dev/null
            echo "Disabled $dm"
        fi
    done
fi

# -------------------------------
# 7. BLUETOOTH SERVICE SETUP
# -------------------------------
echo -e "${YELLOW}Configuring Bluetooth Service...${NC}"
if command -v systemctl >/dev/null; then
    sudo systemctl enable bluetooth 2>/dev/null || echo "Could not enable bluetooth"
    sudo systemctl start bluetooth 2>/dev/null || echo "Could not start bluetooth"
fi

# Unblock RFKill
if command -v rfkill >/dev/null; then
    sudo rfkill unblock bluetooth 2>/dev/null || true
fi

# Ensure Bluetooth service is enabled and started
sudo systemctl enable bluetooth.service
sudo systemctl start bluetooth.service


# Configure Bluetooth Agent (Legacy pairing support)
if command -v bluetoothctl >/dev/null; then
    # This ensures controllers pair without PIN errors
    cat << BT_EOF | sudo bluetoothctl
power on
agent on
default-agent
BT_EOF
fi

# -------------------------------
# 8. SHELL TRIGGER
# -------------------------------
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"
TRIGGER='[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh'
if ! grep -q "bootmenu.sh" "$TARGET_PROFILE" 2>/dev/null; then
    echo "$TRIGGER" >> "$TARGET_PROFILE"
fi

# -------------------------------
# 9. RETROARCH CORES
# -------------------------------
echo -e "${YELLOW}Downloading RetroArch cores...${NC}"
mkdir -p "$HOME/.config/retroarch/cores"
if command -v wget >/dev/null; then
    cd "$HOME/.config/retroarch/cores/"
    wget -q -r -np -nd -R "index.html*" -A "*.zip" \
        https://buildbot.libretro.com/nightly/linux/x86_64/latest/ 2>/dev/null || true
    for z in *.zip; do [ -f "$z" ] && unzip -o "$z" && rm "$z"; done
    cd - >/dev/null
fi



# -------------------------------
# 10. FINAL INSTRUCTIONS
# -------------------------------
echo -e "\n${CYAN}================================================"
echo -e "   INSTALLATION COMPLETE"
echo -e "================================================${NC}"
echo -e "${GREEN}✓${NC} Boot menu: $BOOTMENU"
echo -e "${GREEN}✓${NC} Bluetooth: Enabled & Service Started"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} You must REBOOT for permissions to apply."
echo "On next boot, the menu will load automatically."
echo "To pair a controller, select 'Bluetooth Manager' in the menu."
echo ""
read -r -p "Press Enter to finish..."
