#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# CONFIGURATION & PATHS
# -------------------------------
USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_UI_PY="/usr/local/bin/ps3_ui.py"
PS3_MAPPER="/usr/local/bin/ps3_to_keys.py"
LOG_FILE="$HOME/install_log.txt"

# Colors for terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "   PS3 XMB-Style OS INSTALLER (v0.2.0)"
echo -e "================================================${NC}"
echo "Targets: Arch, Debian, Ubuntu, Fedora"
read -r -p "This script modifies system files. Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# 1. DETECT PACKAGE MANAGER & INSTALL
# -------------------------------
if command -v pacman >/dev/null; then
    PM="pacman"
    INSTALL="sudo pacman -Sy --needed --noconfirm"
    PKGS="python-evdev python-uinput retroarch xorg-xinit xorg-server xterm"
elif command -v apt-get >/dev/null; then
    PM="apt"
    INSTALL="sudo apt-get update && sudo apt-get install -y"
    PKGS="python3-evdev python3-uinput retroarch xinit x11-xserver-utils python3-curses"
elif command -v dnf >/dev/null; then
    PM="dnf"
    INSTALL="sudo dnf install -y"
    PKGS="python3-evdev python3-uinput retroarch xorg-x11-xinit-session python3-curses"
else
    echo -e "${RED}Error: Unsupported distribution.${NC}"
    exit 1
fi

echo -e "${YELLOW}Installing system dependencies...${NC}"
$INSTALL $PKGS

# -------------------------------
# 2. DISABLE LOGIN MANAGER (OPTIONAL)
# -------------------------------
echo -e "\n${CYAN}--- LOGIN MANAGER SETUP ---${NC}"
# Find any active Display Manager
ACTIVE_DM=$(systemctl list-units --type=service --state=running | grep -E 'gdm|sddm|lightdm|lxdm' | awk '{print $1}' | head -n 1 || echo "")

if [ -n "$ACTIVE_DM" ]; then
    echo -e "${YELLOW}Detected active login manager: $ACTIVE_DM${NC}"
    echo "To boot directly into the PS3 Menu, you should disable the graphical login screen."
    read -r -p "Disable $ACTIVE_DM and boot to Console/XMB mode? [y/N]: " DIS_DM
    if [[ "${DIS_DM,,}" == "y" ]]; then
        sudo systemctl set-default multi-user.target
        sudo systemctl disable "$ACTIVE_DM"
        echo -e "${GREEN}Login manager disabled. System will now boot to TTY text mode.${NC}"
    fi
else
    echo "No graphical login manager detected. Ensuring system boots to console..."
    sudo systemctl set-default multi-user.target
fi

# -------------------------------
# 3. CONTROLLER MAPPER (Python)
# -------------------------------
echo -e "${YELLOW}Creating Controller Mapper...${NC}"
sudo tee "$PS3_MAPPER" >/dev/null << 'EOF'
#!/usr/bin/env python3
import evdev, uinput, sys

def get_device():
    try:
        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
        for d in devices:
            if evdev.ecodes.EV_KEY in d.capabilities(): return d
    except: return None
    return None

device = get_device()
if not device: sys.exit(0)

events = [uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT]

try:
    ui = uinput.Device(events)
    # 304=A/Cross (Enter), 305=B/Circle (ESC)
    BTN_MAP = {304: uinput.KEY_ENTER, 305: uinput.KEY_ESC}
    device.grab()
    for e in device.read_loop():
        if e.type == evdev.ecodes.EV_KEY and e.code in BTN_MAP:
            ui.emit(BTN_MAP[e.code], e.value)
        elif e.type == evdev.ecodes.EV_ABS:
            if e.code == evdev.ecodes.ABS_HAT0Y:
                key = uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN
                if e.value != 0: ui.emit(key, 1); ui.emit(key, 0)
            elif e.code == evdev.ecodes.ABS_HAT0X:
                key = uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT
                if e.value != 0: ui.emit(key, 1); ui.emit(key, 0)
except: sys.exit(0)
EOF
sudo chmod +x "$PS3_MAPPER"

# -------------------------------
# 4. PS3 XMB UI (Python Curses)
# -------------------------------
echo -e "${YELLOW}Creating PS3 XMB UI...${NC}"
sudo tee "$PS3_UI_PY" >/dev/null << 'EOF'
#!/usr/bin/env python3
import curses, os, subprocess, datetime

MENU_DATA = {
    "  🎮 GAMES  ": [
        ("RetroArch", "retroarch"),
        ("Terminal", "xterm"),
    ],
    "  ⚙️ SYSTEM  ": [
        ("Desktop Mode", "startx"),
        ("Check Updates", "sudo apt update || sudo pacman -Sy"),
    ],
    "  🔌 POWER   ": [
        ("Reboot", "sudo reboot"),
        ("Shutdown", "sudo shutdown now"),
        ("Exit to Shell", "exit"),
    ]
}

def draw_menu(stdscr):
    curses.curs_set(0)
    curses.start_color()
    curses.init_pair(1, curses.COLOR_CYAN, curses.COLOR_BLACK)  # Selection
    curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK) # Text
    curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_WHITE) # Header

    categories = list(MENU_DATA.keys())
    cat_idx, item_idx = 0, 0

    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()
        time_str = datetime.datetime.now().strftime("%H:%M")

        # Header
        stdscr.attron(curses.color_pair(3))
        stdscr.addstr(0, 0, " " * w)
        stdscr.addstr(0, 2, " P L A Y S T A T I O N ® 3 ")
        stdscr.addstr(0, w - len(time_str) - 2, time_str)
        stdscr.attroff(curses.color_pair(3))

        # Categories
        for i, cat in enumerate(categories):
            pos_x = (w // len(categories)) * i + 4
            style = curses.color_pair(1) | curses.A_BOLD if i == cat_idx else curses.color_pair(2)
            stdscr.addstr(3, pos_x, cat, style)

        # Items
        items = MENU_DATA[categories[cat_idx]]
        start_x = (w // len(categories)) * cat_idx + 6
        for i, (name, cmd) in enumerate(items):
            if i == item_idx:
                stdscr.addstr(6 + i*2, start_x, f"▶ {name}", curses.color_pair(1) | curses.A_BOLD)
            else:
                stdscr.addstr(6 + i*2, start_x, f"  {name}", curses.color_pair(2))

        stdscr.refresh()
        key = stdscr.getch()
        if key == curses.KEY_RIGHT: cat_idx = (cat_idx + 1) % len(categories); item_idx = 0
        elif key == curses.KEY_LEFT: cat_idx = (cat_idx - 1) % len(categories); item_idx = 0
        elif key == curses.KEY_UP: item_idx = (item_idx - 1) % len(items)
        elif key == curses.KEY_DOWN: item_idx = (item_idx + 1) % len(items)
        elif key in [10, 13, curses.KEY_ENTER]: return items[item_idx][1]

if __name__ == "__main__":
    action = curses.wrapper(draw_menu)
    if action == "exit": exit(0)
    if action:
        os.system('clear')
        subprocess.run(action, shell=True)
EOF
sudo chmod +x "$PS3_UI_PY"

# -------------------------------
# 5. BOOT MENU WRAPPER
# -------------------------------
echo -e "${YELLOW}Creating Boot Menu Wrapper...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash
$PS3_MAPPER &
MAPPER_PID=$!
trap 'kill $MAPPER_PID 2>/dev/null' EXIT

while true; do
    python3 /usr/local/bin/ps3_ui.py
    sleep 0.2
done
EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# 6. PERMISSIONS & AUTOLOGIN
# -------------------------------
echo -e "${YELLOW}Finalizing system settings...${NC}"
sudo usermod -aG input,video "$USER_NAME"
sudo modprobe uinput || true
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null || true
sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

# TTY1 Autologin
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
sudo systemctl daemon-reload

# Shell Trigger
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"
TRIGGER='[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh'
grep -q "bootmenu.sh" "$TARGET_PROFILE" || echo "$TRIGGER" >> "$TARGET_PROFILE"

echo -e "\n${GREEN}INSTALLATION COMPLETE!${NC}"
echo "1. Login Manager configured based on your choice."
echo "2. Controller support (D-Pad/Cross/Circle) is enabled."
echo "3. Please reboot now to start your PS3-style console UI."
