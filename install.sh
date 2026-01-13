#!/usr/bin/env bash
set -euo pipefail

USER_NAME="$(whoami)"
LOG_FILE="$HOME/install_log.txt"

BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Simple Game Boot installer"
read -r -p "This modifies system files. Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# Package manager detection
# -------------------------------
declare -A PKGS

if command -v pacman >/dev/null; then
    INSTALL="sudo pacman -Sy --needed --noconfirm"
    PKGS=(
        [xorg]="xorg-server xorg-xinit xorg-xinput"
        [py_evdev]="python-evdev"
        [py_uinput]="python-uinput"
        [retro]="retroarch retroarch-assets"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
elif command -v apt-get >/dev/null; then
    INSTALL="sudo apt-get update && sudo apt-get install -y"
    PKGS=(
        [xorg]="xinit xserver-xorg-core xserver-xorg-input-all"
        [py_evdev]="python3-evdev"
        [py_uinput]="python3-uinput"
        [retro]="retroarch"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
elif command -v dnf >/dev/null; then
    INSTALL="sudo dnf install -y"
    PKGS=(
        [xorg]="xorg-x11-server-Xorg xorg-x11-xinit"
        [py_evdev]="python3-evdev"
        [py_uinput]="python3-uinput"
        [retro]="retroarch"
        [utils]="dialog onboard wget curl unzip sudo neovim tmux antimicrox"
    )
else
    echo "Unsupported distro"
    exit 1
fi

$INSTALL \
    ${PKGS[xorg]} \
    ${PKGS[py_evdev]} \
    ${PKGS[py_uinput]} \
    ${PKGS[retro]} \
    ${PKGS[utils]} || true

# -------------------------------
# uinput + permissions
# -------------------------------
sudo modprobe uinput || true
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null

sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

sudo usermod -aG input "$USER_NAME" || true
sudo usermod -aG video "$USER_NAME" || true

# -------------------------------
# Install scripts
# -------------------------------
sudo install -Dm755 ps3_to_keys.py "$PS3_PYTHON"
sudo install -Dm755 bootmenu.sh "$BOOTMENU"

# -------------------------------
# systemd autologin
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

# -------------------------------
# shell trigger
# -------------------------------
PROFILE="$HOME/.bash_profile"
[[ ! -f "$PROFILE" ]] && PROFILE="$HOME/.profile"

grep -q bootmenu.sh "$PROFILE" || \
    echo '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' >> "$PROFILE"

echo "Done. Reboot."
