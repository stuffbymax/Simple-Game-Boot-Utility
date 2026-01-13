#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# CONFIGURATION
# -------------------------------
USER_NAME="$(whoami)"
INSTALL_DIR="/usr/local/bin/xmb_boot"
MENU_SCRIPT="$INSTALL_DIR/menu.py"
PS3_MAPPER="$INSTALL_DIR/ps3_mapper.py"
LOG_FILE="$HOME/install_log.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "   PS3 XMB STYLE BOOT INSTALLER"
echo -e "================================================${NC}"
echo "This will install Python/Pygame and configure a graphical menu."
read -r -p "Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# 1. INSTALL PACKAGES
# -------------------------------
if command -v apt-get >/dev/null; then
    INSTALL="sudo apt-get install -y"
    sudo apt-get update
elif command -v pacman >/dev/null; then
    INSTALL="sudo pacman -S --noconfirm"
    sudo pacman -Sy
else
    echo -e "${RED}Unsupported package manager. Install dependencies manually.${NC}"
    exit 1
fi
PKGS_LIST=(
    python3
    python3-pip
    python3-evdev
    python3-uinput
    python3-pygame
    xinit
    x11-xserver-utils
    xterm
    sudo
    evtest
    retroarch
)

echo -e "${YELLOW}Installing packages...${NC}"
$INSTALL $PKGS_LIST

# -------------------------------
# 2. SETUP DIRECTORIES & PERMISSIONS
# -------------------------------
echo -e "${YELLOW}Setting up directories...${NC}"
sudo mkdir -p "$INSTALL_DIR/assets"
sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"

# Uinput permissions
sudo modprobe uinput || true
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF
sudo usermod -aG input "$USER_NAME"
sudo usermod -aG video "$USER_NAME"

# -------------------------------
# 3. CONTROLLER MAPPER (Python)
# -------------------------------
# We map controller inputs to Keyboard arrow keys so Pygame can read them easily
cat << 'EOF' > "$PS3_MAPPER"
#!/usr/bin/env python3
import evdev, uinput, sys
from evdev import ecodes

def get_gamepad():
    for path in evdev.list_devices():
        d = evdev.InputDevice(path)
        if ecodes.EV_KEY in d.capabilities() and ecodes.BTN_SOUTH in d.capabilities().get(ecodes.EV_KEY, []):
            return d
    return None

try:
    device = get_gamepad()
    if not device: sys.exit(0)
    
    ui = uinput.Device([uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT, uinput.KEY_ENTER, uinput.KEY_ESC])
    
    # Simple mapping: D-Pad / Analog -> Arrow Keys, Cross -> Enter, Circle -> Esc
    device.grab()
    for e in device.read_loop():
        if e.type == ecodes.EV_KEY:
            if e.code == 304: ui.emit(uinput.KEY_ENTER, e.value) # Cross/A
            elif e.code == 305: ui.emit(uinput.KEY_ESC, e.value)   # Circle/B
        elif e.type == ecodes.EV_ABS:
            if e.code == ecodes.ABS_HAT0Y:
                k = uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN
                if e.value != 0: ui.emit(k, 1); ui.emit(k, 0)
            elif e.code == ecodes.ABS_HAT0X:
                k = uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT
                if e.value != 0: ui.emit(k, 1); ui.emit(k, 0)
except:
    sys.exit(0)
EOF
chmod +x "$PS3_MAPPER"

# -------------------------------
# 4. PYTHON XMB MENU (Pygame)
# -------------------------------
cat << 'EOF' > "$MENU_SCRIPT"
#!/usr/bin/env python3
import pygame
import os
import sys
import subprocess
import json
import time

# --- CONFIGURATION ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS_DIR = os.path.join(BASE_DIR, "assets")
CONFIG_FILE = os.path.join(BASE_DIR, "config.json")

DEFAULT_CONFIG = {
    "bg_color": [20, 20, 20],
    "highlight_color": [255, 255, 255],
    "text_color": [150, 150, 150],
    "font_size": 30,
    "category_y": 100,
    "item_start_y": 200,
    "animation_speed": 10
}

if not os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(DEFAULT_CONFIG, f, indent=4)

with open(CONFIG_FILE, 'r') as f:
    CFG = json.load(f)

# --- DATA STRUCTURE ---
# Define your menu structure here
MENU = [
    {
        "category": "System",
        "icon": "icon_settings.png",
        "items": [
            {"label": "Reboot", "cmd": "sudo reboot"},
            {"label": "Shutdown", "cmd": "sudo shutdown now"},
            {"label": "Exit to Shell", "cmd": "EXIT"}
        ]
    },
    {
        "category": "Games",
        "icon": "icon_games.png",
        "items": [
            {"label": "RetroArch", "cmd": "retroarch -f"},
            {"label": "Terminal", "cmd": "xterm"} 
        ]
    }
]

# --- ENGINE ---
pygame.init()
info = pygame.display.Info()
WIDTH, HEIGHT = info.current_w, info.current_h
screen = pygame.display.set_mode((WIDTH, HEIGHT), pygame.NOFRAME)
pygame.mouse.set_visible(False)
clock = pygame.time.Clock()

# Fonts
font = pygame.font.SysFont("dejavusans", CFG["font_size"])
big_font = pygame.font.SysFont("dejavusans", int(CFG["font_size"] * 1.5))

# Load Background
bg_img = None
bg_path = os.path.join(ASSETS_DIR, "background.png")
if os.path.exists(bg_path):
    bg_img = pygame.image.load(bg_path)
    bg_img = pygame.transform.scale(bg_img, (WIDTH, HEIGHT))

# State
col_idx = 1 # Start at Games
row_idx = 0
target_x = 0
current_x = 0

def draw_text(surface, text, x, y, color, center=False, is_bold=False):
    f = big_font if is_bold else font
    render = f.render(text, True, color)
    rect = render.get_rect()
    if center:
        rect.center = (x, y)
    else:
        rect.topleft = (x, y)
    surface.blit(render, rect)

running = True
while running:
    screen.fill(CFG["bg_color"])
    if bg_img: screen.blit(bg_img, (0, 0))

    # Event Handling
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_LEFT:
                col_idx = (col_idx - 1) % len(MENU)
                row_idx = 0
            elif event.key == pygame.K_RIGHT:
                col_idx = (col_idx + 1) % len(MENU)
                row_idx = 0
            elif event.key == pygame.K_UP:
                row_idx = (row_idx - 1) % len(MENU[col_idx]["items"])
            elif event.key == pygame.K_DOWN:
                row_idx = (row_idx + 1) % len(MENU[col_idx]["items"])
            elif event.key == pygame.K_RETURN:
                cmd = MENU[col_idx]["items"][row_idx]["cmd"]
                if cmd == "EXIT":
                    running = False
                else:
                    # Suspend Pygame, run command, resume
                    pygame.display.quit()
                    subprocess.call(cmd, shell=True)
                    pygame.display.init()
                    screen = pygame.display.set_mode((WIDTH, HEIGHT), pygame.NOFRAME)
                    if bg_img: # Reload bg might be needed depending on memory
                        screen.blit(bg_img, (0,0))

    # Animation Logic (Smooth scrolling horizontal)
    target_pos = -1 * (col_idx * (WIDTH // 3)) + (WIDTH // 3)
    current_x += (target_pos - current_x) / CFG["animation_speed"]

    # Draw Horizontal Categories
    for i, cat in enumerate(MENU):
        x_pos = current_x + (i * (WIDTH // 3))
        
        # Color based on selection
        color = CFG["highlight_color"] if i == col_idx else CFG["text_color"]
        size_mod = 1.2 if i == col_idx else 1.0
        
        # Draw Icon (Placeholder Circle if no image)
        icon_path = os.path.join(ASSETS_DIR, cat.get("icon", ""))
        if os.path.exists(icon_path):
            img = pygame.image.load(icon_path)
            # Scale logic here if needed
            screen.blit(img, (x_pos - 32, CFG["category_y"] - 70))
        else:
            pygame.draw.circle(screen, color, (int(x_pos), CFG["category_y"] - 30), 20)

        draw_text(screen, cat["category"], x_pos, CFG["category_y"], color, center=True, is_bold=(i==col_idx))

        # Draw Vertical Items (Only for active column)
        if i == col_idx:
            for j, item in enumerate(cat["items"]):
                y_pos = CFG["item_start_y"] + (j * (CFG["font_size"] + 20))
                item_color = CFG["highlight_color"] if j == row_idx else CFG["text_color"]
                
                # Highlight indicator
                if j == row_idx:
                    pygame.draw.rect(screen, (50,50,50), (x_pos - 150, y_pos - 5, 300, CFG["font_size"] + 10), border_radius=5)
                
                draw_text(screen, item["label"], x_pos, y_pos, item_color, center=True)

    pygame.display.flip()
    clock.tick(60)

pygame.quit()
EOF
chmod +x "$MENU_SCRIPT"

# -------------------------------
# 5. GENERATE DUMMY ASSETS
# -------------------------------
# This prevents the script from crashing if user has no images yet
touch "$INSTALL_DIR/assets/placeholder.txt"
# You can put "background.png", "icon_settings.png", "icon_games.png" in /usr/local/bin/xmb_boot/assets/

# -------------------------------
# 6. SETUP XINITRC & AUTOLOGIN
# -------------------------------
echo -e "${YELLOW}Configuring Startup...${NC}"

# Create .xinitrc to launch mapper and python menu
cat << EOF > "$HOME/.xinitrc"
#!/bin/bash
# Start the Controller Mapper in background
$PS3_MAPPER &
MAPPER_PID=\$!

# Disable screen saver
xset s off
xset -dpms

# Start the Python XMB Menu
python3 $MENU_SCRIPT

# Cleanup
kill \$MAPPER_PID
EOF

# Configure Shell to start X automatically on TTY1
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"

if ! grep -q "startx" "$TARGET_PROFILE"; then
    echo '[[ -z $DISPLAY && $(tty) == /dev/tty1 ]] && startx' >> "$TARGET_PROFILE"
fi

# Systemd Autologin
if command -v systemctl >/dev/null; then
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reload
fi

echo -e "${GREEN}DONE!${NC}"
echo "-----------------------------------------------------"
echo "1. Reboot your system."
echo "2. It will autologin and start the Graphical XMB Menu."
echo "-----------------------------------------------------"
echo "HOW TO CUSTOMIZE:"
echo "1. Go to: $INSTALL_DIR"
echo "2. Edit 'config.json' to change colors and font sizes."
echo "3. Edit 'menu.py' to add more menu items (Games, Apps)."
echo "4. Put images in '$INSTALL_DIR/assets/':"
echo "   - 'background.png' for wallpaper"
echo "   - 'icon_games.png', 'icon_settings.png' for categories."
echo "-----------------------------------------------------"