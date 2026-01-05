#!/usr/bin/env bash
set -euo pipefail

exec > >(tee -a "$HOME/log.txt") 2>&1

USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"

# -------------------------------
# WARNING
# -------------------------------
echo "WARNING: Experimental script"
read -r -p "Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# Detect package manager
# -------------------------------
detect_pm() {
    for pm in pacman apt dnf zypper xbps-install apk; do
        command -v "$pm" >/dev/null && echo "$pm" && return
    done
    echo "unsupported"
}

PM="$(detect_pm)"

install_packages() {
    case "$PM" in
        pacman)
            sudo pacman -Sy --needed --noconfirm \
                retroarch retroarch-assets \
                xorg-server xorg-xinit xorg-xinput \
                dialog antimicrox onboard \
                python-evdev python-uinput \
                wget curl unzip sudo neovim tmux
            ;;
        apt)
            sudo apt update
            sudo apt install -y \
                retroarch retroarch-assets \
                xinit xserver-xorg-core xserver-xorg-input-all \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux
            ;;
        dnf)
            sudo dnf install -y \
                retroarch retroarch-assets \
                xorg-x11-server-Xorg xorg-x11-xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux
            ;;
        zypper)
            sudo zypper install -y \
                retroarch retroarch-assets \
                xorg-x11-server xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux
            ;;
        xbps-install)
            sudo xbps-install -Sy \
                retroarch retroarch-assets \
                xorg-minimal xinit \
                dialog antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux
            ;;
        apk)
            sudo apk add \
                retroarch \
                xorg-server xinit \
                dialog antimicrox onboard \
                py3-evdev py3-uinput \
                wget curl unzip sudo neovim tmux
            ;;
        *)
            echo "No supported package manager found"
            exit 1
            ;;
    esac
}

# -------------------------------
# Packages
# -------------------------------
install_packages

# -------------------------------
# uinput
# -------------------------------
sudo modprobe uinput || true
sudo chmod 666 /dev/uinput || true

if command -v systemctl >/dev/null; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
fi

# -------------------------------
# Controller mapper
# -------------------------------
sudo tee "$PS3_PYTHON" >/dev/null << 'EOF'
#!/usr/bin/env python3
import evdev, uinput, sys

devices = [evdev.InputDevice(p) for p in evdev.list_devices()]
device = next((d for d in devices if evdev.ecodes.EV_KEY in d.capabilities()), None)

if not device:
    print("No controller found")
    sys.exit(1)

events = [
    uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
    uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT
]

ui = uinput.Device(events)

BTN_MAP = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
    307: uinput.KEY_BACKSPACE,
    308: uinput.KEY_SPACE,
}

device.grab()

for e in device.read_loop():
    if e.type == evdev.ecodes.EV_KEY and e.code in BTN_MAP:
        ui.emit(BTN_MAP[e.code], e.value)
    elif e.type == evdev.ecodes.EV_ABS:
        if e.code == evdev.ecodes.ABS_HAT0Y:
            key = uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN
            ui.emit(key, 1); ui.emit(key, 0)
        elif e.code == evdev.ecodes.ABS_HAT0X:
            key = uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT
            ui.emit(key, 1); ui.emit(key, 0)
EOF

sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# Boot menu - Enhanced TUI
# -------------------------------
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash

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
    DIALOG_CMD="dialog --colors --backtitle \"Game Boot Utility v2.0\" --no-cancel"
elif command -v whiptail >/dev/null; then
    DIALOG_TOOL="whiptail"
    DIALOG_CMD="whiptail --backtitle \"Game Boot Utility v2.0\" --nocancel"
else
    echo -e "${RED}Error: No dialog tool found (dialog or whiptail required)${NC}"
    exit 1
fi

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [[ -n "$name" && -n "$exec" ]] && echo "$name|$exec"
    done
}

detect_steam() {
    command -v steam >/dev/null && echo steam && return
    command -v flatpak >/dev/null && flatpak list | grep -qi steam \
        && echo "flatpak run com.valvesoftware.Steam"
}

get_system_info() {
    local uptime_info=$(uptime -p 2>/dev/null || echo "unknown")
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    
    # Get memory info
    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    local mem_free=$(free -h | awk '/^Mem:/ {print $4}')
    
    # Get disk info for root partition
    local disk_info=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')
    
    # Get CPU load
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    echo "Host: $hostname | Up: $uptime_info | Mem: $mem_used/$mem_total | Disk: $disk_info | Load: $cpu_load"
}

get_detailed_system_info() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                  ${GREEN}System Information${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hostname and uptime
    echo -e "${YELLOW}Hostname:${NC} $(hostname)"
    echo -e "${YELLOW}Uptime:${NC} $(uptime -p 2>/dev/null || echo 'unknown')"
    echo ""
    
    # Memory information
    echo -e "${GREEN}━━━ Memory Information ━━━${NC}"
    free -h | awk 'NR==1 {printf "%-10s %10s %10s %10s %10s\n", $1, $2, $3, $4, $7} 
                   NR==2 {printf "%-10s %10s %10s %10s %10s\n", $1, $2, $3, $4, $7}'
    local mem_percent=$(free | awk '/^Mem:/ {printf "%.1f", ($3/$2)*100}')
    echo -e "${CYAN}Memory Usage:${NC} ${mem_percent}%"
    echo ""
    
    # Disk information
    echo -e "${GREEN}━━━ Disk Information ━━━${NC}"
    df -h | awk 'NR==1 || /^\/dev\// {printf "%-20s %8s %8s %8s %5s %s\n", $1, $2, $3, $4, $5, $6}'
    echo ""
    
    # CPU information
    echo -e "${GREEN}━━━ CPU Information ━━━${NC}"
    if [ -f /proc/cpuinfo ]; then
        local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        local cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
        echo -e "${CYAN}CPU Model:${NC} $cpu_model"
        echo -e "${CYAN}CPU Cores:${NC} $cpu_cores"
    fi
    
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo -e "${CYAN}Load Average:${NC} $load_avg"
    
    # CPU frequency if available
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        local cpu_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        cpu_freq=$((cpu_freq / 1000))
        echo -e "${CYAN}CPU Frequency:${NC} ${cpu_freq} MHz"
    fi
    echo ""
    
    # Temperature if available
    if command -v sensors >/dev/null 2>&1; then
        echo -e "${GREEN}━━━ Temperature ━━━${NC}"
        sensors 2>/dev/null | grep -E "Core|temp" | head -5
        echo ""
    fi
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Press Enter to return to menu...${NC}"
    read
}

show_debug_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${GREEN}Debug Menu${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
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
    
    select opt in "${options[@]}"; do
        case $opt in
            "View System Logs (journalctl)")
                clear
                echo -e "${YELLOW}Last 50 system log entries:${NC}"
                journalctl -n 50 --no-pager 2>/dev/null || echo "journalctl not available"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read
                ;;
            "View Dmesg Logs")
                clear
                echo -e "${YELLOW}Last 50 kernel messages:${NC}"
                dmesg | tail -50
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read
                ;;
            "Check Running Processes")
                clear
                echo -e "${YELLOW}Top processes by CPU:${NC}"
                ps aux --sort=-%cpu | head -15
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read
                ;;
            "Network Status")
                clear
                echo -e "${YELLOW}Network Interfaces:${NC}"
                ip -brief addr 2>/dev/null || ifconfig -a
                echo ""
                echo -e "${YELLOW}Active Connections:${NC}"
                ss -tuln 2>/dev/null | head -10 || netstat -tuln | head -10
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read
                ;;
            "Check X Server Status")
                clear
                echo -e "${YELLOW}X Server Status:${NC}"
                if pgrep -x Xorg >/dev/null; then
                    echo -e "${GREEN}X Server is running${NC}"
                    ps aux | grep -E "[X]org|[x]init"
                else
                    echo -e "${RED}X Server is not running${NC}"
                fi
                echo ""
                echo -e "${YELLOW}Display Variable:${NC} ${DISPLAY:-not set}"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read
                ;;
            "Test Controller Detection")
                clear
                echo -e "${YELLOW}Detecting Controllers:${NC}"
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
                echo -e "${YELLOW}Input devices in /dev/input:${NC}"
                ls -l /dev/input/event* 2>/dev/null || echo "No event devices found"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read
                ;;
            "View Environment Variables")
                clear
                echo -e "${YELLOW}Environment Variables:${NC}"
                env | sort | head -30
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
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
    local title="$1"
    local message="$2"
    if [ "$DIALOG_TOOL" = "dialog" ]; then
        dialog --colors --title "$title" --infobox "$message" 7 50
    else
        whiptail --title "$title" --infobox "$message" 7 50
    fi
    sleep 2
}

show_error_box() {
    local title="$1"
    local message="$2"
    if [ "$DIALOG_TOOL" = "dialog" ]; then
        dialog --colors --title "\Z1ERROR\Zn" --msgbox "$message" 10 60
    else
        whiptail --title "ERROR: $title" --msgbox "$message" 10 60
    fi
}

# Start controller mapper in background
"$PS3_PYTHON" &
PS3_PID=$!

# Trap to ensure cleanup on exit
trap 'kill "$PS3_PID" 2>/dev/null || true' EXIT

while true; do
    ITEMS=()
    ACTIONS=()
    DESCRIPTIONS=()
    i=1

    # Detect RetroArch
    if command -v retroarch >/dev/null; then
        ITEMS+=($i "🎮 RetroArch" "Launch RetroArch in fullscreen mode")
        ACTIONS+=("retroarch")
        ((i++))
    fi

    # Detect Steam
    STEAM=$(detect_steam || true)
    if [ -n "$STEAM" ]; then
        ITEMS+=($i "🎯 Steam" "Launch Steam in Big Picture mode")
        ACTIONS+=("steam:$STEAM")
        ((i++))
    fi

    # Detect Desktop Sessions
    local session_count=0
    while IFS='|' read -r name exec; do
        ITEMS+=($i "🖥️  $name" "Start $name desktop environment")
        ACTIONS+=("session:$exec")
        ((i++))
        ((session_count++))
    done < <(detect_sessions)

    # System options
    ITEMS+=(
        $i "📊 System Info" "View detailed system information"
        $((i+1)) "🔧 Debug Menu" "Debugging tools and logs"
        $((i+2)) "💻 Shell" "Open command line shell"
        $((i+3)) "🔄 Reboot" "Restart the system"
        $((i+4)) "⏻  Shutdown" "Power off the system"
    )
    ACTIONS+=("sysinfo" "debug" "shell" "reboot" "shutdown")

    # Display menu with system info
    SYSINFO=$(get_system_info)
    if [ "$DIALOG_TOOL" = "dialog" ]; then
        CHOICE=$(dialog --colors \
            --backtitle "Game Boot Utility v2.0 | $SYSINFO" \
            --title "\Z2◆ Main Menu ◆\Zn" \
            --ok-label "Select" \
            --menu "\nUse arrow keys to navigate, Enter to select:\n" \
            22 75 14 \
            "${ITEMS[@]}" \
            3>&1 1>&2 2>&3)
    else
        CHOICE=$(whiptail \
            --backtitle "Game Boot Utility v2.0 | $SYSINFO" \
            --title "Main Menu" \
            --ok-button "Select" \
            --menu "Use arrow keys to navigate, Enter to select:" \
            22 75 14 \
            "${ITEMS[@]}" \
            3>&1 1>&2 2>&3)
    fi

    # Handle dialog cancellation
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        continue
    fi

    clear

    # Execute selected action
    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        retroarch)
            show_info_box "Launching" "Starting RetroArch..."
            kill "$PS3_PID" 2>/dev/null || true
            if ! retroarch -f; then
                show_error_box "RetroArch Error" "Failed to launch RetroArch.\nPress any key to return to menu."
            fi
            "$PS3_PYTHON" &
            PS3_PID=$!
            ;;
        steam:*)
            show_info_box "Launching" "Starting Steam..."
            kill "$PS3_PID" 2>/dev/null || true
            pkill -f ps3_to_keys.py 2>/dev/null || true
            if ! xinit ${ACTION#steam:} -bigpicture -- :0 2>/dev/null; then
                show_error_box "Steam Error" "Failed to launch Steam.\nPress any key to return to menu."
            fi
            "$PS3_PYTHON" &
            PS3_PID=$!
            ;;
        session:*)
            show_info_box "Launching" "Starting desktop session..."
            kill "$PS3_PID" 2>/dev/null || true
            echo "exec ${ACTION#session:}" > "$HOME/.xinitrc"
            antimicrox --hidden 2>/dev/null &
            onboard 2>/dev/null &
            if ! startx 2>/dev/null; then
                show_error_box "Session Error" "Failed to start desktop session.\nPress any key to return to menu."
            fi
            "$PS3_PYTHON" &
            PS3_PID=$!
            ;;
        shell)
            clear
            echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║${NC}    ${GREEN}Entering Shell Environment${NC}      ${CYAN}║${NC}"
            echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
            echo -e "${YELLOW}Type 'exit' to return to the menu${NC}\n"
            bash
            ;;
        sysinfo)
            get_detailed_system_info
            ;;
        debug)
            show_debug_menu
            ;;
        reboot)
            if [ "$DIALOG_TOOL" = "dialog" ]; then
                dialog --colors --title "\Z1⚠ Confirm Reboot\Zn" \
                    --yesno "Are you sure you want to reboot?" 7 50
            else
                whiptail --title "⚠ Confirm Reboot" \
                    --yesno "Are you sure you want to reboot?" 7 50
            fi
            if [ $? -eq 0 ]; then
                clear
                echo -e "${YELLOW}Rebooting system...${NC}"
                kill "$PS3_PID" 2>/dev/null || true
                sudo reboot
            fi
            ;;
        shutdown)
            if [ "$DIALOG_TOOL" = "dialog" ]; then
                dialog --colors --title "\Z1⚠ Confirm Shutdown\Zn" \
                    --yesno "Are you sure you want to shut down?" 7 50
            else
                whiptail --title "⚠ Confirm Shutdown" \
                    --yesno "Are you sure you want to shut down?" 7 50
            fi
            if [ $? -eq 0 ]; then
                clear
                echo -e "${YELLOW}Shutting down system...${NC}"
                kill "$PS3_PID" 2>/dev/null || true
                sudo shutdown now
            fi
            ;;
    esac
done
EOF

sudo chmod +x "$BOOTMENU"

# -------------------------------
# Autologin (systemd only)
# -------------------------------
if command -v systemctl >/dev/null; then
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reexec
fi

grep -qxF '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' "$HOME/.bash_profile" \
    || echo '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' >> "$HOME/.bash_profile"

echo "DONE. Reboot."
