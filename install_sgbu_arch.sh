#!/usr/bin/env bash
# created BY marinP/stuffbymax (Arch-only fork)
# description: Installer script for Simple Game Boot Utility (SGBU) - Arch Linux Edition
# License: MIT
# version 0.0.6.0 - GamepadUI, Arch-only, Steam + Vulkan driver selection, bundled RetroArch/AntiMicroX configs, PS4 BT fix
#
# NOTE: This script expects to be run from inside a clone of the SGBU repo,
# with "conf" and "ps4-fix.sh" sitting next to it. If they're missing,
# the related steps are skipped automatically.
set -euo pipefail

# -------------------------------
# CONFIGURATION & PATHS
# -------------------------------
USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
DIAGNOSTIC="/usr/local/bin/diagnostic.sh"
LOG_FILE="$HOME/install_log.txt"

# Directory this script lives in, and the bundled conf/ps4-fix files next to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$SCRIPT_DIR/conf"
PS4_FIX="$SCRIPT_DIR/ps4-fix.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "   Simple Game Boot INSTALLER v0.0.6 (Arch)"
echo -e "================================================${NC}"
echo "Target: Arch Linux only"
echo "Includes: Steam (GamepadUI), Vulkan driver selection, Bluetooth, Controller Mapping, RetroArch/AntiMicroX configs, PS4 Bluetooth fix"
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
# 2. ENABLE MULTILIB
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
# 6. DEPLOY BUNDLED CONFIG FILES (RetroArch / AntiMicroX)
# -------------------------------
deploy_conf_files() {
    echo -e "${YELLOW}Deploying bundled config files (RetroArch / AntiMicroX)...${NC}"
    echo -e "Looking for conf folder at: ${CONF_DIR}"

    if [ ! -d "$CONF_DIR" ]; then
        echo -e "${YELLOW}!${NC} No 'conf' folder found next to this script."
        echo -e "${YELLOW}!${NC} Make sure you cloned the full repo and are running this script from inside it:"
        echo -e "    git clone https://github.com/stuffbymax/Simple-Game-Boot-Utility.git"
        echo -e "    cd Simple-Game-Boot-Utility"
        echo -e "    ./install_sgbu_arch.sh"
        echo -e "${YELLOW}Skipping RetroArch/AntiMicroX config deployment.${NC}"
        return
    fi

    # RetroArch config
    if [ -d "$CONF_DIR/retroarch" ]; then
        mkdir -p "$HOME/.config/retroarch"
        if [ -f "$HOME/.config/retroarch/retroarch.cfg" ]; then
            BACKUP="$HOME/.config/retroarch/retroarch.cfg.bak.$(date +%s)"
            cp "$HOME/.config/retroarch/retroarch.cfg" "$BACKUP" 2>/dev/null || true
            echo -e "${YELLOW}!${NC} Existing retroarch.cfg backed up to $BACKUP"
        fi
        cp -rT "$CONF_DIR/retroarch" "$HOME/.config/retroarch"
        echo -e "${GREEN}✓${NC} RetroArch config deployed to ~/.config/retroarch"
    else
        echo -e "${YELLOW}!${NC} No conf/retroarch folder in repo, skipping RetroArch config."
    fi

    # AntiMicroX config/profiles
    if [ -d "$CONF_DIR/antimicrox" ]; then
        mkdir -p "$HOME/.config/antimicrox"
        cp -rT "$CONF_DIR/antimicrox" "$HOME/.config/antimicrox"
        echo -e "${GREEN}✓${NC} AntiMicroX profile(s) deployed to ~/.config/antimicrox"
    else
        echo -e "${YELLOW}!${NC} No conf/antimicrox folder in repo, skipping AntiMicroX config."
    fi
}
deploy_conf_files

# -------------------------------
# 7. UINPUT & PERMISSIONS
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
# 8. CONTROLLER MAPPER (Python)
# -------------------------------
echo -e "${YELLOW}Creating Controller Mapper...${NC}"
sudo tee "$PS3_PYTHON" >/dev/null << 'EOF'
#!/usr/bin/env python3
'''
created BY marinP/stuffbymax
description: Gamepad to keyboard mapper - supports PS3, PS4, PS5, Xbox 360, Xbox One, Xbox Series X/S
License: MIT
version: 0.0.4
'''

import evdev
import uinput
import sys
import time

KNOWN_CONTROLLERS = [
    "sony", "playstation", "dualshock", "dualsense", "sixaxis",
    "ps3", "ps4", "ps5", "wireless controller",
    "xbox", "microsoft", "x-box", "xinput", "360 pad",
    "xbox 360", "xbox one", "xbox series",
    "gamepad", "joystick",
]

EXCLUDE_NAMES = [
    "touchpad", "motion", "accelerometer", "gyro",
    "sensor", "rumble", "battery",
]

BTN_MAP_PS3 = {
    304: uinput.KEY_ENTER, 305: uinput.KEY_ESC, 307: uinput.KEY_SPACE, 308: uinput.KEY_BACKSPACE,
    544: uinput.KEY_UP, 545: uinput.KEY_DOWN, 546: uinput.KEY_LEFT, 547: uinput.KEY_RIGHT,
    310: uinput.KEY_TAB, 311: uinput.KEY_F1, 312: uinput.KEY_F2, 313: uinput.KEY_F3,
    314: uinput.KEY_F4, 315: uinput.KEY_F5, 316: uinput.KEY_F6, 317: uinput.KEY_F7, 318: uinput.KEY_F8,
}

BTN_MAP_PS4 = {
    304: uinput.KEY_ENTER, 305: uinput.KEY_ESC, 307: uinput.KEY_SPACE, 308: uinput.KEY_BACKSPACE,
    310: uinput.KEY_TAB, 311: uinput.KEY_F1, 312: uinput.KEY_F2, 313: uinput.KEY_F3,
    314: uinput.KEY_F4, 315: uinput.KEY_F5, 316: uinput.KEY_F6, 317: uinput.KEY_F7,
    318: uinput.KEY_F8, 319: uinput.KEY_F9,
}

BTN_MAP_PS5 = {
    304: uinput.KEY_ENTER, 305: uinput.KEY_ESC, 307: uinput.KEY_SPACE, 308: uinput.KEY_BACKSPACE,
    310: uinput.KEY_TAB, 311: uinput.KEY_F1, 312: uinput.KEY_F2, 313: uinput.KEY_F3,
    314: uinput.KEY_F4, 315: uinput.KEY_F5, 316: uinput.KEY_F6, 317: uinput.KEY_F7,
    318: uinput.KEY_F8, 319: uinput.KEY_F9, 320: uinput.KEY_F10,
}

BTN_MAP_XBOX360 = {
    304: uinput.KEY_ENTER, 305: uinput.KEY_ESC, 307: uinput.KEY_SPACE, 308: uinput.KEY_BACKSPACE,
    310: uinput.KEY_TAB, 311: uinput.KEY_F1,
    314: uinput.KEY_F4, 315: uinput.KEY_F5, 316: uinput.KEY_F6, 317: uinput.KEY_F7, 318: uinput.KEY_F8,
}

BTN_MAP_XBOXONE = {
    304: uinput.KEY_ENTER, 305: uinput.KEY_ESC, 307: uinput.KEY_SPACE, 308: uinput.KEY_BACKSPACE,
    310: uinput.KEY_TAB, 311: uinput.KEY_F1,
    314: uinput.KEY_F4, 315: uinput.KEY_F5, 316: uinput.KEY_F6, 317: uinput.KEY_F7,
    318: uinput.KEY_F8, 706: uinput.KEY_F9,
}

BTN_MAP_XBOXSERIES = {
    304: uinput.KEY_ENTER, 305: uinput.KEY_ESC, 307: uinput.KEY_SPACE, 308: uinput.KEY_BACKSPACE,
    310: uinput.KEY_TAB, 311: uinput.KEY_F1,
    314: uinput.KEY_F4, 315: uinput.KEY_F5, 316: uinput.KEY_F6, 317: uinput.KEY_F7,
    318: uinput.KEY_F8, 706: uinput.KEY_F9, 167: uinput.KEY_F10,
}

def find_controller():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        name_lower = device.name.lower()
        if any(k in name_lower for k in KNOWN_CONTROLLERS):
            if any(ex in name_lower for ex in EXCLUDE_NAMES):
                print(f"[SGBU] Skipping sub-device: {device.name}")
                continue
            caps = device.capabilities()
            if evdev.ecodes.EV_KEY in caps:
                return device
    for device in devices:
        name_lower = device.name.lower()
        if any(ex in name_lower for ex in EXCLUDE_NAMES):
            continue
        caps = device.capabilities()
        if evdev.ecodes.EV_KEY in caps and evdev.ecodes.EV_ABS in caps:
            keys = caps[evdev.ecodes.EV_KEY]
            if len(keys) >= 8:
                return device
    return None

def detect_controller_type(device):
    name_lower = device.name.lower()
    if "dualsense" in name_lower or "ps5" in name_lower:
        print("[SGBU] Detected: PS5 DualSense")
        return "ps5", BTN_MAP_PS5
    elif "dualshock 4" in name_lower or "ps4" in name_lower or "wireless controller" in name_lower:
        print("[SGBU] Detected: PS4 DualShock 4")
        return "ps4", BTN_MAP_PS4
    elif "ps3" in name_lower or "dualshock 3" in name_lower or "sixaxis" in name_lower:
        print("[SGBU] Detected: PS3 DualShock 3 / Sixaxis")
        return "ps3", BTN_MAP_PS3
    elif "series" in name_lower or "xbox series" in name_lower:
        print("[SGBU] Detected: Xbox Series X/S")
        return "xboxseries", BTN_MAP_XBOXSERIES
    elif "xbox one" in name_lower or "xbone" in name_lower:
        print("[SGBU] Detected: Xbox One")
        return "xboxone", BTN_MAP_XBOXONE
    elif "xbox 360" in name_lower or "360 pad" in name_lower or "xinput" in name_lower:
        print("[SGBU] Detected: Xbox 360")
        return "xbox360", BTN_MAP_XBOX360
    elif "xbox" in name_lower or "microsoft" in name_lower or "x-box" in name_lower:
        print(f"[SGBU] Detected: Xbox (generic) — using Xbox One map")
        return "xboxone", BTN_MAP_XBOXONE
    else:
        print(f"[SGBU] Unknown controller '{device.name}', using PS4 button map")
        return "ps4", BTN_MAP_PS4

AXIS_THRESHOLD = 16000
stick_state = {"left_x": 0, "left_y": 0}

def handle_analog(ui, code, value):
    if code == evdev.ecodes.ABS_X:
        stick_state["left_x"] = value
    elif code == evdev.ecodes.ABS_Y:
        stick_state["left_y"] = value
    else:
        return
    lx = stick_state["left_x"]
    ly = stick_state["left_y"]
    if lx < -AXIS_THRESHOLD:
        ui.emit(uinput.KEY_LEFT, 1); ui.emit(uinput.KEY_LEFT, 0)
    elif lx > AXIS_THRESHOLD:
        ui.emit(uinput.KEY_RIGHT, 1); ui.emit(uinput.KEY_RIGHT, 0)
    if ly < -AXIS_THRESHOLD:
        ui.emit(uinput.KEY_UP, 1); ui.emit(uinput.KEY_UP, 0)
    elif ly > AXIS_THRESHOLD:
        ui.emit(uinput.KEY_DOWN, 1); ui.emit(uinput.KEY_DOWN, 0)

def handle_hat(ui, code, value):
    if code == evdev.ecodes.ABS_HAT0Y:
        if value == -1:
            ui.emit(uinput.KEY_UP, 1); ui.emit(uinput.KEY_UP, 0)
        elif value == 1:
            ui.emit(uinput.KEY_DOWN, 1); ui.emit(uinput.KEY_DOWN, 0)
    elif code == evdev.ecodes.ABS_HAT0X:
        if value == -1:
            ui.emit(uinput.KEY_LEFT, 1); ui.emit(uinput.KEY_LEFT, 0)
        elif value == 1:
            ui.emit(uinput.KEY_RIGHT, 1); ui.emit(uinput.KEY_RIGHT, 0)

def main():
    print("[SGBU] Controller mapper v0.0.4 starting...")
    print("[SGBU] Supports: PS3 / PS4 / PS5 / Xbox 360 / Xbox One / Xbox Series X|S")

    device = None
    for attempt in range(10):
        device = find_controller()
        if device:
            break
        print(f"[SGBU] No controller found, retrying ({attempt+1}/10)...")
        time.sleep(2)

    if not device:
        print("[SGBU] No controller found after retries. Exiting.")
        sys.exit(1)

    print(f"[SGBU] Using: {device.path} — {device.name}")

    ctrl_type, btn_map = detect_controller_type(device)

    events = [
        uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
        uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT,
        uinput.KEY_TAB,
        uinput.KEY_F1, uinput.KEY_F2, uinput.KEY_F3, uinput.KEY_F4,
        uinput.KEY_F5, uinput.KEY_F6, uinput.KEY_F7, uinput.KEY_F8,
        uinput.KEY_F9, uinput.KEY_F10,
    ]

    try:
        ui = uinput.Device(events)
    except Exception as e:
        print(f"[SGBU] Failed to create uinput device: {e}")
        print("[SGBU] Make sure uinput module is loaded: sudo modprobe uinput")
        sys.exit(1)

    try:
        device.grab()
        print(f"[SGBU] Controller grabbed ({ctrl_type} mode). Press Ctrl+C to stop.")

        for event in device.read_loop():
            if event.type == evdev.ecodes.EV_KEY:
                key = btn_map.get(event.code)
                if key is not None:
                    ui.emit(key, event.value)

            elif event.type == evdev.ecodes.EV_ABS:
                # HAT D-pad (Xbox always, PS3/some PS4)
                if event.code in (evdev.ecodes.ABS_HAT0X, evdev.ecodes.ABS_HAT0Y):
                    handle_hat(ui, event.code, event.value)
                # Analog stick left stick emulation
                elif event.code in (evdev.ecodes.ABS_X, evdev.ecodes.ABS_Y):
                    handle_analog(ui, event.code, event.value)

    except KeyboardInterrupt:
        print("\n[SGBU] Mapper stopped.")
    except Exception as e:
        print(f"[SGBU] Error: {e}")
    finally:
        try:
            device.ungrab()
        except Exception:
            pass

if __name__ == "__main__":
    main()
EOF
sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# 9. BOOT MENU
# -------------------------------
echo -e "${YELLOW}Creating Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'BOOTMENU_EOF'
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

launch_steam_xinitrc() {
    local steam_flag="$1"

    pkill -f ps3_to_keys.py || true

    mkdir -p "$HOME/.config/openbox"
    cat > "$HOME/.config/openbox/rc.xml" <<'OBCONF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc"
                xmlns:xi="http://www.w3.org/2001/XInclude">

  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>

  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>

  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names><name>Steam</name></names>
    <popupTime>0</popupTime>
  </desktops>

  <theme>
    <keepBorder>no</keepBorder>
  </theme>

  <applications>
    <!-- Force Steam GamepadUI fullscreen, no borders, no titlebar -->
    <application class="steam" name="steam">
      <decor>no</decor>
      <fullscreen>yes</fullscreen>
      <maximized>yes</maximized>
      <layer>normal</layer>
      <focus>yes</focus>
    </application>
    <!-- Catch any other Steam windows (e.g. updates, popups) -->
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>

  <!-- Disable right-click desktop menu -->
  <menu>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
    <applicationIcons>no</applicationIcons>
    <manageDesktops>no</manageDesktops>
  </menu>

</openbox_config>
OBCONF

    cat > "$HOME/.xinitrc" <<XINITRC
#!/bin/sh

# Disable screen blanking and power saving
xset s off
xset -dpms
xset s noblank

# Hide the cursor after 1 second of inactivity
command -v unclutter >/dev/null && unclutter -idle 1 -root &

# Environment
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export STEAM_FORCE_DESKTOPUI_SCALING=1
export STEAM_GAMEPADUI=1

# Force correct resolution
if command -v xrandr >/dev/null; then
    PRIMARY=\$(xrandr --query | awk '/ connected primary/ {print \$1; exit}')
    [ -z "\$PRIMARY" ] && PRIMARY=\$(xrandr --query | awk '/ connected/ {print \$1; exit}')
    if [ -n "\$PRIMARY" ]; then
        MODE=\$(xrandr | awk '/\*/ {print \$1; exit}')
        [ -n "\$MODE" ] && xrandr --output "\$PRIMARY" --mode "\$MODE"
    fi
fi

# Start Openbox first, wait for it to be ready
openbox &
OB_PID=\$!
sleep 1

# Launch Steam under Openbox
exec steam ${steam_flag}
XINITRC

    chmod +x "$HOME/.xinitrc"
    startx -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/steam.log"

    # Restart mapper after Steam exits
    [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
}

# Start mapper
MAPPER_PID=""
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
        ITEMS+=($i "Steam (GamepadUI)")
        ACTIONS+=("steam_gamepadui:$STEAM")
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
    CHOICE=$($DIALOG_TOOL --backtitle "SGBU | v0.0.6-arch | $SYSINFO" \
        --menu "Select Action" 22 70 14 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        steam_gamepadui:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            STEAM_BIN="${ACTION#steam_gamepadui:}"
            launch_steam_xinitrc "-gamepadui" "-fullscreen" "$STEAM_BIN"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

        steam_normal:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            STEAM_BIN="${ACTION#steam_normal:}"
            launch_steam_xinitrc "" "-fullscreen" "$STEAM_BIN"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

        retroarch)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            if [ -f "$HOME/.config/retroarch/retroarch.cfg" ]; then
                retroarch -f --config "$HOME/.config/retroarch/retroarch.cfg" 2>&1 | tee -a "$HOME/retroarch.log"
            else
                retroarch -f 2>&1 | tee -a "$HOME/retroarch.log"
            fi
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

bluetooth)
    [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null

    if command -v blueman-manager >/dev/null; then
        # Launch Openbox + blueman if no display is running
        if [ -z "${DISPLAY:-}" ]; then
            cat > "$HOME/.xinitrc.bt" <<'BTRC'
#!/bin/sh
xset s off
xset -dpms
openbox &
sleep 0.5
blueman-manager
# Return to menu when window is closed
BTRC
            chmod +x "$HOME/.xinitrc.bt"
            xinit "$HOME/.xinitrc.bt" -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/blueman.log"
        else
            # Display already running (e.g. called from within X session)
            blueman-manager &
            wait $!
        fi
    else
        echo -e "${RED}blueman not found. Install with: sudo pacman -S blueman${NC}"
        read -rp "Press Enter..."
    fi

    [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
    ;;

        session:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            SESSION_EXEC="${ACTION#session:}"
            ANTIMICROX_PROFILE=$(find "$HOME/.config/antimicrox" -maxdepth 1 -type f \( -iname "*.amgp" -o -iname "*.gamecontroller.amgp" \) 2>/dev/null | head -n1)
            cat > "$HOME/.xinitrc" << XINITRC
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=\$HOME/.Xauthority
if command -v antimicrox >/dev/null; then
    if [ -n "$ANTIMICROX_PROFILE" ]; then
        antimicrox --profile "$ANTIMICROX_PROFILE" --hidden &
    else
        antimicrox --hidden &
    fi
fi
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

        reboot)  sudo reboot ;;
        shutdown) sudo shutdown now ;;
    esac
done
BOOTMENU_EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# 10. DIAGNOSTIC SCRIPT
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
    STEAM_VER=$(steam --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1 || echo "unknown")
    echo -e "${GREEN}✓${NC} Steam version: $STEAM_VER"
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
if [ -f "$HOME/.config/retroarch/retroarch.cfg" ]; then
    echo -e "${GREEN}✓${NC} retroarch.cfg present at ~/.config/retroarch/retroarch.cfg"
else
    echo -e "${YELLOW}!${NC} No retroarch.cfg found (bundled config was not deployed)"
fi

# AntiMicroX
echo -e "\n${CYAN}[AntiMicroX]${NC}"
command -v antimicrox >/dev/null && echo -e "${GREEN}✓${NC} AntiMicroX installed" || echo -e "${RED}✗${NC} AntiMicroX missing"
AMGP_COUNT=$(find "$HOME/.config/antimicrox" -maxdepth 1 -type f \( -iname "*.amgp" -o -iname "*.gamecontroller.amgp" \) 2>/dev/null | wc -l)
if [ "$AMGP_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $AMGP_COUNT AntiMicroX profile(s) found in ~/.config/antimicrox"
else
    echo -e "${YELLOW}!${NC} No AntiMicroX profile found (bundled config was not deployed)"
fi

# Input devices
echo -e "\n${CYAN}[Input Devices]${NC}"
if ls /dev/input/event* >/dev/null 2>&1; then
    COUNT=$(ls /dev/input/event* | wc -l)
    echo -e "${GREEN}✓${NC} $COUNT input device(s) detected"
else
    echo -e "${RED}✗${NC} No input devices found"
fi

# GamepadUI check
echo -e "\n${CYAN}[GamepadUI]${NC}"
if steam --help 2>&1 | grep -q 'gamepadui' 2>/dev/null; then
    echo -e "${GREEN}✓${NC} -gamepadui flag supported"
else
    echo -e "${YELLOW}!${NC} Could not verify -gamepadui flag (Steam may still support it)"
fi

echo -e "\n${CYAN}Done.${NC}"
EOF
sudo chmod +x "$DIAGNOSTIC"

# -------------------------------
# 11. AUTOLOGIN & DISPLAY MANAGER
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
# 12. BLUETOOTH SERVICE
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
# 13. PS4 CONTROLLER BLUETOOTH FIX
# -------------------------------
run_ps4_fix() {
    if [ ! -f "$PS4_FIX" ]; then
        echo -e "${YELLOW}!${NC} ps4-fix.sh not found next to this script ($SCRIPT_DIR) — skipping. Make sure you cloned the full repo."
        return
    fi

    echo ""
    echo -e "${CYAN}================================================"
    echo -e "   PS4 CONTROLLER BLUETOOTH FIX"
    echo -e "================================================${NC}"
    echo "This reloads the hid_sony kernel module and walks you through"
    echo "pairing a DualShock 4 over Bluetooth (fixes touchpad/button issues)."
    read -r -p "Run ps4-fix.sh now? [y/N]: " PS4_FIX_CONFIRM
    if [[ "${PS4_FIX_CONFIRM,,}" == "y" ]]; then
        echo -e "${YELLOW}Running ps4-fix.sh...${NC}"
        bash "$PS4_FIX" || echo -e "${YELLOW}ps4-fix.sh exited with an error — continuing installer...${NC}"
    else
        echo -e "${YELLOW}Skipping PS4 controller Bluetooth fix. You can run it later with: bash $PS4_FIX${NC}"
    fi
}
run_ps4_fix

# -------------------------------
# 14. SHELL TRIGGER
# -------------------------------
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"
TRIGGER='[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh'
if ! grep -q "bootmenu.sh" "$TARGET_PROFILE" 2>/dev/null; then
    echo "$TRIGGER" >> "$TARGET_PROFILE"
fi

# -------------------------------
# 15. RETROARCH CORES
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
echo -e "${GREEN}✓${NC} Steam:       installed (GamepadUI enabled)"
echo -e "${GREEN}✓${NC} Vulkan:      choice applied (option $VULKAN_CHOICE)"
echo -e "${GREEN}✓${NC} Bluetooth:   enabled & started"
if [ -d "$CONF_DIR" ]; then
    echo -e "${GREEN}✓${NC} Bundled configs: deployed from $CONF_DIR"
else
    echo -e "${YELLOW}!${NC} Bundled configs: skipped (no ./conf folder found — clone the full repo)"
fi
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} You must REBOOT for group permissions to apply."
echo "On next boot the menu will load automatically on TTY1."
echo "Steam GamepadUI and Normal Mode are both available in the menu."
echo ""
read -r -p "Press Enter to finish..."
