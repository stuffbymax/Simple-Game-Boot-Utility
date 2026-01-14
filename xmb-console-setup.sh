#!/usr/bin/env bash
set -euo pipefail
echo "script is made by AI so it probably won't work"
############################
# CONFIG
############################
USER_NAME="$(whoami)"
XMB_APP="/usr/local/bin/XMB_Shell-x86_64.AppImage"
LAUNCHER="/usr/local/bin/xmb-launcher.sh"
LOG="$HOME/xmb-setup.log"

exec > >(tee -a "$LOG") 2>&1

############################
# INTRO
############################
echo "===================================="
echo "   XMB Console Kiosk Setup"
echo "===================================="
echo
read -rp "This will modify system files. Continue? [y/N]: " ok
[[ "${ok,,}" == "y" ]] || exit 1

############################
# PACKAGE INSTALL
############################
if command -v pacman >/dev/null; then
    sudo pacman -Sy --needed --noconfirm \
        xorg-server \
        xorg-xinit \
        xorg-xset \
        unclutter
elif command -v apt-get >/dev/null; then
    sudo apt-get update
    sudo apt-get install -y \
        xorg \
        xinit \
        x11-xserver-utils \
        unclutter
elif command -v dnf >/dev/null; then
    sudo dnf install -y \
        xorg-x11-server-Xorg \
        xorg-x11-xinit \
        xset \
        unclutter
else
    echo "Unsupported distro"
    exit 1
fi

############################
# VERIFY APPIMAGE
############################
if [ ! -f "$XMB_APP" ]; then
    echo
    echo "ERROR: XMB Shell AppImage not found:"
    echo "  $XMB_APP"
    echo "Place it there and re-run."
    exit 1
fi

sudo chmod +x "$XMB_APP"

############################
# CREATE LAUNCHER
############################
sudo tee "$LAUNCHER" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e

XMB="/usr/local/bin/XMB_Shell-x86_64.AppImage"
XINITRC="$HOME/.xinitrc-xmb"

cat > "$XINITRC" << 'EOT'
#!/usr/bin/env bash
xset -dpms
xset s off
xset s noblank

unclutter -idle 0.1 -root &

export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR=1

exec /usr/local/bin/XMB_Shell-x86_64.AppImage
EOT

chmod +x "$XINITRC"

if [ "$(tty)" = "/dev/tty1" ]; then
    exec startx "$XINITRC" -- -nocursor
fi
EOF

sudo chmod +x "$LAUNCHER"

############################
# TTY1 AUTOLOGIN
############################
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF

sudo systemctl daemon-reexec

############################
# SHELL AUTO-START
############################
PROFILE="$HOME/.bash_profile"
[[ ! -f "$PROFILE" ]] && PROFILE="$HOME/.profile"

if ! grep -q "xmb-launcher.sh" "$PROFILE" 2>/dev/null; then
    echo >> "$PROFILE"
    echo 'if [ "$(tty)" = "/dev/tty1" ]; then' >> "$PROFILE"
    echo '    exec /usr/local/bin/xmb-launcher.sh' >> "$PROFILE"
    echo 'fi' >> "$PROFILE"
fi

############################
# DISABLE DISPLAY MANAGERS
############################
for dm in gdm sddm lightdm lxdm; do
    sudo systemctl disable "$dm" 2>/dev/null || true
done

############################
# DONE
############################
echo
echo "===================================="
echo " SETUP COMPLETE"
echo "===================================="
echo
echo "Reboot to enter XMB console mode."
echo "Exit XMB = return to TTY1."
echo
