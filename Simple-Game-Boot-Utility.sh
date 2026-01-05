#note external files are not yet uploaded to github

#!/bin/bash
set -e

exec > >(tee -a ~/log.txt) 2>&1

USER_NAME=$(whoami)
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
ICEWM_MENU="$HOME/.icewm/menu"
AUTOSTART_DIR="$HOME/.config/autostart"
ANTIMICROX_PROFILE="$HOME/.config/antimicrox/bootmenu_gamepad_profile.amgp"
conf="retro/conf"
# -------------------------------
# WARNING / ACKNOWLEDGEMENT
# -------------------------------
echo -e "\e[33mWARNING: This script is experimental and may NOT work as intended!\e[0m"
echo -e "\e[33mKnown issues:\e[0m"
echo -e "\e[33m - Keybindings may be missing or incomplete\e[0m"
echo -e "\e[33m - Drivers are default to Intel only\e you have to change it depending on your GPU[0m"
echo -e "\e[33m - Some features require manual follow-up\e[0m"
echo -e "\e[33m - External files are not yet uploaded to GitHub\e[0m"
echo ""

read -p "Do you want to continue? [y/N]: " CONFIRM
CONFIRM=${CONFIRM,,}  # lowercase
if [[ "$CONFIRM" != "y" ]]; then
    echo "Exiting script. No changes were made."
    exit 1
fi


# === Install required packages ===
sudo apt update
echo "update complete"
sudo apt install -y retroarch icewm xfce4 xfce4-goodies xinit xserver-xorg-core xserver-xorg-input-all dialog sudo antimicrox unzip python3-evdev python3-uinput wget curl neovim tmux
echo "installed necesery software"

echo "installing retro arch assets"
sudo apt -y install retroarch-assets
echo "retro arch assets completed"

# here make script for select your gpu driver.eg. 1. (Intel), 2.(AMD) 3. (Nvidia)
echo -e "please select GPU Driver"
echo -e "1) Intel"
echo -e "2) AMD"
echo -e "3) ATI"
echo -e "4) Nvidia (open source)"
echo -e "5) Nvidia (propriatery)"

read -p "Enter your choice (1 or 5): " choice

case $choice in
    1)
        echo "You selected 1. installing Intel..."
        sudo apt install -y xserver-xorg-video-intel
        ;;
    2)
        echo "You selected 2. installing AMD..."
        sudo apt install -y xserver-xorg-video-amdgpu
        ;;
    3)
        echo "You selected 3. installing ATI..."
        sudo apt install -y xserver-xorg-video-ati
        ;;
    4)
        echo "You selected 4. installing Nvidia (open source)..."
        sudo apt install -y xserver-xorg-video-nouveau
        ;;
    5)
        echo "You selected 5. installing Nvidia (open source)..."
        sudo apt install -y nvidia-driver
        ;;
    *)
        echo "Invalid choice. Please run the script again and select 1 or 5."
        ;;
esac

# Load uinput and add user to input group
echo -e "\e[31mWarning: this will set up read write execute (rwx-rwx-rwx-) permissions to /dev/uinput\e[0m"

#sudo usermod -aG input $USER_NAME
sudo modprobe uinput
sudo chmod 777 /dev/uinput

echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf


# -------------------------------
# Step 1: Python PS3 TTY mapper
# -------------------------------
sudo tee $PS3_PYTHON > /dev/null << 'EOF'
#!/usr/bin/env python3
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
sudo chmod 777 $PS3_PYTHON

# -------------------------------
# Step 2: Boot menu script - Enhanced TUI
# -------------------------------
sudo tee $BOOTMENU > /dev/null << EOF
#!/bin/bash

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Determine which dialog tool to use
if command -v dialog >/dev/null; then
    DIALOG_TOOL="dialog"
elif command -v whiptail >/dev/null; then
    DIALOG_TOOL="whiptail"
else
    echo -e "${RED}Error: No dialog tool found (dialog or whiptail required)${NC}"
    exit 1
fi

get_system_info() {
    local uptime_info=\$(uptime -p 2>/dev/null || echo "unknown")
    local hostname=\$(hostname 2>/dev/null || echo "unknown")
    
    # Get memory info
    local mem_total=\$(free -h | awk '/^Mem:/ {print \$2}')
    local mem_used=\$(free -h | awk '/^Mem:/ {print \$3}')
    local mem_free=\$(free -h | awk '/^Mem:/ {print \$4}')
    
    # Get disk info for root partition
    local disk_info=\$(df -h / | awk 'NR==2 {print \$3"/"\$2" ("\$5")"}')
    
    # Get CPU load
    local cpu_load=\$(uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ',')
    
    echo "Host: \$hostname | Up: \$uptime_info | Mem: \$mem_used/\$mem_total | Disk: \$disk_info | Load: \$cpu_load"
}

get_detailed_system_info() {
    clear
    echo -e "\${CYAN}+==================================================================+\${NC}"
    echo -e "\${CYAN}|\${NC}                  \${GREEN}System Information\${NC}                           \${CYAN}|\${NC}"
    echo -e "\${CYAN}+==================================================================+\${NC}"
    echo ""
    
    # Hostname and uptime
    echo -e "\${YELLOW}Hostname:\${NC} \$(hostname)"
    echo -e "\${YELLOW}Uptime:\${NC} \$(uptime -p 2>/dev/null || echo 'unknown')"
    echo ""
    
    # Memory information
    echo -e "\${GREEN}--- Memory Information ---\${NC}"
    free -h | awk 'NR==1 {printf "%-10s %10s %10s %10s %10s\\n", \$1, \$2, \$3, \$4, \$7} 
                   NR==2 {printf "%-10s %10s %10s %10s %10s\\n", \$1, \$2, \$3, \$4, \$7}'
    local mem_percent=\$(free | awk '/^Mem:/ {printf "%.1f", (\$3/\$2)*100}')
    echo -e "\${CYAN}Memory Usage:\${NC} \${mem_percent}%"
    echo ""
    
    # Disk information
    echo -e "\${GREEN}--- Disk Information ---\${NC}"
    df -h | awk 'NR==1 || /^\\\/dev\\// {printf "%-20s %8s %8s %8s %5s %s\\n", \$1, \$2, \$3, \$4, \$5, \$6}'
    echo ""
    
    # CPU information
    echo -e "\${GREEN}--- CPU Information ---\${NC}"
    if [ -f /proc/cpuinfo ]; then
        local cpu_model=\$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        local cpu_cores=\$(grep -c "^processor" /proc/cpuinfo)
        echo -e "\${CYAN}CPU Model:\${NC} \$cpu_model"
        echo -e "\${CYAN}CPU Cores:\${NC} \$cpu_cores"
    fi
    
    local load_avg=\$(uptime | awk -F'load average:' '{print \$2}' | xargs)
    echo -e "\${CYAN}Load Average:\${NC} \$load_avg"
    
    # CPU frequency if available
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        local cpu_freq=\$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        cpu_freq=\$((cpu_freq / 1000))
        echo -e "\${CYAN}CPU Frequency:\${NC} \${cpu_freq} MHz"
    fi
    echo ""
    
    # Temperature if available
    if command -v sensors >/dev/null 2>&1; then
        echo -e "\${GREEN}--- Temperature ---\${NC}"
        sensors 2>/dev/null | grep -E "Core|temp" | head -5
        echo ""
    fi
    
    echo -e "\${CYAN}+==================================================================+\${NC}"
    echo -e "\${YELLOW}Press Enter to return to menu...\${NC}"
    read
}

show_debug_menu() {
    clear
    echo -e "\${CYAN}+==================================================================+\${NC}"
    echo -e "\${CYAN}|\${NC}                    \${GREEN}Debug Menu\${NC}                                \${CYAN}|\${NC}"
    echo -e "\${CYAN}+==================================================================+\${NC}"
    echo ""
    
    PS3="Select debug option: "
    options=(
        "View System Logs (journalctl)"
        "View Dmesg Logs"
        "Check Running Processes"
        "Network Status"
        "Check X Server Status"
        "Test Controller Detection"
        "View Environment Variables"
        "Back to Main Menu"
    )
    
    select opt in "\${options[@]}"; do
        case \$opt in
            "View System Logs (journalctl)")
                clear
                echo -e "\${YELLOW}Last 50 system log entries:\${NC}"
                journalctl -n 50 --no-pager 2>/dev/null || echo "journalctl not available"
                echo ""
                echo -e "\${YELLOW}Press Enter to continue...\${NC}"
                read
                ;;
            "View Dmesg Logs")
                clear
                echo -e "\${YELLOW}Last 50 kernel messages:\${NC}"
                dmesg | tail -50
                echo ""
                echo -e "\${YELLOW}Press Enter to continue...\${NC}"
                read
                ;;
            "Check Running Processes")
                clear
                echo -e "\${YELLOW}Top processes by CPU:\${NC}"
                ps aux --sort=-%cpu | head -15
                echo ""
                echo -e "\${YELLOW}Press Enter to continue...\${NC}"
                read
                ;;
            "Network Status")
                clear
                echo -e "\${YELLOW}Network Interfaces:\${NC}"
                ip -brief addr 2>/dev/null || ifconfig -a
                echo ""
                echo -e "\${YELLOW}Active Connections:\${NC}"
                ss -tuln 2>/dev/null | head -10 || netstat -tuln | head -10
                echo ""
                echo -e "\${YELLOW}Press Enter to continue...\${NC}"
                read
                ;;
            "Check X Server Status")
                clear
                echo -e "\${YELLOW}X Server Status:\${NC}"
                if pgrep -x Xorg >/dev/null; then
                    echo -e "\${GREEN}X Server is running\${NC}"
                    ps aux | grep -E "[X]org|[x]init"
                else
                    echo -e "\${RED}X Server is not running\${NC}"
                fi
                echo ""
                echo -e "\${YELLOW}Display Variable:\${NC} \${DISPLAY:-not set}"
                echo ""
                echo -e "\${YELLOW}Press Enter to continue...\${NC}"
                read
                ;;
            "Test Controller Detection")
                clear
                echo -e "\${YELLOW}Detecting Controllers:\${NC}"
                echo ""
                if command -v python3 >/dev/null; then
                    python3 << 'PYEOF'
import evdev
import sys

try:
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    if devices:
        print("Found devices:")
        for device in devices:
            print(f"  - {device.path}: {device.name}")
            caps = device.capabilities()
            if evdev.ecodes.EV_KEY in caps:
                print(f"    (Has button input)")
    else:
        print("No input devices found")
except Exception as e:
    print(f"Error: {e}")
PYEOF
                else
                    echo "Python3 not available"
                fi
                echo ""
                echo -e "\${YELLOW}Input devices in /dev/input:\${NC}"
                ls -l /dev/input/event* 2>/dev/null || echo "No event devices found"
                echo ""
                echo -e "\${YELLOW}Press Enter to continue...\${NC}"
                read
                ;;
            "View Environment Variables")
                clear
                echo -e "\${YELLOW}Environment Variables:\${NC}"
                env | sort | head -30
                echo ""
                echo -e "\${YELLOW}Press Enter to continue...\${NC}"
                read
                ;;
            "Back to Main Menu")
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

show_info_box() {
    local title="\$1"
    local message="\$2"
    if [ "\$DIALOG_TOOL" = "dialog" ]; then
        dialog --colors --title "\$title" --infobox "\$message" 7 50
    else
        whiptail --title "\$title" --infobox "\$message" 7 50
    fi
    sleep 2
}

show_error_box() {
    local title="\$1"
    local message="\$2"
    if [ "\$DIALOG_TOOL" = "dialog" ]; then
        dialog --colors --title "\Z1ERROR\Zn" --msgbox "\$message" 10 60
    else
        whiptail --title "ERROR: \$title" --msgbox "\$message" 10 60
    fi
}

# Start Python PS3 mapper in background
$PS3_PYTHON &
PS3_PID=\$!

# Trap to ensure cleanup on exit
trap 'kill "\$PS3_PID" 2>/dev/null || true' EXIT

while true; do
    SYSINFO=\$(get_system_info)
    
    if [ "\$DIALOG_TOOL" = "dialog" ]; then
        CHOICE=\$(dialog --colors \
            --backtitle "Game Boot Utility v2.0 | \$SYSINFO" \
            --title "\Z2Main Menu\Zn" \
            --ok-label "Select" \
            --menu "\nUse arrow keys to navigate, Enter to select:\n" 22 75 11 \
            1 "RetroArch" "Launch RetroArch in fullscreen mode" \
            2 "IceWM" "Start IceWM desktop environment" \
            3 "XFCE4" "Start XFCE4 desktop environment" \
            4 "Update System" "Run apt update and upgrade" \
            5 "System Info" "View detailed system information" \
            6 "Debug Menu" "Debugging tools and logs" \
            7 "Shell" "Open command line shell" \
            8 "Network Config" "Configure network settings" \
            9 "Reboot" "Restart the system" \
            10 "Shutdown" "Power off the system" \
            3>&1 1>&2 2>&3)
    else
        CHOICE=\$(whiptail \
            --backtitle "Game Boot Utility v2.0 | \$SYSINFO" \
            --title "Main Menu" \
            --ok-button "Select" \
            --menu "Use arrow keys to navigate, Enter to select:" 22 75 11 \
            1 "RetroArch" "Launch RetroArch in fullscreen" \
            2 "IceWM" "Start IceWM desktop" \
            3 "XFCE4" "Start XFCE4 desktop" \
            4 "Update System" "Run apt update and upgrade" \
            5 "System Info" "View detailed system information" \
            6 "Debug Menu" "Debugging tools and logs" \
            7 "Shell" "Open command line" \
            8 "Network Config" "Configure network" \
            9 "Reboot" "Restart system" \
            10 "Shutdown" "Power off" \
            3>&1 1>&2 2>&3)
    fi

    # Handle dialog cancellation
    exit_code=\$?
    if [ \$exit_code -ne 0 ]; then
        continue
    fi

    clear

    case \$CHOICE in
    1)
        show_info_box "Launching" "Starting RetroArch..."
        kill \$PS3_PID 2>/dev/null || true
        if ! retroarch -f; then
            show_error_box "RetroArch Error" "Failed to launch RetroArch.\nPress any key to return to menu."
        fi
        $PS3_PYTHON &
        PS3_PID=\$!
        ;;
    2)
        show_info_box "Launching" "Starting IceWM desktop..."
        kill \$PS3_PID 2>/dev/null || true
        echo "exec icewm-session" > ~/.xinitrc
        # Start AntimicroX in IceWM
        antimicrox --hidden --profile $ANTIMICROX_PROFILE 2>/dev/null &
        onboard 2>/dev/null &
        if ! startx 2>/dev/null; then
            show_error_box "IceWM Error" "Failed to start IceWM.\nPress any key to return to menu."
        fi
        $PS3_PYTHON &
        PS3_PID=\$!
        ;;
    3)
        show_info_box "Launching" "Starting XFCE4 desktop..."
        kill \$PS3_PID 2>/dev/null || true
        echo "exec startxfce4" > ~/.xinitrc
        # Start AntimicroX in XFCE
        antimicrox --hidden --profile $ANTIMICROX_PROFILE 2>/dev/null &
        onboard 2>/dev/null &
        if ! startx 2>/dev/null; then
            show_error_box "XFCE4 Error" "Failed to start XFCE4.\nPress any key to return to menu."
        fi
        $PS3_PYTHON &
        PS3_PID=\$!
        ;;
    4)
        # System update with animated progress bar
        clear
        echo -e "\${GREEN}+========================================+\${NC}"
        echo -e "\${GREEN}|\${NC}    ${YELLOW}Updating System...${NC}             \${GREEN}|\${NC}"
        echo -e "\${GREEN}+========================================+\${NC}"
        echo ""
        echo -e "\${CYAN}Full log at /tmp/apt_update.log\${NC}\n"
        sudo apt update -y && sudo apt upgrade -y &> /tmp/apt_update.log &
        PID=\$!
        BAR="#"
        WIDTH=40
        while kill -0 \$PID 2>/dev/null; do
            if [ \${#BAR} -lt \$WIDTH ]; then
                BAR="\$BAR="
            else
                BAR=""
            fi
            printf "\r[\${YELLOW}%s\${NC}] Updating..." "\$BAR"
            sleep 0.2
        done
        wait \$PID
        printf "\r[\${GREEN}%s\${NC}] Update complete!          \n" "\$(printf '=%.0s' \$(seq 1 \$WIDTH))"
        sleep 2
        ;;
    5)
        get_detailed_system_info
        ;;
    6)
        show_debug_menu
        ;;
    7)
        clear
        echo -e "\${CYAN}+========================================+\${NC}"
        echo -e "\${CYAN}|\${NC}    \${GREEN}Entering Shell Environment\${NC}      \${CYAN}|\${NC}"
        echo -e "\${CYAN}+========================================+\${NC}"
        echo -e "\${YELLOW}Type 'exit' to return to the menu\${NC}\n"
        bash
        ;;
    8)
        clear
        echo -e "\${CYAN}+========================================+\${NC}"
        echo -e "\${CYAN}|\${NC}    \${GREEN}Network Configuration\${NC}            \${CYAN}|\${NC}"
        echo -e "\${CYAN}+========================================+\${NC}"
        echo -e "\${YELLOW}Note: Limited keyboard mapping active\${NC}"
        echo -e "\${YELLOW}You may need a physical keyboard\${NC}\n"
        sleep 2
        sudo nmtui
        echo -e "\n\${GREEN}Network configuration complete!\${NC}"
        sleep 2
        ;;
    9)
        if [ "\$DIALOG_TOOL" = "dialog" ]; then
            dialog --colors --title "\Z1WARNING: Confirm Reboot\Zn" \
                --yesno "Are you sure you want to reboot?" 7 50
        else
            whiptail --title "WARNING: Confirm Reboot" \
                --yesno "Are you sure you want to reboot?" 7 50
        fi
        if [ \$? -eq 0 ]; then
            clear
            echo -e "\${YELLOW}Rebooting system...\${NC}"
            kill \$PS3_PID 2>/dev/null || true
            sudo reboot
        fi
        ;;
    10)
        if [ "\$DIALOG_TOOL" = "dialog" ]; then
            dialog --colors --title "\Z1WARNING: Confirm Shutdown\Zn" \
                --yesno "Are you sure you want to shut down?" 7 50
        else
            whiptail --title "WARNING: Confirm Shutdown" \
                --yesno "Are you sure you want to shut down?" 7 50
        fi
        if [ \$? -eq 0 ]; then
            clear
            echo -e "\${YELLOW}Shutting down system...\${NC}"
            kill \$PS3_PID 2>/dev/null || true
            sudo shutdown now
        fi
        ;;
    esac
done

EOF
sudo chmod +x $BOOTMENU

# -------------------------------
# Step 3: Auto-login on tty1
# -------------------------------
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
sudo systemctl daemon-reexec

# Launch boot menu automatically on tty1
grep -qxF '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' ~/.bash_profile || \
echo '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' >> ~/.bash_profile

# -------------------------------
# Step 4: IceWM menu
# -------------------------------
mkdir -p "$(dirname "$ICEWM_MENU")"
cat > "$ICEWM_MENU" << EOF

menuprog "apps" folder icewm-menu-fdo
prog Terminal x-terminal-emulator x-terminal-emulator
prog FileManager thunar thunar

sep

prog Restart IceWM restart icewm --restart
prog Logout logout logout
EOF

# -------------------------------
# Step 5: AntimicroX autostart for XFCE4
# -------------------------------
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/antimicrox.desktop" << EOF
[Desktop Entry]
Type=Application
Exec=antimicrox --hidden --profile /home/zdislav/.config/antimicrox/bootmenu_gamepad_profile.amgp
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=AntimicroX
Comment=Start AntimicroX with profile

EOF

# -------------------------------
# Step 6: AntimicroX + Onboard autostart for IceWM
# -------------------------------
mkdir -p ~/.icewm
cat > ~/.icewm/startup << EOF
#!/bin/bash
# Start AntimicroX with profile
antimicrox --hidden --profile $ANTIMICROX_PROFILE &

# Start Onboard on-screen keyboard
onboard &
EOF
chmod +x ~/.icewm/startup


# -------------------------------
# Step6.1: Onboard autostart for xfce4
# -------------------------------
# Onboard autostart
cat > "$AUTOSTART_DIR/onboard.desktop" << EOF
[Desktop Entry]
Type=Application
Exec=onboard
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Onboard
Comment=Start Onboard on-screen keyboard
EOF


# -------------------------------
# Step 7: Latest Download RetroArch cores (all .zip files)
# Because debian has older files
# ------------------------------- 

echo "downloading retroarch lates cores"
mkdir -p ~/.config/retroarch/cores
cd ~/.config/retroarch/cores
sudo wget -r -np -nH --cut-dirs=4 -A "*.zip" https://buildbot.libretro.com/nightly/linux/x86_64/latest/
sudo find . -name "*.zip" -exec unzip -o {} \;
sudo find . -name "*.zip" -delete

echo -e "\e[42mAll RetroArch cores downloaded and extracted.\e[0m"

cd ~
cp -r "$conf"/* ".config/"


echo -e "\e[42m=== Setup complete! Reboot to test ===\e[0m"
echo -e "\e[41mTo check errors, read ./log.txt\e[0m"
