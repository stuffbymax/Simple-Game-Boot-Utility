#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# PATHS
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
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${YELLOW}================================================"
echo -e "   PS3 XMB (Emoji Edition) INSTALLER"
echo -e "================================================${NC}"
echo "Targets: Arch, Debian, Ubuntu, Fedora"
read -r -p "Install? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# 1. INSTALL DEPENDENCIES
# -------------------------------
# We need a font that supports symbols/emojis (Noto or DejaVu)
declare -A PKGS

if command -v pacman >/dev/null; then
    INSTALL="sudo pacman -Sy --needed --noconfirm"
    PKGS_LIST="xorg-server xorg-xinit python-evdev python-uinput python-pygame retroarch not-fonts-emoji ttf-dejavu"
elif command -v apt-get >/dev/null; then
    INSTALL="sudo apt-get update && sudo apt-get install -y"
    PKGS_LIST="xinit xserver-xorg python3-evdev python3-uinput python3-pygame retroarch fonts-noto-color-emoji fonts-dejavu"
elif command -v dnf >/dev/null; then
    INSTALL="sudo dnf install -y"
    PKGS_LIST="xorg-x11-server-Xorg xorg-x11-xinit python3-evdev python3-uinput python3-pygame retroarch google-noto-emoji-fonts dejavu-sans-fonts"
else
    echo -e "${RED}Unsupported Distro.${NC}"
    exit 1
fi

echo -e "${YELLOW}Installing system packages...${NC}"
$INSTALL $PKGS_LIST || echo "Package install had warnings, continuing..."

# -------------------------------
# 2. SETUP DIRECTORIES & PERMISSIONS
# -------------------------------
echo -e "${YELLOW}Creating directories...${NC}"
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"

# Uinput permissions (for Controller)
sudo modprobe uinput || true
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF
sudo usermod -aG input "$USER_NAME"
sudo usermod -aG video "$USER_NAME"

# -------------------------------
# 3. CREATE CONFIG FILES (JSON)
# -------------------------------
echo -e "${YELLOW}Creating configuration files...${NC}"

# 3a. Visual Config (Colors)
cat << EOF > "$INSTALL_DIR/config.json"
{
    "bg_color": [15, 15, 15],
    "highlight_color": [255, 255, 255],
    "text_color": [100, 100, 100],
    "font_size": 32,
    "icon_size": 64,
    "animation_speed": 10
}
EOF

# 3b. Menu Structure (Where you put emojis!)
cat << EOF > "$INSTALL_DIR/menu.json"
[
    {
        "category": "Settings",
        "icon": "⚙️",
        "items": [
            {"label": "Reboot", "cmd": "sudo reboot"},
            {"label": "Shutdown", "cmd": "sudo shutdown now"},
            {"label": "WiFi Setup", "cmd": "nmtui"},
            {"label": "Exit", "cmd": "EXIT"}
        ]
    },
    {
        "category": "Games",
        "icon": "🎮",
        "items": [
            {"label": "RetroArch", "cmd": "retroarch -f"},
            {"label": "Snake", "cmd": "python3 -m terminal_snake"} 
        ]
    },
    {
        "category": "Media",
        "icon": "🍿",
        "items": [
            {"label": "File Manager", "cmd": "mc"},
            {"label": "YouTube (Terminal)", "cmd": "yt-dlp"} 
        ]
    },
    {
        "category": "Network",
        "icon": "🌐",
        "items": [
            {"label": "Browser", "cmd": "firefox"}
        ]
    }
]
EOF

# -------------------------------
# 4. PYTHON CONTROLLER MAPPER
# -------------------------------
cat << 'EOF' > "$PS3_MAPPER"
#!/usr/bin/env python3
import evdev, uinput, sys
from evdev import ecodes

def get_gamepad():
    try:
        for path in evdev.list_devices():
            d = evdev.InputDevice(path)
            if ecodes.EV_KEY in d.capabilities(): return d
    except: pass
    return None

try:
    device = get_gamepad()
    if not device: sys.exit(0)
    
    # Map Gamepad to Keys for the Menu
    ui = uinput.Device([uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT, uinput.KEY_ENTER, uinput.KEY_ESC])
    device.grab()
    
    for e in device.read_loop():
        if e.type == ecodes.EV_KEY:
            # 304=X(PS3), 305=O(PS3) - codes vary by controller
            if e.code in [304, 315]: ui.emit(uinput.KEY_ENTER, e.value)
            elif e.code in [305, 316]: ui.emit(uinput.KEY_ESC, e.value)
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
# 5. PYTHON XMB MENU (Emoji Version)
# -------------------------------
cat << 'EOF' > "$MENU_SCRIPT"
#!/usr/bin/env python3
import pygame
import os
import sys
import subprocess
import json

# Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "config.json")
MENU_FILE = os.path.join(BASE_DIR, "menu.json")

# Load Config
def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

CFG = load_json(CONFIG_FILE)
MENU = load_json(MENU_FILE)

pygame.init()
info = pygame.display.Info()
WIDTH, HEIGHT = info.current_w, info.current_h
screen = pygame.display.set_mode((WIDTH, HEIGHT), pygame.NOFRAME)
pygame.mouse.set_visible(False)
clock = pygame.time.Clock()

# Fonts - Try to find a font that supports emojis/symbols
# Dejavu Sans usually has good coverage for standard symbols
font_name = pygame.font.match_font('dejavusans') 
if not font_name: font_name = pygame.font.match_font('arial')

text_font = pygame.font.Font(font_name, CFG["font_size"])
# Icon font is larger
icon_font = pygame.font.Font(font_name, CFG["icon_size"])

# State
col_idx = 1
row_idx = 0
current_x = 0

def run_cmd(cmd):
    if cmd == "EXIT": return False
    pygame.display.quit()
    subprocess.call(cmd, shell=True)
    pygame.display.init()
    pygame.display.set_mode((WIDTH, HEIGHT), pygame.NOFRAME)
    return True

running = True
while running:
    screen.fill(CFG["bg_color"])

    # Input
    for event in pygame.event.get():
        if event.type == pygame.QUIT: running = False
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
                if not run_cmd(MENU[col_idx]["items"][row_idx]["cmd"]):
                    running = False

    # Animation
    target_pos = -1 * (col_idx * (WIDTH // 4)) + (WIDTH // 2)
    current_x += (target_pos - current_x) / CFG["animation_speed"]

    # Drawing
    category_y = HEIGHT // 3
    
    for i, cat in enumerate(MENU):
        x_pos = int(current_x + (i * (WIDTH // 4)))
        
        # Determine Color and Focus
        is_selected = (i == col_idx)
        color = CFG["highlight_color"] if is_selected else CFG["text_color"]
        
        # 1. Draw Category Icon (Emoji)
        # Note: Pygame renders emojis as monochrome text usually
        try:
            icon_surf = icon_font.render(cat["icon"], True, color)
            icon_rect = icon_surf.get_rect(center=(x_pos, category_y))
            screen.blit(icon_surf, icon_rect)
        except:
            # Fallback if font fails
            pygame.draw.circle(screen, color, (x_pos, category_y), 20)

        # 2. Draw Category Label
        if is_selected:
             lbl_surf = text_font.render(cat["category"], True, color)
             lbl_rect = lbl_surf.get_rect(center=(x_pos, category_y + 60))
             screen.blit(lbl_surf, lbl_rect)

        # 3. Draw Items (Vertical List) - Only for selected category
        if is_selected:
            for j, item in enumerate(cat["items"]):
                item_y = category_y + 120 + (j * (CFG["font_size"] + 15))
                
                item_color = CFG["highlight_color"] if j == row_idx else CFG["text_color"]
                
                # Selection Box
                if j == row_idx:
                    pygame.draw.rect(screen, (40,40,40), (x_pos - 150, item_y - 10, 300, CFG["font_size"] + 20), border_radius=10)

                item_surf = text_font.render(item["label"], True, item_color)
                item_rect = item_surf.get_rect(center=(x_pos, item_y + (CFG["font_size"]//2)))
                screen.blit(item_surf, item_rect)

    pygame.display.flip()
    clock.tick(60)
pygame.quit()
EOF
chmod +x "$MENU_SCRIPT"

# -------------------------------
# 6. AUTOSTART SETUP
# -------------------------------
echo -e "${YELLOW}Configuring Autostart...${NC}"

# .xinitrc
cat << EOF > "$HOME/.xinitrc"
#!/bin/bash
$PS3_MAPPER &
MAPPER_PID=\$!
xset s off -dpms
python3 $MENU_SCRIPT
kill \$MAPPER_PID
EOF

# Bash Profile trigger
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

echo -e "${GREEN}Installation Complete!${NC}"
echo "--------------------------------------------------------"
echo "1. Reboot now."
echo "2. To customize the menu, edit this file:"
echo "   nano $INSTALL_DIR/menu.json"
echo "   (You can paste any Emoji in there!)"
echo "--------------------------------------------------------"