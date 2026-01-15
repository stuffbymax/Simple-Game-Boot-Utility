#created BY marinP/stuffbymax
#description: Simple Game Boot Utility (setup PKGs, uinput, controller mapping, boot menu)
#version: 0.0.3 - testing
#License: MIT

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
        [py_uinput]=" python3-uinput"
        [retro]="retroarch"
        [utils]="dialog wget curl unzip sudo neovim tmux antimicrox"
        [console]="antimicrox squeekboard onboard "
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
'''
created BY marinP/stuffbymax
description: a tool thats allows user to use gamepad as keyboard
License MIT
'''

import evdev
import uinput
import sys

# 1. Find any controller with buttons
def find_controller():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if evdev.ecodes.EV_KEY in device.capabilities():
            return device
    print("No controller found.")
    sys.exit(1)

device = find_controller()
print(f"Using device: {device.path} ({device.name})")

# 2. Create uinput device with all mapped keys
events = [
    uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
    uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT
]
ui = uinput.Device(events)

# 3. Individual BTN_MAP dictionaries

# PS3
BTN_MAP_PS3 = {
    304: uinput.KEY_ENTER,      # X
    305: uinput.KEY_ESC,        # Circle
    307: uinput.KEY_BACKSPACE,  # Square
    308: uinput.KEY_SPACE,      # Triangle
    544: uinput.KEY_UP,         # D-pad Up
    545: uinput.KEY_DOWN,       # D-pad Down
    546: uinput.KEY_LEFT,       # D-pad Left
    547: uinput.KEY_RIGHT       # D-pad Right
}

# PS4
BTN_MAP_PS4 = {
    304: uinput.KEY_ENTER,      # Cross
    305: uinput.KEY_ESC,        # Circle
    307: uinput.KEY_BACKSPACE,  # Square
    308: uinput.KEY_SPACE,      # Triangle
    544: uinput.KEY_UP,         # D-pad Up
    545: uinput.KEY_DOWN,       # D-pad Down
    546: uinput.KEY_LEFT,       # D-pad Left
    547: uinput.KEY_RIGHT       # D-pad Right
}

# Xbox 360 / One
BTN_MAP_XBOX = {
    304: uinput.KEY_ENTER,      # A
    305: uinput.KEY_ESC,        # B
    307: uinput.KEY_BACKSPACE,  # X
    308: uinput.KEY_SPACE,      # Y
    544: uinput.KEY_UP,         # D-pad Up (for EV_KEY devices)
    545: uinput.KEY_DOWN,       # D-pad Down
    546: uinput.KEY_LEFT,       # D-pad Left
    547: uinput.KEY_RIGHT       # D-pad Right
}

# Generic controller
BTN_MAP_GENERIC = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
    307: uinput.KEY_BACKSPACE,
    308: uinput.KEY_SPACE,
    544: uinput.KEY_UP,
    545: uinput.KEY_DOWN,
    546: uinput.KEY_LEFT,
    547: uinput.KEY_RIGHT
}

# Generic Xbox pad (hat axes)
BTN_MAP_GENERIC_XBOX = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
    307: uinput.KEY_BACKSPACE,
    308: uinput.KEY_SPACE,
    1000: uinput.KEY_UP,        # D-pad Up (ABS_HAT0Y = -1)
    1001: uinput.KEY_DOWN,      # D-pad Down (ABS_HAT0Y = 1)
    1002: uinput.KEY_LEFT,      # D-pad Left (ABS_HAT0X = -1)
    1003: uinput.KEY_RIGHT      # D-pad Right (ABS_HAT0X = 1)
}

# 4. Choose which BTN_MAP to use
# Example: you can select based on device name
if "PLAYSTATION" in device.name.upper() or "PS3" in device.name.upper():
    BTN_MAP = BTN_MAP_PS3
elif "PS4" in device.name.upper():
    BTN_MAP = BTN_MAP_PS4
elif "XBOX" in device.name.upper():
    BTN_MAP = BTN_MAP_XBOX
else:
    BTN_MAP = BTN_MAP_GENERIC_XBOX  # fallback for generic/Xbox controllers

# 5. Grab the device and emit key events
device.grab()
for event in device.read_loop():
    # EV_KEY buttons
    if event.type == evdev.ecodes.EV_KEY:
        key = BTN_MAP.get(event.code)
        if key is not None:
            ui.emit(key, event.value)

    # EV_ABS for generic Xbox D-pad
    elif event.type == evdev.ecodes.EV_ABS:
        if event.code == evdev.ecodes.ABS_HAT0Y:
            if event.value == -1:  # Up
                ui.emit(BTN_MAP.get(1000, uinput.KEY_UP), 1)
                ui.emit(BTN_MAP.get(1000, uinput.KEY_UP), 0)
            elif event.value == 1:  # Down
                ui.emit(BTN_MAP.get(1001, uinput.KEY_DOWN), 1)
                ui.emit(BTN_MAP.get(1001, uinput.KEY_DOWN), 0)
        elif event.code == evdev.ecodes.ABS_HAT0X:
            if event.value == -1:  # Left
                ui.emit(BTN_MAP.get(1002, uinput.KEY_LEFT), 1)
                ui.emit(BTN_MAP.get(1002, uinput.KEY_LEFT), 0)
            elif event.value == 1:  # Right
                ui.emit(BTN_MAP.get(1003, uinput.KEY_RIGHT), 1)
                ui.emit(BTN_MAP.get(1003, uinput.KEY_RIGHT), 0)
EOF
sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# 4. ENHANCED BOOT MENU
# -------------------------------
echo -e "${YELLOW}Creating Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# CONFIG
# -------------------------------
MAPPER="/usr/local/bin/ps3_to_keys.py"
TMP_XINIT="/tmp/sgbu-xinitrc"
export SGBU_RUNNING=1

DIALOG=dialog
command -v dialog >/dev/null || DIALOG=whiptail

# -------------------------------
# HELPERS
# -------------------------------
detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep -m1 '^Name=' "$f" | cut -d= -f2)
        exec=$(grep -m1 '^Exec=' "$f" | cut -d= -f2)
        [ -n "$name" ] && [ -n "$exec" ] && echo "$name|$exec"
    done
}

detect_steam() {
    command -v steam >/dev/null && echo steam && return
    command -v flatpak >/dev/null && flatpak list | grep -qi steam \
        && echo "flatpak run com.valvesoftware.Steam"
}

detect_apps() {
    command -v retroarch >/dev/null && echo "RetroArch|retroarch -f"
    command -v steam >/dev/null && echo "Steam|steam -bigpicture"

    if command -v flatpak >/dev/null &&
       flatpak list | grep -qi steam; then
        echo "Steam (Flatpak)|flatpak run com.valvesoftware.Steam -bigpicture"
    fi
}

launch_x() {
    local cmd="$1"

    cat > "$TMP_XINIT" <<EOF
#!/usr/bin/env bash
antimicrox --hidden &
onboard &
exec $cmd
EOF

    chmod +x "$TMP_XINIT"
    startx "$TMP_XINIT" -- :0
}

# -------------------------------
# CONTROLLER MAPPER
# -------------------------------
"$MAPPER" &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null' EXIT

# -------------------------------
# MENU LOOP
# -------------------------------
while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    # Apps
    while IFS='|' read -r name cmd; do
        ITEMS+=($i "$name")
        ACTIONS+=("app:$cmd")
        ((i++))
    done < <(detect_apps)

    # Sessions
    while IFS='|' read -r name exec; do
        ITEMS+=($i "Desktop: $name")
        ACTIONS+=("session:$exec")
        ((i++))
    done < <(detect_sessions)

    # System
    ITEMS+=(
        $i "Shell"
        $((i+1)) "Reboot"
        $((i+2)) "Shutdown"
    )
    ACTIONS+=("shell" "reboot" "shutdown")

    CHOICE=$($DIALOG --menu "Simple Game Boot" 20 70 15 \
        "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    kill "$MAPPER_PID" 2>/dev/null || true

    case "$ACTION" in
        retroarch)
            kill $MAPPER_PID 2>/dev/null
            retroarch -f || read -p "Error starting RetroArch"
            $MAPPER & MAPPER_PID=$!
            ;;
        session:*)
            kill $MAPPER_PID 2>/dev/null
            echo "exec ${ACTION#session:}" > "$HOME/.xinitrc"
            startx || read -p "Error starting Desktop"
            $MAPPER & MAPPER_PID=$!
            ;;
        reboot)
            systemctl reboot || sudo reboot
            ;;
        shutdown)
            systemctl poweroff || sudo shutdown now
            ;;
    esac

    "$MAPPER" &
    MAPPER_PID=$!
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

echo -e "${GREEN}Boot Menu installation complete.${NC}"
# -------------------------------
# 7. RETROARCH CONFIG & CORES
# -------------------------------
echo -e "${YELLOW}Setting up RetroArch config and downloading cores...${NC}"
cp .conf/ $HOME/.config/

cd "$HOME/.config/retroarch/cores/"
wget -r -np -nd -R "index.html*" https://buildbot.libretro.com/nightly/linux/x86_64/latest/
unzip -o "*.zip"
rm *.zip 

#-------------------------------
#disabling loginmanager
#-------------------------------
echo -e "${YELLOW}Disabling login manager...${NC}"
if command -v systemctl >/dev/null; then
    if systemctl is-active gdm >/dev/null 2>&1; then
        sudo systemctl disable gdm
    elif systemctl is-active sddm >/dev/null 2>&1; then
        sudo systemctl disable sddm
    elif systemctl is-active lightdm >/dev/null 2>&1; then
        sudo systemctl disable lightdm
    fi
fi

# -------------------------------
# FINAL MESSAGE
# -------------------------------

echo "installing retroarch cores"
cp conf "$HOME/.config/"
mkdir -p "$HOME/.config/retroarch/cores"
cd "$HOME/.config/retroarch/cores"
wget -r -np -nd -R "index.html*" https://buildbot.libretro.com/nightly/linux/x86_64/latest/
unzip -o "*.zip"
rm *.zip 
cp .conf/ .config/
echo -e "${GREEN}DONE! Setup complete.${NC}"
echo "1. Your user was added to the 'input' group for the controller mapper."
echo "2. Please reboot for all group changes and autologin to take effect."#
echo "3. remove login manager
    - For GDM (GNOME): sudo systemctl disable gdm
    - For SDDM (KDE): sudo systemctl disable sddm
    - For LightDM: sudo systemctl disable lightdm"
