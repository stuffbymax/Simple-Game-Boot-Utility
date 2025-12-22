#!/bin/bash
set -e

exec > >(tee -a ~/log.txt) 2>&1

USER_NAME=$(whoami)
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
ANTIMICROX_PROFILE="$HOME/.config/antimicrox/bootmenu_gamepad_profile.amgp"

# -------------------------------
# WARNING
# -------------------------------
echo "WARNING: Experimental script"
read -p "Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# Packages
# -------------------------------
sudo apt update
sudo apt install -y \
    retroarch retroarch-assets \
    xinit xserver-xorg-core xserver-xorg-input-all \
    dialog antimicrox onboard \
    python3-evdev python3-uinput \
    wget curl unzip sudo neovim tmux

# -------------------------------
# uinput
# -------------------------------
sudo modprobe uinput
sudo chmod 777 /dev/uinput
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf

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
            ui.emit(uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN, 1)
            ui.emit(uinput.KEY_UP if e.value == -1 else uinput.KEY_DOWN, 0)
        if e.code == evdev.ecodes.ABS_HAT0X:
            ui.emit(uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT, 1)
            ui.emit(uinput.KEY_LEFT if e.value == -1 else uinput.KEY_RIGHT, 0)
EOF
sudo chmod +x "$PS3_PYTHON"

# -------------------------------
# Boot menu (AUTO-DETECT)
# -------------------------------
sudo tee "$BOOTMENU" >/dev/null << 'EOF'
#!/bin/bash

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [[ -n "$name" && -n "$exec" ]] && echo "$name|$exec"
    done
}

detect_steam() {
    command -v steam && echo steam && return
    command -v flatpak && flatpak list | grep -qi steam && echo "flatpak run com.valvesoftware.Steam"
}

"$PS3_PYTHON" &
PS3_PID=$!

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    if command -v retroarch >/dev/null; then
        ITEMS+=($i "RetroArch")
        ACTIONS+=("retroarch")
        ((i++))
    fi

    STEAM=$(detect_steam)
    if [ -n "$STEAM" ]; then
        ITEMS+=($i "Steam")
        ACTIONS+=("steam:$STEAM")
        ((i++))
    fi

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

    kill $PS3_PID 2>/dev/null || true
    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        retroarch)
            retroarch -f
            ;;
        steam:*)
            ${ACTION#steam:}
            ;;
        session:*)
            echo "exec ${ACTION#session:}" > ~/.xinitrc
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
# Autologin tty1
# -------------------------------
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
sudo systemctl daemon-reexec

grep -qxF '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' ~/.bash_profile || \
echo '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' >> ~/.bash_profile

echo "DONE. Reboot."
