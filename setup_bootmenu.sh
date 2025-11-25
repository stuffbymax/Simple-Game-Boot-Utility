#note external files are not yet uploaded to github

#!/bin/bash
set -e

exec > >(tee -a ~/log.txt) 2>&1

USER_NAME=$(whoami)
BOOTMENU="/usr/local/bin/bootmenu.sh"
PS3_PYTHON="/usr/local/bin/ps3_to_keys.py"
ICEWM_MENU="$HOME/.icewm/menu"
AUTOSTART_DIR="$HOME/.config/autostart"
ANTIMICROX_PROFILE="$HOME/.config/antimicrox/bootmenu_gamepad_profile.amgp"
conf="retro/conf"
# -------------------------------
# WARNING / ACKNOWLEDGEMENT
# -------------------------------
echo -e "\e[33mWARNING: This script is experimental and may NOT work as intended!\e[0m"
echo -e "\e[33mKnown issues:\e[0m"
echo -e "\e[33m - Keybindings may be missing or incomplete\e[0m"
echo -e "\e[33m - Drivers are default to Intel only\e you have to change it depending on your GPU[0m"
echo -e "\e[33m - Some features require manual follow-up\e[0m"
echo -e "\e[33m - External files are not yet uploaded to GitHub\e[0m"
echo ""

read -p "Do you want to continue? [y/N]: " CONFIRM
CONFIRM=${CONFIRM,,}  # lowercase
if [[ "$CONFIRM" != "y" ]]; then
    echo "Exiting script. No changes were made."
    exit 1
fi


# === Install required packages ===
sudo apt update
echo "update complete"
sudo apt install -y retroarch icewm xfce4 xfce4-goodies xinit xserver-xorg-core xserver-xorg-input-all dialog sudo antimicrox unzip python3-evdev python3-uinput wget curl neovim tmux
echo "installed necesery software"

echo "installing retro arch assets"
sudo apt -y install retroarch-assets
echo "retro arch assets completed"

# here make script for select your gpu driver.eg. 1. (Intel), 2.(AMD) 3. (Nvidia)
echo -e "please select GPU Driver"
echo -e "1) Intel"
echo -e "2) AMD"
echo -e "3) ATI"
echo -e "4) Nvidia (open source)"
echo -e "5) Nvidia (propriatery)"

read -p "Enter your choice (1 or 5): " choice

case $choice in
    1)
        echo "You selected 1. installing Intel..."
        sudo apt install -y xserver-xorg-video-intel
        ;;
    2)
        echo "You selected 2. installing AMD..."
        sudo apt install -y xserver-xorg-video-amdgpu
        ;;
    3)
        echo "You selected 3. installing ATI..."
        sudo apt install -y xserver-xorg-video-ati
        ;;
    4)
        echo "You selected 4. installing Nvidia (open source)..."
        sudo apt install -y xserver-xorg-video-nouveau
        ;;
    5)
        echo "You selected 5. installing Nvidia (open source)..."
        sudo apt install -y nvidia-driver
        ;;
    *)
        echo "Invalid choice. Please run the script again and select 1 or 5."
        ;;
esac

# Load uinput and add user to input group
echo -e "\e[31mWarning: this will set up read write execute (rwx-rwx-rwx-) permissions to /dev/uinput\e[0m"

#sudo usermod -aG input $USER_NAME
sudo modprobe uinput
sudo chmod 777 /dev/uinput

echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf


# -------------------------------
# Step 1: Python PS3 TTY mapper
# -------------------------------
sudo tee $PS3_PYTHON > /dev/null << 'EOF'
#!/usr/bin/env python3
import evdev
import uinput
import sys

# 1. Find any controller with buttons
def find_controller():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if evdev.ecodes.EV_KEY in device.capabilities():
            return device
    print("No controller found.")
    sys.exit(1)

device = find_controller()
print(f"Using device: {device.path} ({device.name})")

# 2. Create uinput device with all mapped keys
events = [
    uinput.KEY_ENTER, uinput.KEY_ESC, uinput.KEY_BACKSPACE, uinput.KEY_SPACE,
    uinput.KEY_UP, uinput.KEY_DOWN, uinput.KEY_LEFT, uinput.KEY_RIGHT
]
ui = uinput.Device(events)

# 3. Individual BTN_MAP dictionaries

# PS3
BTN_MAP_PS3 = {
    304: uinput.KEY_ENTER,      # X
    305: uinput.KEY_ESC,        # Circle
    307: uinput.KEY_BACKSPACE,  # Square
    308: uinput.KEY_SPACE,      # Triangle
    544: uinput.KEY_UP,         # D-pad Up
    545: uinput.KEY_DOWN,       # D-pad Down
    546: uinput.KEY_LEFT,       # D-pad Left
    547: uinput.KEY_RIGHT       # D-pad Right
}

# PS4
BTN_MAP_PS4 = {
    304: uinput.KEY_ENTER,      # Cross
    305: uinput.KEY_ESC,        # Circle
    307: uinput.KEY_BACKSPACE,  # Square
    308: uinput.KEY_SPACE,      # Triangle
    544: uinput.KEY_UP,         # D-pad Up
    545: uinput.KEY_DOWN,       # D-pad Down
    546: uinput.KEY_LEFT,       # D-pad Left
    547: uinput.KEY_RIGHT       # D-pad Right
}

# Xbox 360 / One
BTN_MAP_XBOX = {
    304: uinput.KEY_ENTER,      # A
    305: uinput.KEY_ESC,        # B
    307: uinput.KEY_BACKSPACE,  # X
    308: uinput.KEY_SPACE,      # Y
    544: uinput.KEY_UP,         # D-pad Up (for EV_KEY devices)
    545: uinput.KEY_DOWN,       # D-pad Down
    546: uinput.KEY_LEFT,       # D-pad Left
    547: uinput.KEY_RIGHT       # D-pad Right
}

# Generic controller
BTN_MAP_GENERIC = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
    307: uinput.KEY_BACKSPACE,
    308: uinput.KEY_SPACE,
    544: uinput.KEY_UP,
    545: uinput.KEY_DOWN,
    546: uinput.KEY_LEFT,
    547: uinput.KEY_RIGHT
}

# Generic Xbox pad (hat axes)
BTN_MAP_GENERIC_XBOX = {
    304: uinput.KEY_ENTER,
    305: uinput.KEY_ESC,
    307: uinput.KEY_BACKSPACE,
    308: uinput.KEY_SPACE,
    1000: uinput.KEY_UP,        # D-pad Up (ABS_HAT0Y = -1)
    1001: uinput.KEY_DOWN,      # D-pad Down (ABS_HAT0Y = 1)
    1002: uinput.KEY_LEFT,      # D-pad Left (ABS_HAT0X = -1)
    1003: uinput.KEY_RIGHT      # D-pad Right (ABS_HAT0X = 1)
}

# 4. Choose which BTN_MAP to use
# Example: you can select based on device name
if "PLAYSTATION" in device.name.upper() or "PS3" in device.name.upper():
    BTN_MAP = BTN_MAP_PS3
elif "PS4" in device.name.upper():
    BTN_MAP = BTN_MAP_PS4
elif "XBOX" in device.name.upper():
    BTN_MAP = BTN_MAP_XBOX
else:
    BTN_MAP = BTN_MAP_GENERIC_XBOX  # fallback for generic/Xbox controllers

# 5. Grab the device and emit key events
device.grab()
for event in device.read_loop():
    # EV_KEY buttons
    if event.type == evdev.ecodes.EV_KEY:
        key = BTN_MAP.get(event.code)
        if key is not None:
            ui.emit(key, event.value)

    # EV_ABS for generic Xbox D-pad
    elif event.type == evdev.ecodes.EV_ABS:
        if event.code == evdev.ecodes.ABS_HAT0Y:
            if event.value == -1:  # Up
                ui.emit(BTN_MAP.get(1000, uinput.KEY_UP), 1)
                ui.emit(BTN_MAP.get(1000, uinput.KEY_UP), 0)
            elif event.value == 1:  # Down
                ui.emit(BTN_MAP.get(1001, uinput.KEY_DOWN), 1)
                ui.emit(BTN_MAP.get(1001, uinput.KEY_DOWN), 0)
        elif event.code == evdev.ecodes.ABS_HAT0X:
            if event.value == -1:  # Left
                ui.emit(BTN_MAP.get(1002, uinput.KEY_LEFT), 1)
                ui.emit(BTN_MAP.get(1002, uinput.KEY_LEFT), 0)
            elif event.value == 1:  # Right
                ui.emit(BTN_MAP.get(1003, uinput.KEY_RIGHT), 1)
                ui.emit(BTN_MAP.get(1003, uinput.KEY_RIGHT), 0)
EOF
sudo chmod 777 $PS3_PYTHON

# -------------------------------
# Step 2: Boot menu script
# -------------------------------
sudo tee $BOOTMENU > /dev/null << EOF
#!/bin/bash
# Start Python PS3 mapper in background
$PS3_PYTHON &
PS3_PID=\$!

while true; do
CHOICE=\$(dialog --clear --backtitle "Debian Boot Menu" \
--title "Boot Menu" \
--menu "Choose an option:" 20 60 9 \
1 "Launch RetroArch (fullscreen)" \
2 "Launch IceWM Desktop" \
3 "Launch XFCE4 Desktop" \
4 "Update System (apt upgrade)" \
5 "Open Shell (TTY)" \
6 "Network Configuration" \
7 "Reboot" \
8 "Shutdown" 3>&1 1>&2 2>&3)


clear

case \$CHOICE in
1)
    kill \$PS3_PID 2>/dev/null || true
    retroarch -f
    $PS3_PYTHON &
    PS3_PID=\$!
    ;;
2)
    kill \$PS3_PID 2>/dev/null || true
    echo "exec icewm-session" > ~/.xinitrc
    # Start AntimicroX in IceWM
    antimicrox --hidden --profile $ANTIMICROX_PROFILE &
    onboard &
    startx
    $PS3_PYTHON &
    PS3_PID=\$!
    ;;
3)
    kill \$PS3_PID 2>/dev/null || true
    echo "exec startxfce4" > ~/.xinitrc
    # Start AntimicroX in XFCE
    antimicrox --hidden --profile $ANTIMICROX_PROFILE &
    onboard &
    startx
    $PS3_PYTHON &
    PS3_PID=\$!
    ;;
4)
    # System update with animated '===' progress bar
    clear
    echo -e  "\e[42m=== Updating system... please wait ===\e[0m"
    echo "(Full log at /tmp/apt_update.log)"
    sudo apt update -y && sudo apt upgrade -y &> /tmp/apt_update.log &
    PID=$!
    BAR="#"
    WIDTH=40
    while kill -0 $PID 2>/dev/null; do
        if [ ${#BAR} -lt $WIDTH ]; then
            BAR="$BAR="
        else
            BAR=""
        fi
        printf "\r[%s] Updating..." "$BAR"
        sleep 0.2
    done
    wait $PID
    printf "\r[%s] Update complete!          \n" "$(printf '=%.0s' $(seq 1 $WIDTH))"
    sleep 2
    echo "exiting"
    exit
    ;;
5)
    clear
    echo -e "\e[42m=== Entering shell ===\e[0m"
    echo "Type 'exit' to return to the Boot Menu."
    bash
    ;;
6)
    clear
    echo "=== Network Configuration ==="
    echo -e "\e[41mcurrently mapping is only set to up down left right enter back so you have to use keyboard\e[0m"
    # echo "Use your controller to navigate!"
    echo -e "\e[42mLaunching nmtui...\e[0m"
    sleep 1
    $PS3_PYTHON &
    PS3_PID=$!
    sudo nmtui
    kill $PS3_PID 2>/dev/null || true
    echo "Network configuration done!"
    sleep 2
    ;;
7)
    kill $PS3_PID 2>/dev/null || true
    sudo reboot
    ;;
8)
    kill $PS3_PID 2>/dev/null || true
    sudo shutdown now
    ;;
esac
done

EOF
sudo chmod +x $BOOTMENU

# -------------------------------
# Step 3: Auto-login on tty1
# -------------------------------
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
sudo systemctl daemon-reexec

# Launch boot menu automatically on tty1
grep -qxF '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' ~/.bash_profile || \
echo '[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh' >> ~/.bash_profile

# -------------------------------
# Step 4: IceWM menu
# -------------------------------
mkdir -p "$(dirname "$ICEWM_MENU")"
cat > "$ICEWM_MENU" << EOF

menuprog "apps" folder icewm-menu-fdo
prog Terminal x-terminal-emulator x-terminal-emulator
prog FileManager thunar thunar

sep

prog Restart IceWM restart icewm --restart
prog Logout logout logout
EOF

# -------------------------------
# Step 5: AntimicroX autostart for XFCE4
# -------------------------------
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/antimicrox.desktop" << EOF
[Desktop Entry]
Type=Application
Exec=antimicrox --hidden --profile /home/zdislav/.config/antimicrox/bootmenu_gamepad_profile.amgp
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=AntimicroX
Comment=Start AntimicroX with profile

EOF

# -------------------------------
# Step 6: AntimicroX + Onboard autostart for IceWM
# -------------------------------
mkdir -p ~/.icewm
cat > ~/.icewm/startup << EOF
#!/bin/bash
# Start AntimicroX with profile
antimicrox --hidden --profile $ANTIMICROX_PROFILE &

# Start Onboard on-screen keyboard
onboard &
EOF
chmod +x ~/.icewm/startup


# -------------------------------
# Step6.1: Onboard autostart for xfce4
# -------------------------------
# Onboard autostart
cat > "$AUTOSTART_DIR/onboard.desktop" << EOF
[Desktop Entry]
Type=Application
Exec=onboard
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Onboard
Comment=Start Onboard on-screen keyboard
EOF


# -------------------------------
# Step 7: Latest Download RetroArch cores (all .zip files)
# Because debian has older files
# ------------------------------- 

echo "downloading retroarch lates cores"
mkdir -p ~/.config/retroarch/cores
cd ~/.config/retroarch/cores
sudo wget -r -np -nH --cut-dirs=4 -A "*.zip" https://buildbot.libretro.com/nightly/linux/x86_64/latest/
sudo find . -name "*.zip" -exec unzip -o {} \;
sudo find . -name "*.zip" -delete

echo -e "\e[42mAll RetroArch cores downloaded and extracted.\e[0m"

cd ~
cp -r "$conf"/* ".config/"


echo -e "\e[42m=== Setup complete! Reboot to test ===\e[0m"
echo -e "\e[41mTo check errors, read ./log.txt\e[0m"
