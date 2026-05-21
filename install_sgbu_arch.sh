#!/usr/bin/env bash
# created BY marinP/stuffbymax (Arch-only fork)
# description: Installer script for Simple Game Boot Utility (SGBU) - Arch Linux Edition
# License MIT
# version 0.0.4.0 - Arch-only, Steam + Vulkan driver selection
set -euo pipefail

# -------------------------------
# CONFIGURATION & PATHS
# -------------------------------
USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
DIAGNOSTIC="/usr/local/bin/diagnostic.sh"
LOG_FILE="$HOME/install_log.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "   Simple Game Boot INSTALLER v0.0.4 (Arch)"
echo -e "================================================${NC}"
echo "Target: Arch Linux only"
echo "Includes: Steam, Vulkan driver selection, Bluetooth, Controller Mapping"
echo ""

# -------------------------------
# ARCH CHECK
# -------------------------------
if ! command -v pacman >/dev/null; then
    echo -e "${RED}This script is for Arch Linux only (pacman not found).${NC}"
    exit 1
fi

read -r -p "This script modifies system files. Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# 1. VULKAN DRIVER SELECTION
# -------------------------------
echo ""
echo -e "${CYAN}================================================"
echo -e "   VULKAN DRIVER SELECTION"
echo -e "================================================${NC}"
echo "Choose your GPU / Vulkan driver:"
echo ""
echo "  1) AMD       - amdvlk + lib32-amdvlk         (RADV is also included via mesa)"
echo "  2) AMD RADV  - mesa + lib32-mesa only         (open-source, recommended for most AMD)"
echo "  3) NVIDIA    - nvidia + nvidia-utils           (proprietary, Maxwell/Pascal/Turing/Ampere+)"
echo "  4) NVIDIA (open) - nvidia-open + nvidia-utils  (open-source kernel module, Turing+)"
echo "  5) Intel     - intel-media-driver + mesa       (Iris Xe / Arc)"
echo "  6) Skip      - I'll install Vulkan drivers manually"
echo ""
read -r -p "Enter choice [1-6]: " VULKAN_CHOICE

VULKAN_PKGS=()
case "$VULKAN_CHOICE" in
    1)
        echo -e "${GREEN}Selected: AMD (amdvlk + mesa/RADV)${NC}"
        VULKAN_PKGS=(
            mesa lib32-mesa
            vulkan-radeon lib32-vulkan-radeon
            amdvlk lib32-amdvlk
            vulkan-icd-loader lib32-vulkan-icd-loader
        )
        ;;
    2)
        echo -e "${GREEN}Selected: AMD RADV (mesa only, recommended)${NC}"
        VULKAN_PKGS=(
            mesa lib32-mesa
            vulkan-radeon lib32-vulkan-radeon
            vulkan-icd-loader lib32-vulkan-icd-loader
        )
        ;;
    3)
        echo -e "${GREEN}Selected: NVIDIA proprietary${NC}"
        VULKAN_PKGS=(
            nvidia nvidia-utils lib32-nvidia-utils
            vulkan-icd-loader lib32-vulkan-icd-loader
        )
        ;;
    4)
        echo -e "${GREEN}Selected: NVIDIA open (kernel module)${NC}"
        VULKAN_PKGS=(
            nvidia-open nvidia-utils lib32-nvidia-utils
            vulkan-icd-loader lib32-vulkan-icd-loader
        )
        ;;
    5)
        echo -e "${GREEN}Selected: Intel${NC}"
        VULKAN_PKGS=(
            mesa lib32-mesa
            vulkan-intel lib32-vulkan-intel
            intel-media-driver
            vulkan-icd-loader lib32-vulkan-icd-loader
        )
        ;;
    6)
        echo -e "${YELLOW}Skipping Vulkan driver installation.${NC}"
        VULKAN_PKGS=()
        ;;
    *)
        echo -e "${RED}Invalid choice, skipping Vulkan.${NC}"
        VULKAN_PKGS=()
        ;;
esac

# -------------------------------
# 2. ENABLE MULTILIB (required for Steam + 32-bit Vulkan)
# -------------------------------
echo -e "${YELLOW}Enabling multilib repository (required for Steam)...${NC}"
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo tee -a /etc/pacman.conf >/dev/null <<'MULTILIB'

[multilib]
Include = /etc/pacman.d/mirrorlist
MULTILIB
    echo -e "${GREEN}multilib enabled.${NC}"
else
    echo -e "${GREEN}multilib already enabled.${NC}"
fi

sudo pacman -Syu --noconfirm

# -------------------------------
# 3. INSTALL BASE PACKAGES
# -------------------------------
echo -e "${YELLOW}Installing base packages...${NC}"
sudo pacman -S --needed --noconfirm \
    bluez bluez-utils \
    retroarch retroarch-assets-xmb retroarch-assets-ozone \
    xorg-server xorg-xinit xorg-xinput xorg-xrandr \
    dialog antimicrox onboard \
    python-evdev python-uinput \
    wget curl unzip neovim tmux \
    rfkill || echo -e "${YELLOW}Some base packages failed, continuing...${NC}"

# -------------------------------
# 4. INSTALL VULKAN PACKAGES
# -------------------------------
if [ ${#VULKAN_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Installing Vulkan packages: ${VULKAN_PKGS[*]}${NC}"
    sudo pacman -S --needed --noconfirm "${VULKAN_PKGS[@]}" || \
        echo -e "${YELLOW}Some Vulkan packages failed, continuing...${NC}"
fi

# -------------------------------
# 5. INSTALL STEAM
# -------------------------------
echo -e "${YELLOW}Installing Steam...${NC}"
sudo pacman -S --needed --noconfirm steam || {
    echo -e "${RED}Steam installation failed. Make sure multilib is enabled and synced.${NC}"
}

# -------------------------------
# 6. UINPUT & PERMISSIONS
# -------------------------------
echo -e "${YELLOW}Configuring uinput permissions...${NC}"
sudo modprobe uinput || true

if [ -d /etc/modules-load.d ]; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
fi

sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

if getent group bluetooth >/dev/null; then
    sudo usermod -aG bluetooth "$USER_NAME" || true
fi
sudo usermod -aG input "$USER_NAME" || true
sudo usermod -aG video "$USER_NAME" || true

sudo udevadm control --reload-rules || true
sudo udevadm trigger || true

# -------------------------------
# 7. CONTROLLER MAPPER (Python)
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

BTN_MAP_COMMON = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
    307: uinput.KEY_BACKSPACE,
    308: uinput.KEY_SPACE,
    544: uinput.KEY_UP,
    545: uinput.KEY_DOWN,
    546: uinput.KEY_LEFT,
    547: uinput.KEY_RIGHT
}

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
# 8. BOOT MENU
# -------------------------------
echo -e "${YELLOW}Creating Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash

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
    local mem
    mem=$(free -h --si 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')
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

    STEAM=$(detect_steam || true)
    if [ -n "$STEAM" ]; then
        ITEMS+=($i "Steam (Big Picture)")
        ACTIONS+=("steam:$STEAM")
        ((i++))

        ITEMS+=($i "Steam (Normal Mode)")
        ACTIONS+=("steam_normal:$STEAM")
        ((i++))
    fi

    while IFS='|' read -r name exec_cmd; do
        ITEMS+=($i "Desktop: $name")
        ACTIONS+=("session:$exec_cmd")
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
    CHOICE=$($DIALOG_TOOL --backtitle "SGBU | v0.0.4-arch | $SYSINFO" \
        --menu "Select Action" 22 70 14 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        steam:*)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            xinit ${ACTION#steam:} -bigpicture -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/steam.log"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        steam_normal:*)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            xinit ${ACTION#steam_normal:} -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/steam.log"
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
                echo "2. Type 'scan on' to discover devices."
                echo "3. Type 'pair <MAC>' to pair."
                echo "4. Type 'trust <MAC>' to auto-connect later."
                echo "5. Type 'connect <MAC>' to connect now."
                echo "6. Type 'exit' to return to menu."
                echo ""
                bluetoothctl
            else
                echo -e "${RED}bluetoothctl not found. Is BlueZ installed?${NC}"
                read -rp "Press Enter..."
            fi
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        session:*)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            SESSION_EXEC="${ACTION#session:}"
            cat > "$HOME/.xinitrc" << XINITRC
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=\$HOME/.Xauthority
command -v antimicrox >/dev/null && antimicrox --hidden &
command -v onboard >/dev/null && onboard &
exec $SESSION_EXEC
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
            [ -x /usr/local/bin/diagnostic.sh ] && /usr/local/bin/diagnostic.sh || echo "Diagnostic not found"
            read -rp "Press Enter to continue..."
            ;;
        reboot) sudo reboot ;;
        shutdown) sudo shutdown now ;;
    esac
done
EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# 9. DIAGNOSTIC SCRIPT
# -------------------------------
echo -e "${YELLOW}Creating Diagnostic Script...${NC}"
sudo tee "$DIAGNOSTIC" >/dev/null << 'EOF'
#!/usr/bin/env bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=============================="
echo -e "  SGBU SYSTEM DIAGNOSTICS"
echo -e "==============================${NC}"

# GPU / Vulkan
echo -e "\n${CYAN}[Vulkan / GPU]${NC}"
if command -v vulkaninfo >/dev/null; then
    GPU=$(vulkaninfo 2>/dev/null | grep 'deviceName' | head -n1 | awk -F= '{print $2}' | xargs)
    echo -e "${GREEN}✓${NC} Vulkan device: ${GPU:-unknown}"
else
    echo -e "${YELLOW}!${NC} vulkan-tools not installed (run: pacman -S vulkan-tools)"
fi
if command -v glxinfo >/dev/null; then
    RENDERER=$(glxinfo 2>/dev/null | grep 'OpenGL renderer' | awk -F: '{print $2}' | xargs)
    echo -e "${GREEN}✓${NC} OpenGL renderer: ${RENDERER:-unknown}"
fi

# Steam
echo -e "\n${CYAN}[Steam]${NC}"
if command -v steam >/dev/null || [ -x "$HOME/.steam/steam/steam.sh" ]; then
    echo -e "${GREEN}✓${NC} Steam found"
else
    echo -e "${RED}✗${NC} Steam not found"
fi

# Bluetooth
echo -e "\n${CYAN}[Bluetooth]${NC}"
if command -v bluetoothctl >/dev/null; then
    echo -e "${GREEN}✓${NC} BlueZ installed"
    if systemctl is-active --quiet bluetooth; then
        echo -e "${GREEN}✓${NC} Bluetooth service running"
    else
        echo -e "${RED}✗${NC} Bluetooth service NOT running — try: sudo systemctl start bluetooth"
    fi
else
    echo -e "${RED}✗${NC} BlueZ not found"
fi

# Xorg
echo -e "\n${CYAN}[X Server]${NC}"
command -v Xorg >/dev/null && echo -e "${GREEN}✓${NC} Xorg installed" || echo -e "${RED}✗${NC} Xorg missing"

# RetroArch
echo -e "\n${CYAN}[RetroArch]${NC}"
command -v retroarch >/dev/null && echo -e "${GREEN}✓${NC} RetroArch installed" || echo -e "${RED}✗${NC} RetroArch missing"

# Input devices
echo -e "\n${CYAN}[Input Devices]${NC}"
if ls /dev/input/event* >/dev/null 2>&1; then
    COUNT=$(ls /dev/input/event* | wc -l)
    echo -e "${GREEN}✓${NC} $COUNT input device(s) detected"
else
    echo -e "${RED}✗${NC} No input devices found"
fi

echo -e "\n${CYAN}Done.${NC}"
EOF
sudo chmod +x "$DIAGNOSTIC"

# -------------------------------
# 10. AUTOLOGIN & DISPLAY MANAGER
# -------------------------------
if command -v systemctl >/dev/null; then
    echo -e "${YELLOW}Configuring Autologin on TTY1...${NC}"
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reload

    for dm in gdm sddm lightdm lxdm; do
        if systemctl is-enabled "$dm" >/dev/null 2>&1; then
            sudo systemctl disable "$dm" 2>/dev/null && echo "Disabled $dm"
        fi
    done
fi

# -------------------------------
# 11. BLUETOOTH SERVICE
# -------------------------------
echo -e "${YELLOW}Configuring Bluetooth service...${NC}"
sudo systemctl enable bluetooth.service 2>/dev/null || true
sudo systemctl start bluetooth.service 2>/dev/null || true

if command -v rfkill >/dev/null; then
    sudo rfkill unblock bluetooth 2>/dev/null || true
fi

if command -v bluetoothctl >/dev/null; then
    printf 'power on\nagent on\ndefault-agent\n' | sudo bluetoothctl || true
fi

# -------------------------------
# 12. SHELL TRIGGER
# -------------------------------
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"
TRIGGER='[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh'
if ! grep -q "bootmenu.sh" "$TARGET_PROFILE" 2>/dev/null; then
    echo "$TRIGGER" >> "$TARGET_PROFILE"
fi

# -------------------------------
# 13. RETROARCH CORES
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
# DONE
# -------------------------------
echo -e "\n${CYAN}================================================"
echo -e "   INSTALLATION COMPLETE"
echo -e "================================================${NC}"
echo -e "${GREEN}✓${NC} Boot menu:   $BOOTMENU"
echo -e "${GREEN}✓${NC} Steam:       installed"
echo -e "${GREEN}✓${NC} Vulkan:      choice applied (option $VULKAN_CHOICE)"
echo -e "${GREEN}✓${NC} Bluetooth:   enabled & started"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} You must REBOOT for group permissions to apply."
echo "On next boot the menu will load automatically on TTY1."
echo "Steam Big Picture and Normal Mode are both available in the menu."
echo ""
read -r -p "Press Enter to finish..."
