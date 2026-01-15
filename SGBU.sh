#!/usr/bin/env bash
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
echo "The program may not install PKGs for other distros than debian"
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
                x11-xserver-utils x11-utils || echo "X packages failed"
            
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
            
            # AntiMicroX - try multiple methods
            if ! sudo apt install -y antimicrox 2>/dev/null; then
                echo -e "${YELLOW}AntiMicroX not in repos, trying alternatives...${NC}"
                
                # Try Flatpak
                if command -v flatpak >/dev/null; then
                    flatpak install -y flathub io.github.antimicrox.antimicrox 2>/dev/null && \
                    echo -e "${GREEN}AntiMicroX installed via Flatpak${NC}" || \
                    echo -e "${YELLOW}Flatpak install failed${NC}"
                else
                    echo -e "${YELLOW}Consider installing Flatpak for AntiMicroX${NC}"
                fi
            fi
            
            # Onboard
            sudo apt install -y onboard || echo -e "${YELLOW}Onboard failed - may need manual install${NC}"
            
            # XFCE system tray support
            sudo apt install -y xfce4-panel xfce4-indicator-plugin 2>/dev/null || true
            
            # Utilities
            sudo apt install -y wget curl unzip sudo neovim tmux || echo "Utilities failed"
            ;;
        dnf)
            sudo dnf install -y \
                retroarch \
                xorg-x11-server-Xorg xorg-x11-xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux || echo "Some packages failed"
            ;;
        zypper)
            sudo zypper install -y \
                retroarch \
                xorg-x11-server xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux || echo "Some packages failed"
            ;;
        xbps-install)
            sudo xbps-install -Sy \
                retroarch \
                xorg-minimal xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux || echo "Some packages failed"
            ;;
        apk)
            sudo apk add --no-cache \
                retroarch \
                xorg-server xinit \
                dialog antimicrox onboard \
                py3-evdev py3-uinput \
                wget curl unzip sudo neovim tmux || echo "Some packages failed"
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

# Reload udev rules
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

# 1. Find any controller with buttons
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

# 2. Create uinput device with all mapped keys
events = [
    uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
    uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT
]

try:
    ui = uinput.Device(events)
except Exception as e:
    print(f"Error creating uinput device: {e}")
    print("Make sure you're in the 'input' group and uinput module is loaded")
    sys.exit(1)

# 3. Button mapping dictionaries
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

BTN_MAP_PS4 = {
    304: uinput.KEY_ENTER,      # Cross
    305: uinput.KEY_ESC,        # Circle
    307: uinput.KEY_BACKSPACE,  # Square
    308: uinput.KEY_SPACE,      # Triangle
    544: uinput.KEY_UP,
    545: uinput.KEY_DOWN,
    546: uinput.KEY_LEFT,
    547: uinput.KEY_RIGHT
}

BTN_MAP_XBOX = {
    304: uinput.KEY_ENTER,      # A
    305: uinput.KEY_ESC,        # B
    307: uinput.KEY_BACKSPACE,  # X
    308: uinput.KEY_SPACE,      # Y
    544: uinput.KEY_UP,
    545: uinput.KEY_DOWN,
    546: uinput.KEY_LEFT,
    547: uinput.KEY_RIGHT
}

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

# 4. Choose button map based on controller
if "PLAYSTATION" in device.name.upper() or "PS3" in device.name.upper():
    BTN_MAP = BTN_MAP_PS3
    print("Using PS3 button mapping")
elif "PS4" in device.name.upper() or "PS5" in device.name.upper():
    BTN_MAP = BTN_MAP_PS4
    print("Using PS4/PS5 button mapping")
elif "XBOX" in device.name.upper():
    BTN_MAP = BTN_MAP_XBOX
    print("Using Xbox button mapping")
else:
    BTN_MAP = BTN_MAP_GENERIC_XBOX
    print("Using generic Xbox/gamepad button mapping")

# 5. Grab device and emit key events
try:
    device.grab()
    print("Controller grabbed successfully. Press Ctrl+C to stop.")
    
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
except KeyboardInterrupt:
    print("\nStopping controller mapper...")
except Exception as e:
    print(f"Error in main loop: {e}")
finally:
    device.ungrab()
EOF
sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# 4. ENHANCED BOOT MENU
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

# Determine Dialog tool
DIALOG_TOOL="dialog"
command -v dialog >/dev/null || DIALOG_TOOL="whiptail"

# Controller Mapper Path
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
        "$HOME/.local/share/Steam/steam.sh" \
        "/usr/bin/steam" \
        "/usr/games/steam"; do
        [ -x "$steam_path" ] && echo "$steam_path" && return 0
    done
    return 1
}

get_system_info() {
    local mem=$(free -h --si 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')
    local load=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
    local cpu=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2 + $4"%"}')
    local temp=$(sensors 2>/dev/null | grep "Package id 0" | awk '{print $4}' | sed 's/+//')
    [ -z "$temp" ] && temp="N/A"
    echo "Mem: $mem | Load: $load | CPU: $cpu | Temp: $temp"
}

# Start mapper
if [ -x "$MAPPER" ]; then
    $MAPPER &
    MAPPER_PID=$!
    trap 'kill $MAPPER_PID 2>/dev/null' EXIT
else
    echo -e "${YELLOW}Controller mapper not found or not executable${NC}"
    sleep 2
fi

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    # RetroArch
    if command -v retroarch >/dev/null; then
        ITEMS+=($i "RetroArch")
        ACTIONS+=("retroarch")
        ((i++))
    fi

    # Steam
    STEAM=$(detect_steam)
    if [ -n "$STEAM" ]; then
        ITEMS+=($i "Steam Big Picture")
        ACTIONS+=("steam:$STEAM")
        ((i++))
    fi

    # Desktop Sessions
    while IFS='|' read -r name exec; do
        ITEMS+=($i "Desktop: $name")
        ACTIONS+=("session:$exec")
        ((i++))
    done < <(detect_sessions)

    # Utilities
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
    CHOICE=$($DIALOG_TOOL --backtitle "SGBU | version 0.0.3 | $SYSINFO" --menu "Select Action" 20 70 12 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        steam:*)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            xinit ${ACTION#steam:} -bigpicture -- :0 vt$XDG_VTNR 2>&1 | tee -a "$HOME/steam.log"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        retroarch)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            retroarch -f 2>&1 | tee -a "$HOME/retroarch.log" || {
                echo -e "${RED}Error starting RetroArch${NC}"
                echo "Check $HOME/retroarch.log for details"
                read -p "Press Enter to continue..."
            }
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        session:*)
            [ -n "${MAPPER_PID:-}" ] && kill $MAPPER_PID 2>/dev/null
            
            # Create xinitrc with proper helper app startup
            cat > "$HOME/.xinitrc" << XINITRC
#!/bin/bash

# Set up X environment
export DISPLAY=:0
export XAUTHORITY=\$HOME/.Xauthority

# Wait for X to be ready
sleep 2

# Start helper apps in background
if command -v antimicrox >/dev/null; then
    echo "Starting AntiMicroX..."
    antimicrox --hidden &
    sleep 1
elif flatpak list | grep -q antimicrox; then
    echo "Starting AntiMicroX (Flatpak)..."
    flatpak run io.github.antimicrox.antimicrox --hidden &
    sleep 1
fi

if command -v onboard >/dev/null; then
    echo "Starting Onboard..."
    onboard &
    sleep 1
fi

# Start the desktop session
echo "Starting desktop session: ${ACTION#session:}"
exec ${ACTION#session:}
XINITRC
            
            chmod +x "$HOME/.xinitrc"
            startx 2>&1 | tee -a "$HOME/xsession.log" || {
                echo -e "${RED}Error starting Desktop${NC}"
                echo "Check $HOME/xsession.log and ~/.xsession-errors for details"
                read -p "Press Enter to continue..."
            }
            
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;
        shell)
            clear
            echo -e "${CYAN}Entering shell. Type 'exit' to return to menu.${NC}"
            bash
            ;;
        diagnostic)
            clear
            if [ -x /usr/local/bin/diagnostic.sh ]; then
                /usr/local/bin/diagnostic.sh
            else
                echo -e "${RED}Diagnostic script not found${NC}"
            fi
            read -p "Press Enter to continue..."
            ;;
        reboot)
            sudo reboot
            ;;
        shutdown)
            sudo shutdown now
            ;;
    esac
done
EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# 5. DIAGNOSTIC SCRIPT
# -------------------------------
echo -e "${YELLOW}Creating Diagnostic Script...${NC}"
sudo tee "$DIAGNOSTIC" >/dev/null << 'EOF'
#!/usr/bin/env bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}================================================"
echo -e "   SYSTEM DIAGNOSTICS"
echo -e "================================================${NC}"

# Check X server
echo -e "\n${CYAN}[X Server Check]${NC}"
if command -v Xorg >/dev/null; then
    echo -e "${GREEN}✓${NC} Xorg installed: $(Xorg -version 2>&1 | head -n1)"
else
    echo -e "${RED}✗${NC} Xorg not found"
fi

# Check xinit
if command -v xinit >/dev/null; then
    echo -e "${GREEN}✓${NC} xinit installed"
else
    echo -e "${RED}✗${NC} xinit not found"
fi

# Check RetroArch
echo -e "\n${CYAN}[RetroArch Check]${NC}"
if command -v retroarch >/dev/null; then
    echo -e "${GREEN}✓${NC} RetroArch installed: $(retroarch --version 2>&1 | head -n1)"
    
    # Check cores directory
    CORES_DIR="$HOME/.config/retroarch/cores"
    if [ -d "$CORES_DIR" ]; then
        CORE_COUNT=$(find "$CORES_DIR" -name "*.so" 2>/dev/null | wc -l)
        echo -e "${GREEN}✓${NC} Cores directory exists: $CORE_COUNT cores found"
    else
        echo -e "${YELLOW}!${NC} Cores directory not found: $CORES_DIR"
    fi
else
    echo -e "${RED}✗${NC} RetroArch not found"
fi

# Check AntiMicroX
echo -e "\n${CYAN}[AntiMicroX Check]${NC}"
if command -v antimicrox >/dev/null; then
    echo -e "${GREEN}✓${NC} AntiMicroX installed (system)"
    # Check if it can run
    timeout 2 antimicrox --version >/dev/null 2>&1 && \
        echo -e "${GREEN}✓${NC} AntiMicroX runs successfully" || \
        echo -e "${YELLOW}!${NC} AntiMicroX may have issues running"
elif flatpak list 2>/dev/null | grep -q antimicrox; then
    echo -e "${GREEN}✓${NC} AntiMicroX installed (Flatpak)"
else
    echo -e "${RED}✗${NC} AntiMicroX not found"
    echo "  Install with: sudo apt install antimicrox"
    echo "  Or Flatpak: flatpak install flathub io.github.antimicrox.antimicrox"
fi

# Check Qt5 libraries
echo -e "\n${CYAN}[Qt5 Libraries Check]${NC}"
for lib in libQt5Core.so.5 libQt5Gui.so.5 libQt5Widgets.so.5; do
    if ldconfig -p 2>/dev/null | grep -q "$lib"; then
        echo -e "${GREEN}✓${NC} $lib found"
    else
        echo -e "${RED}✗${NC} $lib not found"
    fi
done

# Check Onboard
echo -e "\n${CYAN}[Onboard Check]${NC}"
if command -v onboard >/dev/null; then
    echo -e "${GREEN}✓${NC} Onboard installed"
else
    echo -e "${RED}✗${NC} Onboard not found"
    echo "  Install with: sudo apt install onboard"
fi

# Check Python dependencies
echo -e "\n${CYAN}[Python Dependencies Check]${NC}"
if command -v python3 >/dev/null; then
    echo -e "${GREEN}✓${NC} Python3 installed: $(python3 --version)"
    
    # Check evdev
    if python3 -c "import evdev" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} python3-evdev installed"
    else
        echo -e "${RED}✗${NC} python3-evdev not found"
        echo "  Install with: sudo apt install python3-evdev"
    fi
    
    # Check uinput
    if python3 -c "import uinput" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} python3-uinput installed"
    else
        echo -e "${RED}✗${NC} python3-uinput not found"
        echo "  Install with: sudo apt install python3-uinput"
        echo "  Or: sudo pip3 install python-uinput"
    fi
else
    echo -e "${RED}✗${NC} Python3 not found"
fi

# Check uinput module
echo -e "\n${CYAN}[uinput Module Check]${NC}"
if lsmod | grep -q uinput; then
    echo -e "${GREEN}✓${NC} uinput module loaded"
else
    echo -e "${YELLOW}!${NC} uinput module not loaded"
    echo "  Load with: sudo modprobe uinput"
fi

if [ -e /dev/uinput ]; then
    echo -e "${GREEN}✓${NC} /dev/uinput exists"
    ls -l /dev/uinput
else
    echo -e "${RED}✗${NC} /dev/uinput not found"
fi

# Check user groups
echo -e "\n${CYAN}[User Groups Check]${NC}"
GROUPS_OUTPUT=$(groups)
if echo "$GROUPS_OUTPUT" | grep -q "input"; then
    echo -e "${GREEN}✓${NC} User in 'input' group"
else
    echo -e "${RED}✗${NC} User NOT in 'input' group"
    echo "  Add with: sudo usermod -aG input $USER"
    echo "  Then logout and login again"
fi

if echo "$GROUPS_OUTPUT" | grep -q "video"; then
    echo -e "${GREEN}✓${NC} User in 'video' group"
else
    echo -e "${YELLOW}!${NC} User NOT in 'video' group (may be needed for X)"
    echo "  Add with: sudo usermod -aG video $USER"
fi

# Check controller
echo -e "\n${CYAN}[Controller Check]${NC}"
CONTROLLER_COUNT=$(ls /dev/input/event* 2>/dev/null | wc -l)
echo "Found $CONTROLLER_COUNT input devices in /dev/input/"

if command -v evtest >/dev/null 2>&1; then
    echo -e "\nListing input devices (first 5):"
    for i in $(seq 0 4); do
        [ -e "/dev/input/event$i" ] && \
        python3 -c "import evdev; d=evdev.InputDevice('/dev/input/event$i'); print(f'/dev/input/event$i: {d.name}')" 2>/dev/null
    done
else
    echo "Install 'evtest' for detailed controller info: sudo apt install evtest"
fi

# Check controller mapper script
echo -e "\n${CYAN}[Controller Mapper Check]${NC}"
if [ -x /usr/local/bin/ps3_to_keys.py ]; then
    echo -e "${GREEN}✓${NC} Controller mapper installed"
else
    echo -e "${RED}✗${NC} Controller mapper not found or not executable"
fi

# Check desktop sessions
echo -e "\n${CYAN}[Desktop Sessions Check]${NC}"
SESSION_COUNT=0
for f in /usr/share/xsessions/*.desktop; do
    [ -f "$f" ] || continue
    SESSION_NAME=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
    echo -e "${GREEN}✓${NC} Found: $SESSION_NAME"
    ((SESSION_COUNT++))
done

if [ $SESSION_COUNT -eq 0 ]; then
    echo -e "${YELLOW}!${NC} No desktop sessions found"
fi

# Check autostart
echo -e "\n${CYAN}[Autostart Check]${NC}"
if [ -d "$HOME/.config/autostart" ]; then
    echo -e "${GREEN}✓${NC} Autostart directory exists"
    if [ -f "$HOME/.config/autostart/antimicrox.desktop" ]; then
        echo -e "${GREEN}✓${NC} AntiMicroX autostart configured"
    else
        echo -e "${YELLOW}!${NC} AntiMicroX autostart not configured"
    fi
    
    if [ -f "$HOME/.config/autostart/onboard.desktop" ]; then
        echo -e "${GREEN}✓${NC} Onboard autostart configured"
    else
        echo -e "${YELLOW}!${NC} Onboard autostart not configured"
    fi
else
    echo -e "${YELLOW}!${NC} Autostart directory doesn't exist"
fi

# Check logs
echo -e "\n${CYAN}[Recent Logs Check]${NC}"
if [ -f "$HOME/.xsession-errors" ]; then
    echo "Last 5 lines of .xsession-errors:"
    tail -n 5 "$HOME/.xsession-errors" 2>/dev/null || echo "Cannot read log"
fi

# Summary
echo -e "\n${CYAN}================================================"
echo -e "   DIAGNOSTIC COMPLETE"
echo -e "================================================${NC}"
echo ""
echo "If you see any ${RED}✗${NC} marks above, those components need attention."
echo "Check the suggestions provided for each failed component."
echo ""
EOF
sudo chmod +x "$DIAGNOSTIC"

# -------------------------------
# 6. AUTOLOGIN (SYSTEMD)
# -------------------------------
if command -v systemctl >/dev/null; then
    echo -e "${YELLOW}Configuring TTY1 Autologin...${NC}"
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin