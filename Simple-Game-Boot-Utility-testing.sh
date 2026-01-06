#!/usr/bin/env bash
set -euo pipefail

LOG="$HOME/bootmenu-install.log"
exec > >(tee -a "$LOG") 2>&1

USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"

echo "WARNING: Experimental boot menu installer"
read -r -p "Continue? [y/N]: " CONFIRM
[ "${CONFIRM,,}" = "y" ] || exit 1

# -------------------------------------------------
# Package manager detection (best effort)
# -------------------------------------------------
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
                dialog xorg-server xorg-xinit \
                retroarch antimicrox onboard \
                python-evdev python-uinput \
                wget curl unzip sudo neovim tmux \
                procps-ng util-linux iproute2
            ;;
        apt)
            sudo apt update
            sudo apt install -y \
                dialog xinit xserver-xorg-core \
                retroarch antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux \
                procps util-linux iproute2
            ;;
        dnf)
            sudo dnf install -y \
                dialog xorg-x11-server-Xorg xorg-x11-xinit \
                retroarch antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux \
                procps-ng util-linux iproute
            ;;
        zypper)
            sudo zypper install -y \
                dialog xorg-x11-server xinit \
                retroarch antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux \
                procps util-linux iproute2
            ;;
        xbps-install)
            sudo xbps-install -Sy \
                dialog xorg-minimal xinit \
                retroarch antimicrox onboard \
                python3-evdev python3-uinput \
                wget curl unzip sudo neovim tmux \
                procps util-linux iproute2
            ;;
        apk)
            sudo apk add \
                dialog xorg-server xinit \
                retroarch antimicrox onboard \
                py3-evdev py3-uinput \
                wget curl unzip sudo neovim tmux \
                procps util-linux iproute2
            ;;
        *)
            echo "Unsupported distro. Install dependencies manually."
            ;;
    esac
}

install_packages || true

# -------------------------------------------------
# uinput setup (portable)
# -------------------------------------------------
sudo modprobe uinput 2>/dev/null || true
[ -e /dev/uinput ] && sudo chmod 666 /dev/uinput || true

if command -v systemctl >/dev/null; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
fi

# -------------------------------------------------
# Controller -> keyboard mapper
# -------------------------------------------------
sudo tee "$PS3_PYTHON" >/dev/null << 'EOF'
#!/usr/bin/env python3
import evdev, uinput, sys

devices = [evdev.InputDevice(p) for p in evdev.list_devices()]
device = next((d for d in devices if evdev.ecodes.EV_KEY in d.capabilities()), None)

if not device:
    print("No input device found")
    sys.exit(1)

events = [
    uinput.KEY_ENTER, uinput.KEY_ESC,
    uinput.KEY_UP, uinput.KEY_DOWN,
    uinput.KEY_LEFT, uinput.KEY_RIGHT
]

ui = uinput.Device(events)

BTN_MAP = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
}

device.grab()

for e in device.read_loop():
    if e.type == evdev.ecodes.EV_KEY and e.code in BTN_MAP:
        ui.emit(BTN_MAP[e.code], e.value)
    elif e.type == evdev.ecodes.EV_ABS:
        if e.code == evdev.ecodes.ABS_HAT0Y:
            ui.emit(uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN, 1)
            ui.emit(uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN, 0)
        elif e.code == evdev.ecodes.ABS_HAT0X:
            ui.emit(uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT, 1)
            ui.emit(uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT, 0)
EOF

sudo chmod +x "$PS3_PYTHON"

# -------------------------------------------------
# Boot menu
# -------------------------------------------------
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

DEBUG=0

toggle_debug() {
    if [ "$DEBUG" -eq 0 ]; then
        set -x
        DEBUG=1
    else
        set +x
        DEBUG=0
    fi
}

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [ -n "$name" ] && [ -n "$exec" ] && echo "$name|$exec"
    done
}

detect_steam() {
    command -v steam >/dev/null && echo "steam" && return
    command -v flatpak >/dev/null && flatpak list 2>/dev/null | grep -qi steam \
        && echo "flatpak run com.valvesoftware.Steam"
}

system_monitor() {
    while true; do
        clear
        echo "SYSTEM MONITOR"
        echo "=============="
        echo
        uptime
        echo
        free -h 2>/dev/null || true
        echo
        df -h / 2>/dev/null || true
        echo
        ip -brief addr show 2>/dev/null || true
        echo
        echo "Press q to return"
        read -r -t 2 key
        [ "$key" = "q" ] && break
    done
}

diagnostics_menu() {
    while true; do
        CHOICE=$(dialog --menu "Diagnostics" 20 70 10 \
            1 "System Info" \
            2 "Kernel Messages" \
            3 "Boot Errors" \
            4 "Input Test" \
            5 "Network Test" \
            6 "Back" \
            3>&1 1>&2 2>&3)
        clear
        case "$CHOICE" in
            1)
                uname -a
                lsblk 2>/dev/null || true
                read -r -p "Press Enter..."
                ;;
            2)
                dmesg | less
                ;;
            3)
                command -v journalctl >/dev/null \
                    && journalctl -b -p err --no-pager | less \
                    || echo "journalctl unavailable"
                read -r -p "Press Enter..."
                ;;
            4)
                evtest 2>/dev/null || echo "evtest not installed"
                read -r -p "Press Enter..."
                ;;
            5)
                ping -c 3 1.1.1.1 || true
                ip route || true
                read -r -p "Press Enter..."
                ;;
            *)
                break
                ;;
        esac
    done
}

"$HOME"/ps3_to_keys.py 2>/dev/null &
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
        $i "System Monitor"
        $((i+1)) "Diagnostics"
        $((i+2)) "Toggle Debug"
        $((i+3)) "Shell"
        $((i+4)) "Reboot"
        $((i+5)) "Shutdown"
    )

    ACTIONS+=(
        "monitor"
        "diagnostics"
        "debug"
        "shell"
        "reboot"
        "shutdown"
    )

    CHOICE=$(dialog --menu "Boot Menu" 20 70 15 "${ITEMS[@]}" \
        3>&1 1>&2 2>&3)

    kill "$PS3_PID" 2>/dev/null || true
    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        retroarch) retroarch -f ;;
        steam:*) xinit ${ACTION#steam:} -bigpicture -- :0 ;;
        session:*)
            echo "exec ${ACTION#session:}" > "$HOME/.xinitrc"
            antimicrox --hidden &
            onboard &
            startx
            ;;
        monitor) system_monitor ;;
        diagnostics) diagnostics_menu ;;
        debug) toggle_debug ;;
        shell) bash ;;
        reboot) reboot ;;
        shutdown) shutdown now ;;
    esac

    "$HOME"/ps3_to_keys.py 2>/dev/null &
    PS3_PID=$!
done
EOF

sudo chmod +x "$BOOTMENU"

# -------------------------------------------------
# Autostart on tty1 (portable)
# -------------------------------------------------
PROFILE="$HOME/.bash_profile"
grep -qxF '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' "$PROFILE" \
    || echo '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' >> "$PROFILE"

if command -v systemctl >/dev/null; then
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reexec
fi

echo "INSTALL COMPLETE"
echo "Reboot to enter boot menu"
