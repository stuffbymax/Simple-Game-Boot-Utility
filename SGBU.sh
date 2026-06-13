#!/usr/bin/env bash
# created BY marinP/stuffbymax (Multi-Distro fork)
# description: Installer script for Simple Game Boot Utility (SGBU) - Multi-Distro Edition
# Supports: Arch Linux, Debian/Ubuntu, Gentoo
# License: MIT
# version 0.0.6.0 - GamepadUI, Multi-Distro, Steam + Vulkan driver selection
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
echo -e "   Simple Game Boot INSTALLER v0.0.6"
echo -e "   Multi-Distro Edition"
echo -e "================================================${NC}"
echo "Includes: Steam (GamepadUI), Vulkan driver selection, Bluetooth, Controller Mapping"
echo ""

# -------------------------------
# DISTRO DETECTION
# -------------------------------
detect_distro() {
    if command -v pacman >/dev/null 2>&1; then
        echo "arch"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "debian"
    elif command -v emerge >/dev/null 2>&1; then
        echo "gentoo"
    else
        echo "unknown"
    fi
}

DISTRO="$(detect_distro)"

case "$DISTRO" in
    arch)
        echo -e "${GREEN}Detected: Arch Linux${NC}"
        ;;
    debian)
        echo -e "${GREEN}Detected: Debian/Ubuntu${NC}"
        ;;
    gentoo)
        echo -e "${GREEN}Detected: Gentoo Linux${NC}"
        ;;
    *)
        echo -e "${RED}Unsupported distribution. This script supports Arch, Debian/Ubuntu, and Gentoo.${NC}"
        exit 1
        ;;
esac

# -------------------------------
# PACKAGE MANAGER HELPERS
# -------------------------------

pkg_update() {
    case "$DISTRO" in
        arch)    sudo pacman -Syu --noconfirm ;;
        debian)  sudo apt-get update && sudo apt-get upgrade -y ;;
        gentoo)  sudo emerge --sync && sudo emerge -uDN @world ;;
    esac
}

pkg_install() {
    # Usage: pkg_install pkg1 pkg2 ...
    case "$DISTRO" in
        arch)    sudo pacman -S --needed --noconfirm "$@" ;;
        debian)  sudo apt-get install -y "$@" ;;
        gentoo)  sudo emerge --ask=n "$@" ;;
    esac
}

pkg_install_optional() {
    # Like pkg_install but failures are non-fatal
    pkg_install "$@" || echo -e "${YELLOW}Some packages failed to install, continuing...${NC}"
}

# -------------------------------
# DISTRO-SPECIFIC PACKAGE MAPS
# -------------------------------

# Returns distro-appropriate package name(s) for a logical group
pkgs_base() {
    case "$DISTRO" in
        arch)
            echo "bluez bluez-utils retroarch retroarch-assets-xmb retroarch-assets-ozone \
                  xorg-server xorg-xinit xorg-xinput xorg-xrandr \
                  dialog antimicrox onboard \
                  python-evdev python-uinput \
                  wget curl unzip neovim tmux rfkill"
            ;;
        debian)
            echo "bluez bluez-utils retroarch \
                  xorg xinit xinput x11-xserver-utils \
                  dialog antimicrox onboard \
                  python3-evdev python3-uinput \
                  wget curl unzip neovim tmux rfkill"
            ;;
        gentoo)
            echo "net-wireless/bluez \
                  games-emulation/retroarch \
                  x11-base/xorg-server x11-apps/xinit x11-apps/xinput x11-apps/xrandr \
                  dev-util/dialog games-util/antimicrox app-accessibility/onboard \
                  dev-python/evdev dev-python/uinput \
                  net-misc/wget net-misc/curl app-arch/unzip app-editors/neovim app-misc/tmux \
                  sys-apps/rfkill"
            ;;
    esac
}

# Vulkan packages per GPU choice per distro
pkgs_vulkan() {
    local choice="$1"
    case "$DISTRO" in
        arch)
            case "$choice" in
                1) echo "mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon amdvlk lib32-amdvlk vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                2) echo "mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                3) echo "nvidia nvidia-utils lib32-nvidia-utils vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                4) echo "nvidia-open nvidia-utils lib32-nvidia-utils vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                5) echo "mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver vulkan-icd-loader lib32-vulkan-icd-loader" ;;
            esac
            ;;
        debian)
            case "$choice" in
                1) echo "mesa-vulkan-drivers libvulkan1 mesa-utils amdvlk vulkan-tools" ;;
                2) echo "mesa-vulkan-drivers libvulkan1 mesa-utils vulkan-tools" ;;
                3) echo "nvidia-driver nvidia-vulkan-icd libvulkan1 vulkan-tools" ;;
                4) echo "nvidia-open-dkms nvidia-vulkan-icd libvulkan1 vulkan-tools" ;;
                5) echo "mesa-vulkan-drivers intel-media-va-driver libvulkan1 vulkan-tools" ;;
            esac
            ;;
        gentoo)
            case "$choice" in
                1) echo "media-libs/mesa dev-util/vulkan-headers media-libs/vulkan-loader x11-drivers/amdgpu-pro-vulkan" ;;
                2) echo "media-libs/mesa dev-util/vulkan-headers media-libs/vulkan-loader" ;;
                3) echo "x11-drivers/nvidia-drivers media-libs/vulkan-loader dev-util/vulkan-headers" ;;
                4) echo "x11-drivers/nvidia-drivers media-libs/vulkan-loader dev-util/vulkan-headers" ;;
                5) echo "media-libs/mesa dev-util/vulkan-headers media-libs/vulkan-loader" ;;
            esac
            ;;
    esac
}

pkgs_steam() {
    case "$DISTRO" in
        arch)   echo "steam" ;;
        debian) echo "steam-installer" ;;
        gentoo) echo "games-util/steam-launcher" ;;
    esac
}

pkgs_blueman() {
    case "$DISTRO" in
        arch)   echo "blueman" ;;
        debian) echo "blueman" ;;
        gentoo) echo "net-wireless/blueman" ;;
    esac
}

# -------------------------------
# CONFIRM
# -------------------------------
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
echo "  1) AMD       - amdvlk + mesa/RADV            (RADV is included via mesa)"
echo "  2) AMD RADV  - mesa only                      (open-source, recommended for most AMD)"
echo "  3) NVIDIA    - proprietary                    (Maxwell/Pascal/Turing/Ampere+)"
echo "  4) NVIDIA (open) - open-source kernel module  (Turing+)"
echo "  5) Intel     - mesa + intel-media-driver      (Iris Xe / Arc)"
echo "  6) Skip      - I'll install Vulkan drivers manually"
echo ""
read -r -p "Enter choice [1-6]: " VULKAN_CHOICE

VULKAN_PKGS=()
case "$VULKAN_CHOICE" in
    1) echo -e "${GREEN}Selected: AMD (amdvlk + mesa/RADV)${NC}"    ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 1)" ;;
    2) echo -e "${GREEN}Selected: AMD RADV (mesa only)${NC}"         ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 2)" ;;
    3) echo -e "${GREEN}Selected: NVIDIA proprietary${NC}"            ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 3)" ;;
    4) echo -e "${GREEN}Selected: NVIDIA open (kernel module)${NC}"   ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 4)" ;;
    5) echo -e "${GREEN}Selected: Intel${NC}"                         ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 5)" ;;
    6) echo -e "${YELLOW}Skipping Vulkan driver installation.${NC}"   ; VULKAN_PKGS=() ;;
    *) echo -e "${RED}Invalid choice, skipping Vulkan.${NC}"          ; VULKAN_PKGS=() ;;
esac

# -------------------------------
# 2. DISTRO-SPECIFIC SETUP
# -------------------------------
echo -e "${YELLOW}Performing distro-specific pre-install setup...${NC}"

case "$DISTRO" in
    arch)
        # Enable multilib (required for Steam 32-bit libs)
        echo -e "${YELLOW}Enabling multilib repository...${NC}"
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
        ;;

    debian)
        # Enable 32-bit architecture and non-free repos (needed for Steam / Nvidia)
        echo -e "${YELLOW}Enabling i386 (multiarch) and non-free repos...${NC}"
        sudo dpkg --add-architecture i386
        # Add contrib/non-free if not already present (best-effort)
        if ! grep -qE 'non-free|contrib' /etc/apt/sources.list 2>/dev/null; then
            echo -e "${YELLOW}Note: contrib/non-free may be required for Steam/NVIDIA. Edit /etc/apt/sources.list if packages are missing.${NC}"
        fi
        # Ubuntu: enable universe/multiverse
        if command -v add-apt-repository >/dev/null 2>&1; then
            sudo add-apt-repository -y universe 2>/dev/null || true
            sudo add-apt-repository -y multiverse 2>/dev/null || true
        fi
        sudo apt-get update
        ;;

    gentoo)
        # Sync portage tree
        echo -e "${YELLOW}Syncing Portage tree...${NC}"
        sudo emerge --sync
        # Remind user about USE flags for Vulkan / Steam
        echo -e "${YELLOW}Gentoo note: You may need to set USE flags for Vulkan/Steam support."
        echo -e "Example: echo 'media-libs/mesa vulkan' >> /etc/portage/package.use/sgbu${NC}"
        echo -e "${YELLOW}Also ensure ACCEPT_KEYWORDS contains ~amd64 if needed.${NC}"
        ;;
esac

# -------------------------------
# 3. INSTALL BASE PACKAGES
# -------------------------------
echo -e "${YELLOW}Installing base packages...${NC}"
IFS=' ' read -ra BASE_PKGS <<< "$(pkgs_base)"
pkg_install_optional "${BASE_PKGS[@]}"

# -------------------------------
# 4. INSTALL VULKAN PACKAGES
# -------------------------------
if [ ${#VULKAN_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Installing Vulkan packages: ${VULKAN_PKGS[*]}${NC}"
    pkg_install_optional "${VULKAN_PKGS[@]}"
fi

# -------------------------------
# 5. INSTALL STEAM
# -------------------------------
echo -e "${YELLOW}Installing Steam...${NC}"
IFS=' ' read -ra STEAM_PKGS <<< "$(pkgs_steam)"
pkg_install_optional "${STEAM_PKGS[@]}" || {
    echo -e "${RED}Steam installation failed. Check your repos/USE flags.${NC}"
}

# Debian: some systems need to run steam-installer interactively once
if [ "$DISTRO" = "debian" ]; then
    echo -e "${YELLOW}Note (Debian/Ubuntu): If Steam shows a licence dialog on first run, accept it manually.${NC}"
fi

# -------------------------------
# 6. UINPUT & PERMISSIONS
# -------------------------------
echo -e "${YELLOW}Configuring uinput permissions...${NC}"
sudo modprobe uinput || true

if [ -d /etc/modules-load.d ]; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
elif [ -d /etc/conf.d ]; then
    # Gentoo OpenRC
    echo "uinput" | sudo tee /etc/conf.d/modules >/dev/null
fi

sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

getent group bluetooth >/dev/null && sudo usermod -aG bluetooth "$USER_NAME" || true
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
                if event.code in (evdev.ecodes.ABS_HAT0X, evdev.ecodes.ABS_HAT0Y):
                    handle_hat(ui, event.code, event.value)
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
# 8. BOOT MENU
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
    for steam_path in \
        "$HOME/.steam/steam/steam.sh" \
        "/usr/bin/steam" \
        "/usr/games/steam" \
        "/usr/lib/steam/steam.sh"; do
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
    <application class="steam" name="steam">
      <decor>no</decor>
      <fullscreen>yes</fullscreen>
      <maximized>yes</maximized>
      <layer>normal</layer>
      <focus>yes</focus>
    </application>
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>
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
xset s off
xset -dpms
xset s noblank
command -v unclutter >/dev/null && unclutter -idle 1 -root &
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export STEAM_FORCE_DESKTOPUI_SCALING=1
export STEAM_GAMEPADUI=1
if command -v xrandr >/dev/null; then
    PRIMARY=\$(xrandr --query | awk '/ connected primary/ {print \$1; exit}')
    [ -z "\$PRIMARY" ] && PRIMARY=\$(xrandr --query | awk '/ connected/ {print \$1; exit}')
    if [ -n "\$PRIMARY" ]; then
        MODE=\$(xrandr | awk '/\*/ {print \$1; exit}')
        [ -n "\$MODE" ] && xrandr --output "\$PRIMARY" --mode "\$MODE"
    fi
fi
openbox &
OB_PID=\$!
sleep 1
exec steam ${steam_flag}
XINITRC

    chmod +x "$HOME/.xinitrc"
    startx -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/steam.log"
    [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
}

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
    CHOICE=$($DIALOG_TOOL --backtitle "SGBU | v0.0.6-multiDistro | $SYSINFO" \
        --menu "Select Action" 22 70 14 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        steam_gamepadui:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            launch_steam_xinitrc "-gamepadui -fullscreen"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        steam_normal:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            launch_steam_xinitrc "-fullscreen"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        retroarch)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            retroarch -f 2>&1 | tee -a "$HOME/retroarch.log"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        bluetooth)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            if command -v blueman-manager >/dev/null; then
                if [ -z "${DISPLAY:-}" ]; then
                    cat > "$HOME/.xinitrc.bt" <<'BTRC'
#!/bin/sh
xset s off
xset -dpms
openbox &
sleep 0.5
blueman-manager
BTRC
                    chmod +x "$HOME/.xinitrc.bt"
                    xinit "$HOME/.xinitrc.bt" -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/blueman.log"
                else
                    blueman-manager &
                    wait $!
                fi
            else
                echo -e "${RED}blueman not found.${NC}"
                read -rp "Press Enter..."
            fi
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        session:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
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
        reboot)   sudo reboot ;;
        shutdown) sudo shutdown now ;;
    esac
done
BOOTMENU_EOF
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

# Detect distro for hints
if command -v pacman >/dev/null 2>&1; then
    DISTRO="arch"
    PKG_HINT="pacman -S vulkan-tools"
elif command -v apt-get >/dev/null 2>&1; then
    DISTRO="debian"
    PKG_HINT="apt-get install vulkan-tools"
elif command -v emerge >/dev/null 2>&1; then
    DISTRO="gentoo"
    PKG_HINT="emerge dev-util/vulkan-tools"
else
    DISTRO="unknown"
    PKG_HINT="your package manager"
fi

echo -e "${CYAN}=============================="
echo -e "  SGBU SYSTEM DIAGNOSTICS"
echo -e "  Distro: $DISTRO"
echo -e "==============================${NC}"

echo -e "\n${CYAN}[Vulkan / GPU]${NC}"
if command -v vulkaninfo >/dev/null; then
    GPU=$(vulkaninfo 2>/dev/null | grep 'deviceName' | head -n1 | awk -F= '{print $2}' | xargs)
    echo -e "${GREEN}✓${NC} Vulkan device: ${GPU:-unknown}"
else
    echo -e "${YELLOW}!${NC} vulkan-tools not installed (run: $PKG_HINT)"
fi
if command -v glxinfo >/dev/null; then
    RENDERER=$(glxinfo 2>/dev/null | grep 'OpenGL renderer' | awk -F: '{print $2}' | xargs)
    echo -e "${GREEN}✓${NC} OpenGL renderer: ${RENDERER:-unknown}"
fi

echo -e "\n${CYAN}[Steam]${NC}"
if command -v steam >/dev/null || [ -x "$HOME/.steam/steam/steam.sh" ]; then
    echo -e "${GREEN}✓${NC} Steam found"
    STEAM_VER=$(steam --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1 || echo "unknown")
    echo -e "${GREEN}✓${NC} Steam version: $STEAM_VER"
else
    echo -e "${RED}✗${NC} Steam not found"
fi

echo -e "\n${CYAN}[Bluetooth]${NC}"
if command -v bluetoothctl >/dev/null; then
    echo -e "${GREEN}✓${NC} BlueZ installed"
    if systemctl is-active --quiet bluetooth 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Bluetooth service running"
    elif rc-service bluetooth status >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Bluetooth service running (OpenRC)"
    else
        echo -e "${RED}✗${NC} Bluetooth service NOT running"
    fi
else
    echo -e "${RED}✗${NC} BlueZ not found"
fi

echo -e "\n${CYAN}[X Server]${NC}"
command -v Xorg >/dev/null && echo -e "${GREEN}✓${NC} Xorg installed" || echo -e "${RED}✗${NC} Xorg missing"

echo -e "\n${CYAN}[RetroArch]${NC}"
command -v retroarch >/dev/null && echo -e "${GREEN}✓${NC} RetroArch installed" || echo -e "${RED}✗${NC} RetroArch missing"

echo -e "\n${CYAN}[Input Devices]${NC}"
if ls /dev/input/event* >/dev/null 2>&1; then
    COUNT=$(ls /dev/input/event* | wc -l)
    echo -e "${GREEN}✓${NC} $COUNT input device(s) detected"
else
    echo -e "${RED}✗${NC} No input devices found"
fi

echo -e "\n${CYAN}[Init System]${NC}"
if command -v systemctl >/dev/null && systemctl --version >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} systemd detected"
elif command -v rc-service >/dev/null; then
    echo -e "${GREEN}✓${NC} OpenRC detected"
else
    echo -e "${YELLOW}!${NC} Init system not identified"
fi

echo -e "\n${CYAN}Done.${NC}"
EOF
sudo chmod +x "$DIAGNOSTIC"

# -------------------------------
# 10. AUTOLOGIN & SERVICE SETUP
# -------------------------------

# Detect init system
use_systemd=false
use_openrc=false
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    use_systemd=true
elif command -v rc-service >/dev/null 2>&1; then
    use_openrc=true
fi

if $use_systemd; then
    echo -e "${YELLOW}Configuring Autologin on TTY1 (systemd)...${NC}"
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

elif $use_openrc; then
    echo -e "${YELLOW}Configuring Autologin on TTY1 (OpenRC / agetty)...${NC}"
    # Gentoo / OpenRC: edit /etc/inittab to autologin
    if [ -f /etc/inittab ]; then
        if ! grep -q "autologin" /etc/inittab; then
            sudo sed -i "s|^c1:.*agetty.*tty1.*|c1:12345:respawn:/sbin/agetty --autologin $USER_NAME --noclear tty1 38400 linux|" /etc/inittab
            echo -e "${GREEN}inittab updated for autologin.${NC}"
        else
            echo -e "${GREEN}Autologin already set in inittab.${NC}"
        fi
    else
        echo -e "${YELLOW}Could not find /etc/inittab — configure autologin manually.${NC}"
    fi
fi

# -------------------------------
# 11. BLUETOOTH SERVICE
# -------------------------------
echo -e "${YELLOW}Configuring Bluetooth service...${NC}"

if $use_systemd; then
    sudo systemctl enable bluetooth.service 2>/dev/null || true
    sudo systemctl start bluetooth.service 2>/dev/null || true
elif $use_openrc; then
    sudo rc-update add bluetooth default 2>/dev/null || true
    sudo rc-service bluetooth start 2>/dev/null || true
fi

command -v rfkill >/dev/null && sudo rfkill unblock bluetooth 2>/dev/null || true

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
echo -e "   Distro: $DISTRO"
echo -e "================================================${NC}"
echo -e "${GREEN}✓${NC} Boot menu:   $BOOTMENU"
echo -e "${GREEN}✓${NC} Steam:       installed (GamepadUI enabled)"
echo -e "${GREEN}✓${NC} Vulkan:      choice applied (option $VULKAN_CHOICE)"
echo -e "${GREEN}✓${NC} Bluetooth:   enabled & started"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} You must REBOOT for group permissions to apply."
echo "On next boot the menu will load automatically on TTY1."

if [ "$DISTRO" = "gentoo" ]; then
    echo ""
    echo -e "${YELLOW}Gentoo notes:${NC}"
    echo "  - Check USE flags for mesa/vulkan in /etc/portage/package.use/"
    echo "  - If using OpenRC, verify autologin in /etc/inittab"
    echo "  - python-uinput may need to be installed via pip if not in portage:"
    echo "    pip install python-uinput"
fi

if [ "$DISTRO" = "debian" ]; then
    echo ""
    echo -e "${YELLOW}Debian/Ubuntu notes:${NC}"
    echo "  - For NVIDIA: you may need linux-headers and dkms installed first"
    echo "  - Steam may prompt for licence acceptance on first launch"
    echo "  - If steam-installer is unavailable, try: sudo apt-get install steam"
fi

echo ""
read -r -p "Press Enter to finish..."
