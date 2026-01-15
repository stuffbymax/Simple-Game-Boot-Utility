#use this at your own risk! because this script makes system-level changes and installs packages and is not tested  this file is only for me
#this script installs the Simple Game Boot Utility (SGBU) and sets up a boot menu for launching games and applications and configures controller input mapping. and it configures the system for auto-login and disables any graphical login managers. and it sets up RetroArch with default configurations and downloads necessary cores.
#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# CONFIGURATION & PATHS
# -------------------------------
USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
LOG_FILE="$HOME/install_log.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "   Simple Game Boot INSTALLER"
echo -e "================================================${NC}"

read -r -p "This script modifies system files. Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# PACKAGE MANAGER
# -------------------------------
declare -A PKGS

if command -v pacman >/dev/null; then
    INSTALL="sudo pacman -Syu --needed --noconfirm"
    PKGS=(
        [xorg]="xorg-server xorg-xinit"
        [py]="python-evdev python-uinput"
        [retro]="retroarch retroarch-assets"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
elif command -v apt-get >/dev/null; then
    INSTALL="sudo apt-get update && sudo apt-get install -y"
    PKGS=(
        [xorg]="xinit xserver-xorg-core xserver-xorg-input-all"
        [py]="python3-evdev python3-uinput"
        [retro]="retroarch"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
elif command -v dnf >/dev/null; then
    INSTALL="sudo dnf install -y"
    PKGS=(
        [xorg]="xorg-x11-server-Xorg xorg-x11-xinit"
        [py]="python3-evdev python3-uinput"
        [retro]="retroarch"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
else
    echo -e "${RED}Unsupported distro${NC}"
    exit 1
fi

$INSTALL ${PKGS[xorg]} ${PKGS[py]} ${PKGS[retro]} ${PKGS[utils]} || true

# -------------------------------
# UINPUT
# -------------------------------
sudo modprobe uinput || true
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null

sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input"
EOF

sudo usermod -aG input,video "$USER_NAME" || true

# -------------------------------
# CONTROLLER MAPPER
# -------------------------------
sudo tee "$PS3_PYTHON" >/dev/null << 'EOF'
#!/usr/bin/env python3
import evdev, uinput, sys

def find():
    for p in evdev.list_devices():
        d = evdev.InputDevice(p)
        caps = d.capabilities()
        if evdev.ecodes.EV_KEY in caps and evdev.ecodes.BTN_SOUTH in caps[evdev.ecodes.EV_KEY]:
            return d
    sys.exit("No controller found")

dev = find()
ui = uinput.Device([
    uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
    uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT
])

MAP = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
    307: uinput.KEY_BACKSPACE,
    308: uinput.KEY_SPACE
}

try:
    dev.grab()
    for e in dev.read_loop():
        if e.type == evdev.ecodes.EV_KEY and e.code in MAP:
            ui.emit(MAP[e.code], e.value)
        elif e.type == evdev.ecodes.EV_ABS:
            if e.code == evdev.ecodes.ABS_HAT0Y:
                ui.emit(uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN, 1)
                ui.emit(uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN, 0)
            elif e.code == evdev.ecodes.ABS_HAT0X:
                ui.emit(uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT, 1)
                ui.emit(uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT, 0)
finally:
    dev.ungrab()
EOF
sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# BOOT MENU
# -------------------------------
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

MAPPER="/usr/local/bin/ps3_to_keys.py"
TMP_XINIT="/tmp/sgbu-xinitrc"
export SGBU_RUNNING=1

DIALOG=dialog
command -v dialog >/dev/null || DIALOG=whiptail

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        echo "$(grep -m1 '^Name=' "$f" | cut -d= -f2)|$(grep -m1 '^Exec=' "$f" | cut -d= -f2)"
    done
}

detect_apps() {
    command -v steam >/dev/null && echo "Steam|steam -bigpicture"
}

launch_session() {
    cat > "$TMP_XINIT" <<EOF2
#!/usr/bin/env bash
antimicrox --hidden &
onboard &
exec $1
EOF2
    chmod +x "$TMP_XINIT"
    startx "$TMP_XINIT" -- :0
}

launch_clean() {
    echo "exec $1" > "$TMP_XINIT"
    chmod +x "$TMP_XINIT"
    startx "$TMP_XINIT" -- :0
}

"$MAPPER" &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    command -v retroarch >/dev/null && {
        ITEMS+=($i "RetroArch")
        ACTIONS+=("retroarch")
        ((i++))
    }

    while IFS='|' read -r n c; do
        ITEMS+=($i "$n")
        ACTIONS+=("app:$c")
        ((i++))
    done < <(detect_apps)

    while IFS='|' read -r n c; do
        ITEMS+=($i "Desktop: $n")
        ACTIONS+=("session:$c")
        ((i++))
    done < <(detect_sessions)

    ITEMS+=($i "Shell" $((i+1)) "Reboot" $((i+2)) "Shutdown")
    ACTIONS+=("shell" "reboot" "shutdown")

    CHOICE=$($DIALOG --menu "Simple Game Boot" 20 70 15 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit

    kill $PID 2>/dev/null || true

    case "${ACTIONS[$((CHOICE-1))]}" in
        retroarch) launch_clean "retroarch -f" ;;
        app:*)     launch_clean "${ACTIONS[$((CHOICE-1))]#app:}" ;;
        session:*) launch_session "${ACTIONS[$((CHOICE-1))]#session:}" ;;
        shell) bash ;;
        reboot) systemctl reboot || sudo reboot ;;
        shutdown) systemctl poweroff || sudo shutdown now ;;
    esac

    "$MAPPER" & PID=$!
done
EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# AUTOLOGIN
# -------------------------------
if command -v systemctl >/dev/null; then
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reload
fi

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


echo -e "${GREEN}Boot Menu installation complete.${NC}"
# -------------------------------
# RETROARCH CONFIG & CORES
# -------------------------------
echo -e "${YELLOW}Setting up RetroArch config and downloading cores...${NC}"
cp .conf/ $HOME/.config/

cd "$HOME/.config/retroarch/cores/"
wget -r -np -nd -R "index.html*" https://buildbot.libretro.com/nightly/linux/x86_64/latest/
unzip -o "*.zip"
rm *.zip 

PROFILE="$HOME/.bash_profile"
[ -f "$PROFILE" ] || PROFILE="$HOME/.profile"
grep -q bootmenu.sh "$PROFILE" || \
echo '[ -z "$SGBU_RUNNING" ] && [ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' >> "$PROFILE"

echo -e "${GREEN}DONE. Reboot.${NC}"
