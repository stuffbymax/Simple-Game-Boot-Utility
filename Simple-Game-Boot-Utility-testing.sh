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
# Boot menu
# -------------------------------
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash

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

"$PS3_PYTHON" &
PS3_PID=$!

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    command -v retroarch >/dev/null && {
        ITEMS+=($i "RetroArch")
        ACTIONS+=("retroarch")
        ((i++))
    }

    STEAM=$(detect_steam || true)
    [ -n "$STEAM" ] && {
        ITEMS+=($i "Steam")
        ACTIONS+=("steam:$STEAM")
        ((i++))
    }

    while IFS='|' read -r name exec; do
        ITEMS+=($i "$name")
        ACTIONS+=("session:$exec")
        ((i++))
    done < <(detect_sessions)

    ITEMS+=(
        $i "Shell"
        $((i+1)) "Reboot"
        $((i+2)) "Shutdown"
    )
    ACTIONS+=("shell" "reboot" "shutdown")

    CHOICE=$(dialog --menu "Boot Menu" 20 60 15 "${ITEMS[@]}" 3>&1 1>&2 2>&3)
    clear

    kill "$PS3_PID" 2>/dev/null || true
    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        retroarch)
            retroarch -f
            ;;
        steam:*)
            pkill -f ps3_to_keys.py || true
            xinit ${ACTION#steam:} -bigpicture -- :0
            ;;
        session:*)
            echo "exec ${ACTION#session:}" > "$HOME/.xinitrc"
            antimicrox --hidden &
            onboard &
            startx
            ;;
        shell)
            bash
            ;;
        reboot)
            sudo reboot
            ;;
        shutdown)
            sudo shutdown now
            ;;
    esac

    "$PS3_PYTHON" &
    PS3_PID=$!
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
