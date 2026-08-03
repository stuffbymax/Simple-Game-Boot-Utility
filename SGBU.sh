#!/usr/bin/env bash
# created BY marinP/stuffbymax (Multi-Distro fork)
# description: Installer script for Simple Game Boot Utility (SGBU) - Multi-Distro Edition
# Supports: Arch Linux, Debian/Ubuntu, Gentoo
# License: MIT
# version 0.0.7.0 - GamepadUI, Multi-Distro, Steam + Vulkan driver selection, bundled RetroArch/AntiMicroX configs
#
# NOTE: This script expects to be run from inside a clone of the SGBU repo,
# with a "conf" folder sitting next to it (conf/retroarch, conf/antimicrox).
# If you only downloaded this file on its own, the RetroArch/AntiMicroX
# config deployment step will be skipped automatically.
set -euo pipefail

# -------------------------------
# CONFIGURATION & PATHS
# -------------------------------
USER_NAME="$(whoami)"
BOOTMENU="/usr/local/bin/bootmenu.sh"
GAMEPAD_PYTHON="/usr/local/bin/gamepad_to_keys.py"
DIAGNOSTIC="/usr/local/bin/diagnostic.sh"
LOG_FILE="$HOME/install_log.txt"

# Directory this script lives in, and the bundled conf folder next to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$SCRIPT_DIR/conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}================================================"
echo -e "  Simple Game Boot INSTALLER v0.0.8"
echo -e "  Multi-Distro Edition"
echo -e "  warning: This script modifies system files and installs packages."
echo -e "  Please review the script before running."
echo -e "  Controller mapping now only needs python-evdev (official repos on"
echo -e "  every supported distro, no AUR required). evdev's own UInput class"
echo -e "  is used to emit key events, so the old python-uinput AUR dependency"
echo -e "  has been removed entirely."
echo -e "  on arch the script will enable multilib repo and install steam and vulkan drivers automatically"
echo -e "  If you are using Gentoo, make sure to set the appropriate USE flags for Vulkan and Steam support."
echo -e "  This script is provided as-is. Use at your own risk."
echo -e "  Supported distros: Arch Linux, Debian/Ubuntu, Gentoo"
echo -e "================================================${NC}"
echo "Includes: Steam (GamepadUI), Vulkan driver selection, Bluetooth, Controller Mapping, RetroArch/AntiMicroX configs, PS4 Bluetooth fix (Arch)"
echo ""

# -------------------------------
# DISTRO DETECTION
# -------------------------------
detect_distro() {
    if command -v pacman >/dev/null 2>&1; then
        echo "arch"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "debian"
    elif command -v emerge >/dev/null 2>&1; then
        echo "gentoo"
    else
        echo "unknown"
    fi
}

DISTRO="$(detect_distro)"

case "$DISTRO" in
    arch)
        echo -e "${GREEN}Detected: Arch Linux${NC}"
        ;;
    debian)
        echo -e "${GREEN}Detected: Debian/Ubuntu${NC}"
        ;;
    gentoo)
        echo -e "${GREEN}Detected: Gentoo Linux${NC}"
        ;;
    *)
        echo -e "${RED}Unsupported distribution. This script supports Arch, Debian/Ubuntu, and Gentoo.${NC}"
        exit 1
        ;;
esac

# -------------------------------
# PACKAGE MANAGER HELPERS
# -------------------------------

pkg_update() {
    case "$DISTRO" in
        arch)    sudo pacman -Syu --noconfirm ;;
        debian)  sudo apt-get update && sudo apt-get upgrade -y ;;
        gentoo)  sudo emerge --sync && sudo emerge -uDN @world ;;
    esac
}

pkg_install() {
    # Usage: pkg_install pkg1 pkg2 ...
    case "$DISTRO" in
        arch)    sudo pacman -S --needed --noconfirm "$@" ;;
        debian)  sudo apt-get install -y "$@" ;;
        gentoo)  sudo emerge --ask=n "$@" ;;
    esac
}

pkg_install_optional() {
    # Like pkg_install but failures are non-fatal
    pkg_install "$@" || echo -e "${YELLOW}Some packages failed to install, continuing...${NC}"
}

# -------------------------------
# DISTRO-SPECIFIC PACKAGE MAPS
# -------------------------------

# Returns distro-appropriate package name(s) for a logical group
pkgs_base() {
    case "$DISTRO" in
        arch)
            # NOTE: retroarch-assets-xmb / retroarch-assets-xmb-sound are NOT official
            # Arch packages (they don't exist in repos or AUR under that name) - dropped.
            # retroarch-assets-ozone ships with RetroArch by default and IS a real package.
            echo "bluez bluez-utils retroarch retroarch-assets-ozone \
                  xorg-server xorg-xinit xorg-xinput xorg-xrandr unzip zip \
                  dialog antimicrox onboard \
                  python-evdev figlet \
                  wget curl neovim tmux rfkill"
            ;;
        debian)
            echo "bluez bluez-utils retroarch \
                  xorg xinit xinput x11-xserver-utils \
                  dialog antimicrox onboard \
                  python3-evdev figlet \
                  wget curl unzip zip neovim tmux rfkill antimicrox"
            ;;
        gentoo)
            echo "net-wireless/bluez \
                  games-emulation/retroarch \
                  x11-base/xorg-server x11-apps/xinit x11-apps/xinput x11-apps/xrandr \
                  dev-util/dialog games-util/antimicrox app-accessibility/onboard \
                  dev-python/evdev app-misc/figlet \
                  net-misc/wget net-misc/curl app-arch/unzip app-editors/neovim app-misc/tmux \
                  sys-apps/rfkill"
            ;;
    esac
}

# Vulkan packages per GPU choice per distro
pkgs_vulkan() {
    local choice="$1"
    case "$DISTRO" in
        arch)
            case "$choice" in
                1) echo "mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon amdvlk lib32-amdvlk vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                2) echo "mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                3) echo "nvidia nvidia-utils lib32-nvidia-utils vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                4) echo "nvidia-open nvidia-utils lib32-nvidia-utils vulkan-icd-loader lib32-vulkan-icd-loader" ;;
                5) echo "mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver vulkan-icd-loader lib32-vulkan-icd-loader" ;;
            esac
            ;;
        debian)
            case "$choice" in
                1) echo "mesa-vulkan-drivers libvulkan1 mesa-utils amdvlk vulkan-tools" ;;
                2) echo "mesa-vulkan-drivers libvulkan1 mesa-utils vulkan-tools" ;;
                3) echo "nvidia-driver nvidia-vulkan-icd libvulkan1 vulkan-tools" ;;
                4) echo "nvidia-open-dkms nvidia-vulkan-icd libvulkan1 vulkan-tools" ;;
                5) echo "mesa-vulkan-drivers intel-media-va-driver libvulkan1 vulkan-tools" ;;
            esac
            ;;
        gentoo)
            case "$choice" in
                1) echo "media-libs/mesa dev-util/vulkan-headers media-libs/vulkan-loader x11-drivers/amdgpu-pro-vulkan" ;;
                2) echo "media-libs/mesa dev-util/vulkan-headers media-libs/vulkan-loader" ;;
                3) echo "x11-drivers/nvidia-drivers media-libs/vulkan-loader dev-util/vulkan-headers" ;;
                4) echo "x11-drivers/nvidia-drivers media-libs/vulkan-loader dev-util/vulkan-headers" ;;
                5) echo "media-libs/mesa dev-util/vulkan-headers media-libs/vulkan-loader" ;;
            esac
            ;;
    esac
}

pkgs_steam() {
    case "$DISTRO" in
        arch)   echo "steam" ;;
        debian) echo "steam-installer" ;;
        gentoo) echo "games-util/steam-launcher" ;;
    esac
}

pkgs_blueman() {
    case "$DISTRO" in
        arch)   echo "blueman" ;;
        debian) echo "blueman" ;;
        gentoo) echo "net-wireless/blueman" ;;
    esac
}

# -------------------------------
# CONFIRM
# -------------------------------
read -r -p "This script modifies system files. Continue? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && exit 1

# -------------------------------
# 1. VULKAN DRIVER SELECTION
# -------------------------------
echo ""
echo -e "${CYAN}================================================"
echo -e "   VULKAN DRIVER SELECTION"
echo -e "================================================${NC}"
echo "Choose your GPU / Vulkan driver:"
echo ""
echo "  1) AMD       - amdvlk + mesa/RADV            (RADV is included via mesa)"
echo "  2) AMD RADV  - mesa only                      (open-source, recommended for most AMD)"
echo "  3) NVIDIA    - proprietary                    (Maxwell/Pascal/Turing/Ampere+)"
echo "  4) NVIDIA (open) - open-source kernel module  (Turing+)"
echo "  5) Intel     - mesa + intel-media-driver      (Iris Xe / Arc)"
echo "  6) Skip      - I'll install Vulkan drivers manually"
echo ""
read -r -p "Enter choice [1-6]: " VULKAN_CHOICE

VULKAN_PKGS=()
case "$VULKAN_CHOICE" in
    1) echo -e "${GREEN}Selected: AMD (amdvlk + mesa/RADV)${NC}"    ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 1)" ;;
    2) echo -e "${GREEN}Selected: AMD RADV (mesa only)${NC}"         ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 2)" ;;
    3) echo -e "${GREEN}Selected: NVIDIA proprietary${NC}"            ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 3)" ;;
    4) echo -e "${GREEN}Selected: NVIDIA open (kernel module)${NC}"   ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 4)" ;;
    5) echo -e "${GREEN}Selected: Intel${NC}"                         ; IFS=' ' read -ra VULKAN_PKGS <<< "$(pkgs_vulkan 5)" ;;
    6) echo -e "${YELLOW}Skipping Vulkan driver installation.${NC}"   ; VULKAN_PKGS=() ;;
    *) echo -e "${RED}Invalid choice, skipping Vulkan.${NC}"          ; VULKAN_PKGS=() ;;
esac

# -------------------------------
# 2. DISTRO-SPECIFIC SETUP
# -------------------------------
echo -e "${YELLOW}Performing distro-specific pre-install setup...${NC}"

case "$DISTRO" in
    arch)
        # Enable multilib (required for Steam 32-bit libs)
        echo -e "${YELLOW}Enabling multilib repository...${NC}"
        if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
            sudo tee -a /etc/pacman.conf >/dev/null <<'MULTILIB'

[multilib]
Include = /etc/pacman.d/mirrorlist
MULTILIB
            echo -e "${GREEN}multilib enabled.${NC}"
        else
            echo -e "${GREEN}multilib already enabled.${NC}"
        fi
        sudo pacman -Syu --noconfirm
        ;;

    debian)
        # Enable 32-bit architecture and non-free repos (needed for Steam / Nvidia)
        echo -e "${YELLOW}Enabling i386 (multiarch) and non-free repos...${NC}"
        sudo dpkg --add-architecture i386
        # Add contrib/non-free if not already present (best-effort)
        if ! grep -qE 'non-free|contrib' /etc/apt/sources.list 2>/dev/null; then
            echo -e "${YELLOW}Note: contrib/non-free may be required for Steam/NVIDIA. Edit /etc/apt/sources.list if packages are missing.${NC}"
        fi
        # Ubuntu: enable universe/multiverse
        if command -v add-apt-repository >/dev/null 2>&1; then
            sudo add-apt-repository -y universe 2>/dev/null || true
            sudo add-apt-repository -y multiverse 2>/dev/null || true
        fi
        sudo apt-get update
        ;;

    gentoo)
        # Sync portage tree
        echo -e "${YELLOW}Syncing Portage tree...${NC}"
        sudo emerge --sync
        # Remind user about USE flags for Vulkan / Steam
        echo -e "${YELLOW}Gentoo note: You may need to set USE flags for Vulkan/Steam support."
        echo -e "Example: echo 'media-libs/mesa vulkan' >> /etc/portage/package.use/sgbu${NC}"
        echo -e "${YELLOW}Also ensure ACCEPT_KEYWORDS contains ~amd64 if needed.${NC}"
        ;;
esac

# -------------------------------
# 3. INSTALL BASE PACKAGES
# -------------------------------
echo -e "${YELLOW}Installing base packages...${NC}"
IFS=' ' read -ra BASE_PKGS <<< "$(pkgs_base)"
pkg_install_optional "${BASE_PKGS[@]}"

# -------------------------------
# 4. INSTALL VULKAN PACKAGES
# -------------------------------
if [ ${#VULKAN_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Installing Vulkan packages: ${VULKAN_PKGS[*]}${NC}"
    pkg_install_optional "${VULKAN_PKGS[@]}"
fi

# -------------------------------
# 5. INSTALL STEAM
# -------------------------------
echo -e "${YELLOW}Installing Steam...${NC}"
IFS=' ' read -ra STEAM_PKGS <<< "$(pkgs_steam)"
pkg_install_optional "${STEAM_PKGS[@]}" || {
    echo -e "${RED}Steam installation failed. Check your repos/USE flags.${NC}"
}

# Debian: some systems need to run steam-installer interactively once
if [ "$DISTRO" = "debian" ]; then
    echo -e "${YELLOW}Note (Debian/Ubuntu): If Steam shows a licence dialog on first run, accept it manually.${NC}"
fi

# -------------------------------
# 6. DEPLOY BUNDLED CONFIG FILES (RetroArch / AntiMicroX)
# -------------------------------
deploy_conf_files() {
    echo -e "${YELLOW}Deploying bundled config files (RetroArch / AntiMicroX)...${NC}"
    echo -e "Looking for conf folder at: ${CONF_DIR}"

    if [ ! -d "$CONF_DIR" ]; then
        echo -e "${YELLOW}!${NC} No 'conf' folder found next to this script."
        echo -e "${YELLOW}!${NC} Make sure you cloned the full repo and are running this script from inside it:"
        echo -e "    git clone https://github.com/stuffbymax/Simple-Game-Boot-Utility.git"
        echo -e "    cd Simple-Game-Boot-Utility"
        echo -e "    ./install-multi.sh"
        echo -e "${YELLOW}Skipping RetroArch/AntiMicroX config deployment.${NC}"
        return
    fi

    # RetroArch config
    if [ -d "$CONF_DIR/retroarch" ]; then
        mkdir -p "$HOME/.config/retroarch"
        if [ -f "$HOME/.config/retroarch/retroarch.cfg" ]; then
            BACKUP="$HOME/.config/retroarch/retroarch.cfg.bak.$(date +%s)"
            cp "$HOME/.config/retroarch/retroarch.cfg" "$BACKUP" 2>/dev/null || true
            echo -e "${YELLOW}!${NC} Existing retroarch.cfg backed up to $BACKUP"
        fi
        cp -rT "$CONF_DIR/retroarch" "$HOME/.config/retroarch"
        echo -e "${GREEN}✓${NC} RetroArch config deployed to ~/.config/retroarch"
    else
        echo -e "${YELLOW}!${NC} No conf/retroarch folder in repo, skipping RetroArch config."
    fi

    # AntiMicroX config/profiles
    if [ -d "$CONF_DIR/antimicrox" ]; then
        mkdir -p "$HOME/.config/antimicrox"
        cp -rT "$CONF_DIR/antimicrox" "$HOME/.config/antimicrox"
        echo -e "${GREEN}✓${NC} AntiMicroX profile(s) deployed to ~/.config/antimicrox"
    else
        echo -e "${YELLOW}!${NC} No conf/antimicrox folder in repo, skipping AntiMicroX config."
    fi
}
deploy_conf_files

# -------------------------------
# 6B. PLYMOUTH BOOT SPLASH (sgbu_logo.png)
# -------------------------------
setup_plymouth_splash() {
    local LOGO="$SCRIPT_DIR/sgbu_logo.png"
    local THEME_DIR="/usr/share/plymouth/themes/sgbu"

    echo -e "${YELLOW}Setting up Plymouth boot splash...${NC}"

    if [ ! -f "$LOGO" ]; then
        echo -e "${YELLOW}!${NC} No sgbu_logo.png found next to this script ($SCRIPT_DIR)."
        echo -e "${YELLOW}!${NC} Skipping Plymouth splash setup. Drop sgbu_logo.png in the repo root and re-run to enable it."
        return
    fi

    # Make sure plymouth itself is installed (not always in pkgs_base on every distro)
    case "$DISTRO" in
        arch)   pkg_install_optional plymouth ;;
        debian) pkg_install_optional plymouth plymouth-themes ;;
        gentoo) pkg_install_optional sys-boot/plymouth ;;
    esac

    if ! command -v plymouth-set-default-theme >/dev/null 2>&1 && [ ! -d /usr/share/plymouth ]; then
        echo -e "${YELLOW}!${NC} Plymouth doesn't appear to be installed correctly, skipping splash setup."
        return
    fi

    sudo mkdir -p "$THEME_DIR"
    sudo cp "$LOGO" "$THEME_DIR/sgbu_logo.png"

    sudo tee "$THEME_DIR/sgbu.plymouth" >/dev/null << 'PLYMOUTH_EOF'
[Plymouth Theme]
Name=SGBU
Description=Simple Game Boot Utility splash screen
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/sgbu
ScriptFile=/usr/share/plymouth/themes/sgbu/sgbu.script
PLYMOUTH_EOF

    sudo tee "$THEME_DIR/sgbu.script" >/dev/null << 'SCRIPT_EOF'
# SGBU Plymouth theme - centers sgbu_logo.png on a black background
# with a simple fade-in and a small pulsing-dot progress indicator.

Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);

logo.image = Image("sgbu_logo.png");
logo.sprite = Sprite(logo.image);
logo.x = Window.GetX() + Window.GetWidth()  / 2 - logo.image.GetWidth()  / 2;
logo.y = Window.GetY() + Window.GetHeight() / 2 - logo.image.GetHeight() / 2;
logo.sprite.SetPosition(logo.x, logo.y, 10000);
logo.opacity = 0;

fun fade_in_callback() {
    if (logo.opacity < 1) {
        logo.opacity += 0.05;
        logo.sprite.SetOpacity(logo.opacity);
    }
}
Plymouth.SetRefreshFunction(fade_in_callback);

# Small pulsing dots under the logo to show activity while packages load / boot proceeds
dot_count = 3;
dots = [];
for (i = 0; i < dot_count; i++) {
    dots[i].sprite = Sprite();
    dots[i].sprite.SetPosition(logo.x + logo.image.GetWidth() / 2 - (dot_count * 20) / 2 + i * 20,
                                logo.y + logo.image.GetHeight() + 30, 10001);
}

progress = 0;
fun pulse_callback() {
    progress++;
    for (i = 0; i < dot_count; i++) {
        active = (Math.Int(progress / 10) % dot_count == i);
        if (active) {
            dots[i].sprite.SetImage(Image.Text("●", 1, 1, 1));
        } else {
            dots[i].sprite.SetImage(Image.Text("●", 0.4, 0.4, 0.4));
        }
    }
}
Plymouth.SetRefreshFunction(pulse_callback);

fun display_normal_callback() {
    logo.sprite.SetOpacity(1);
}
Plymouth.SetDisplayNormalFunction(display_normal_callback);
SCRIPT_EOF

    # Point the default theme at ours and rebuild the initramfs so the
    # splash actually shows up at next boot.
    case "$DISTRO" in
        arch)
            if command -v plymouth-set-default-theme >/dev/null 2>&1; then
                sudo plymouth-set-default-theme -R sgbu 2>/dev/null || {
                    sudo plymouth-set-default-theme sgbu 2>/dev/null || true
                    command -v mkinitcpio >/dev/null && sudo mkinitcpio -P 2>/dev/null || true
                }
            fi
            if [ -f /etc/mkinitcpio.conf ] && ! grep -q '\bplymouth\b' /etc/mkinitcpio.conf; then
                sudo cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$(date +%s)"
                sudo sed -i 's/\(HOOKS=.*base udev\)/\1 plymouth/' /etc/mkinitcpio.conf
                sudo mkinitcpio -P 2>/dev/null || true
            fi
            ;;
        debian)
            if command -v plymouth-set-default-theme >/dev/null 2>&1; then
                sudo plymouth-set-default-theme -R sgbu 2>/dev/null || true
            else
                sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
                    default.plymouth "$THEME_DIR/sgbu.plymouth" 100 2>/dev/null || true
                sudo update-alternatives --set default.plymouth "$THEME_DIR/sgbu.plymouth" 2>/dev/null || true
            fi
            command -v update-initramfs >/dev/null && sudo update-initramfs -u 2>/dev/null || true
            ;;
        gentoo)
            echo -e "${YELLOW}Gentoo: plymouth theme files installed to $THEME_DIR.${NC}"
            echo -e "${YELLOW}Set it with: plymouth-set-default-theme -R sgbu (needs an initramfs, e.g. dracut/genkernel).${NC}"
            ;;
    esac

    # Make sure the kernel actually boots with a splash (adds 'splash quiet'
    # to GRUB if present; best-effort, backs up first, never fatal).
    if [ -f /etc/default/grub ]; then
        sudo cp /etc/default/grub "/etc/default/grub.bak.$(date +%s)"
        if ! grep -q 'splash' /etc/default/grub; then
            sudo sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 splash quiet"/' /etc/default/grub
        fi
        if command -v update-grub >/dev/null 2>&1; then
            sudo update-grub 2>/dev/null || true
        elif command -v grub-mkconfig >/dev/null 2>&1; then
            sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
        fi
    elif [ -d /boot/loader/entries ]; then
        for entry in /boot/loader/entries/*.conf; do
            [ -f "$entry" ] || continue
            grep -q 'splash' "$entry" || {
                sudo cp "$entry" "${entry}.bak.$(date +%s)"
                sudo sed -i '/^options /s/$/ splash quiet/' "$entry"
            }
        done
    else
        echo -e "${YELLOW}!${NC} Couldn't detect GRUB or systemd-boot automatically."
        echo -e "${YELLOW}!${NC} Add 'splash quiet' to your kernel command line manually to see the splash at boot."
    fi

    echo -e "${GREEN}✓${NC} Plymouth splash 'sgbu' installed using $LOGO"
}
setup_plymouth_splash

# -------------------------------
# 7. UINPUT & PERMISSIONS
# -------------------------------
echo -e "${YELLOW}Configuring uinput permissions...${NC}"
sudo modprobe uinput || true

if [ -d /etc/modules-load.d ]; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
elif [ -d /etc/conf.d ]; then
    # Gentoo OpenRC
    echo "uinput" | sudo tee /etc/conf.d/modules >/dev/null
fi

sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF

getent group bluetooth >/dev/null && sudo usermod -aG bluetooth "$USER_NAME" || true
sudo usermod -aG input "$USER_NAME" || true
sudo usermod -aG video "$USER_NAME" || true

sudo udevadm control --reload-rules || true
sudo udevadm trigger || true

# -------------------------------
# 8. CONTROLLER MAPPER (Python)
# -------------------------------
echo -e "${YELLOW}Creating Controller Mapper...${NC}"
sudo tee "$GAMEPAD_PYTHON" >/dev/null << 'EOF'
#!/usr/bin/env python3
'''
created BY marinP/stuffbymax
description: Gamepad to keyboard mapper - supports PS3, PS4, PS5, Xbox 360, Xbox One, Xbox Series X/S
             Renamed from ps3_to_keys.py -> gamepad_to_keys.py (it maps every pad, not just PS3).
License: MIT
version: 0.0.5

NOTE: This no longer depends on the separate "uinput" python package (AUR-only
on Arch). python-evdev ships its own device-emission class, evdev.UInput,
which is all we need to synthesize key events. Only python-evdev is required
now, and it's in the official repos on every supported distro.
'''

import evdev
from evdev import UInput, ecodes as e
import sys
import time

KNOWN_CONTROLLERS = [
    "sony", "playstation", "dualshock", "dualsense", "sixaxis",
    "ps3", "ps4", "ps5", "wireless controller",
    "xbox", "microsoft", "x-box", "xinput", "360 pad",
    "xbox 360", "xbox one", "xbox series",
    "gamepad", "joystick",
]

EXCLUDE_NAMES = [
    "touchpad", "motion", "accelerometer", "gyro",
    "sensor", "rumble", "battery",
]

BTN_MAP_PS3 = {
    304: e.KEY_ENTER, 305: e.KEY_ESC, 307: e.KEY_SPACE, 308: e.KEY_BACKSPACE,
    544: e.KEY_UP, 545: e.KEY_DOWN, 546: e.KEY_LEFT, 547: e.KEY_RIGHT,
    310: e.KEY_TAB, 311: e.KEY_F1, 312: e.KEY_F2, 313: e.KEY_F3,
    314: e.KEY_F4, 315: e.KEY_F5, 316: e.KEY_F6, 317: e.KEY_F7, 318: e.KEY_F8,
}

BTN_MAP_PS4 = {
    304: e.KEY_ENTER, 305: e.KEY_ESC, 307: e.KEY_SPACE, 308: e.KEY_BACKSPACE,
    310: e.KEY_TAB, 311: e.KEY_F1, 312: e.KEY_F2, 313: e.KEY_F3,
    314: e.KEY_F4, 315: e.KEY_F5, 316: e.KEY_F6, 317: e.KEY_F7,
    318: e.KEY_F8, 319: e.KEY_F9,
}

BTN_MAP_PS5 = {
    304: e.KEY_ENTER, 305: e.KEY_ESC, 307: e.KEY_SPACE, 308: e.KEY_BACKSPACE,
    310: e.KEY_TAB, 311: e.KEY_F1, 312: e.KEY_F2, 313: e.KEY_F3,
    314: e.KEY_F4, 315: e.KEY_F5, 316: e.KEY_F6, 317: e.KEY_F7,
    318: e.KEY_F8, 319: e.KEY_F9, 320: e.KEY_F10,
}

BTN_MAP_XBOX360 = {
    304: e.KEY_ENTER, 305: e.KEY_ESC, 307: e.KEY_SPACE, 308: e.KEY_BACKSPACE,
    310: e.KEY_TAB, 311: e.KEY_F1,
    314: e.KEY_F4, 315: e.KEY_F5, 316: e.KEY_F6, 317: e.KEY_F7, 318: e.KEY_F8,
}

BTN_MAP_XBOXONE = {
    304: e.KEY_ENTER, 305: e.KEY_ESC, 307: e.KEY_SPACE, 308: e.KEY_BACKSPACE,
    310: e.KEY_TAB, 311: e.KEY_F1,
    314: e.KEY_F4, 315: e.KEY_F5, 316: e.KEY_F6, 317: e.KEY_F7,
    318: e.KEY_F8, 706: e.KEY_F9,
}

BTN_MAP_XBOXSERIES = {
    304: e.KEY_ENTER, 305: e.KEY_ESC, 307: e.KEY_SPACE, 308: e.KEY_BACKSPACE,
    310: e.KEY_TAB, 311: e.KEY_F1,
    314: e.KEY_F4, 315: e.KEY_F5, 316: e.KEY_F6, 317: e.KEY_F7,
    318: e.KEY_F8, 706: e.KEY_F9, 167: e.KEY_F10,
}

# Default axis deadzone; can be overridden per-device by the stick-drift
# calibration tool (writes /etc/sgbu/<device-name>.deadzone as a plain int).
DEFAULT_AXIS_THRESHOLD = 16000
CALIBRATION_DIR = "/etc/sgbu"

def load_deadzone(device_name):
    import os, re
    safe = re.sub(r'[^a-zA-Z0-9_-]', '_', device_name)
    path = os.path.join(CALIBRATION_DIR, f"{safe}.deadzone")
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return DEFAULT_AXIS_THRESHOLD

def find_controller():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        name_lower = device.name.lower()
        if any(k in name_lower for k in KNOWN_CONTROLLERS):
            if any(ex in name_lower for ex in EXCLUDE_NAMES):
                print(f"[SGBU] Skipping sub-device: {device.name}")
                continue
            caps = device.capabilities()
            if evdev.ecodes.EV_KEY in caps:
                return device
    for device in devices:
        name_lower = device.name.lower()
        if any(ex in name_lower for ex in EXCLUDE_NAMES):
            continue
        caps = device.capabilities()
        if evdev.ecodes.EV_KEY in caps and evdev.ecodes.EV_ABS in caps:
            keys = caps[evdev.ecodes.EV_KEY]
            if len(keys) >= 8:
                return device
    return None

def detect_controller_type(device):
    name_lower = device.name.lower()
    if "dualsense" in name_lower or "ps5" in name_lower:
        print("[SGBU] Detected: PS5 DualSense")
        return "ps5", BTN_MAP_PS5
    elif "dualshock 4" in name_lower or "ps4" in name_lower or "wireless controller" in name_lower:
        print("[SGBU] Detected: PS4 DualShock 4")
        return "ps4", BTN_MAP_PS4
    elif "ps3" in name_lower or "dualshock 3" in name_lower or "sixaxis" in name_lower:
        print("[SGBU] Detected: PS3 DualShock 3 / Sixaxis")
        return "ps3", BTN_MAP_PS3
    elif "series" in name_lower or "xbox series" in name_lower:
        print("[SGBU] Detected: Xbox Series X/S")
        return "xboxseries", BTN_MAP_XBOXSERIES
    elif "xbox one" in name_lower or "xbone" in name_lower:
        print("[SGBU] Detected: Xbox One")
        return "xboxone", BTN_MAP_XBOXONE
    elif "xbox 360" in name_lower or "360 pad" in name_lower or "xinput" in name_lower:
        print("[SGBU] Detected: Xbox 360")
        return "xbox360", BTN_MAP_XBOX360
    elif "xbox" in name_lower or "microsoft" in name_lower or "x-box" in name_lower:
        print(f"[SGBU] Detected: Xbox (generic) — using Xbox One map")
        return "xboxone", BTN_MAP_XBOXONE
    else:
        print(f"[SGBU] Unknown controller '{device.name}', using PS4 button map")
        return "ps4", BTN_MAP_PS4

stick_state = {"left_x": 0, "left_y": 0}

def handle_analog(ui, code, value, threshold):
    if code == evdev.ecodes.ABS_X:
        stick_state["left_x"] = value
    elif code == evdev.ecodes.ABS_Y:
        stick_state["left_y"] = value
    else:
        return
    lx = stick_state["left_x"]
    ly = stick_state["left_y"]
    if lx < -threshold:
        ui.write(e.EV_KEY, e.KEY_LEFT, 1); ui.write(e.EV_KEY, e.KEY_LEFT, 0); ui.syn()
    elif lx > threshold:
        ui.write(e.EV_KEY, e.KEY_RIGHT, 1); ui.write(e.EV_KEY, e.KEY_RIGHT, 0); ui.syn()
    if ly < -threshold:
        ui.write(e.EV_KEY, e.KEY_UP, 1); ui.write(e.EV_KEY, e.KEY_UP, 0); ui.syn()
    elif ly > threshold:
        ui.write(e.EV_KEY, e.KEY_DOWN, 1); ui.write(e.EV_KEY, e.KEY_DOWN, 0); ui.syn()

def handle_hat(ui, code, value):
    if code == evdev.ecodes.ABS_HAT0Y:
        if value == -1:
            ui.write(e.EV_KEY, e.KEY_UP, 1); ui.write(e.EV_KEY, e.KEY_UP, 0); ui.syn()
        elif value == 1:
            ui.write(e.EV_KEY, e.KEY_DOWN, 1); ui.write(e.EV_KEY, e.KEY_DOWN, 0); ui.syn()
    elif code == evdev.ecodes.ABS_HAT0X:
        if value == -1:
            ui.write(e.EV_KEY, e.KEY_LEFT, 1); ui.write(e.EV_KEY, e.KEY_LEFT, 0); ui.syn()
        elif value == 1:
            ui.write(e.EV_KEY, e.KEY_RIGHT, 1); ui.write(e.EV_KEY, e.KEY_RIGHT, 0); ui.syn()

def main():
    print("[SGBU] gamepad_to_keys.py v0.0.5 starting...")
    print("[SGBU] Supports: PS3 / PS4 / PS5 / Xbox 360 / Xbox One / Xbox Series X|S")
    device = None
    for attempt in range(10):
        device = find_controller()
        if device:
            break
        print(f"[SGBU] No controller found, retrying ({attempt+1}/10)...")
        time.sleep(2)
    if not device:
        print("[SGBU] No controller found after retries. Exiting.")
        sys.exit(1)
    print(f"[SGBU] Using: {device.path} — {device.name}")
    ctrl_type, btn_map = detect_controller_type(device)
    threshold = load_deadzone(device.name)
    print(f"[SGBU] Analog deadzone: {threshold} (run stick-calibrate.py to tune)")

    # evdev's own UInput class replaces the old separate "uinput" package.
    capabilities = {
        e.EV_KEY: [
            e.KEY_ENTER, e.KEY_ESC, e.KEY_BACKSPACE, e.KEY_SPACE,
            e.KEY_UP, e.KEY_DOWN, e.KEY_LEFT, e.KEY_RIGHT,
            e.KEY_TAB,
            e.KEY_F1, e.KEY_F2, e.KEY_F3, e.KEY_F4,
            e.KEY_F5, e.KEY_F6, e.KEY_F7, e.KEY_F8,
            e.KEY_F9, e.KEY_F10,
        ]
    }
    try:
        ui = UInput(capabilities, name="sgbu-gamepad-to-keys")
    except Exception as ex:
        print(f"[SGBU] Failed to create uinput device: {ex}")
        print("[SGBU] Make sure the uinput kernel module is loaded: sudo modprobe uinput")
        sys.exit(1)

    try:
        device.grab()
        print(f"[SGBU] Controller grabbed ({ctrl_type} mode). Press Ctrl+C to stop.")
        for event in device.read_loop():
            if event.type == evdev.ecodes.EV_KEY:
                key = btn_map.get(event.code)
                if key is not None:
                    ui.write(e.EV_KEY, key, event.value)
                    ui.syn()
            elif event.type == evdev.ecodes.EV_ABS:
                if event.code in (evdev.ecodes.ABS_HAT0X, evdev.ecodes.ABS_HAT0Y):
                    handle_hat(ui, event.code, event.value)
                elif event.code in (evdev.ecodes.ABS_X, evdev.ecodes.ABS_Y):
                    handle_analog(ui, event.code, event.value, threshold)
    except KeyboardInterrupt:
        print("\n[SGBU] Mapper stopped.")
    except Exception as ex:
        print(f"[SGBU] Error: {ex}")
    finally:
        try:
            device.ungrab()
        except Exception:
            pass
        ui.close()

if __name__ == "__main__":
    main()
EOF
sudo chmod +x "$GAMEPAD_PYTHON"

# -------------------------------
# 8B. STICK DRIFT CALIBRATION TOOL
# -------------------------------
echo -e "${YELLOW}Creating Stick Drift Calibration Tool...${NC}"
sudo mkdir -p /etc/sgbu
STICK_CALIBRATE="/usr/local/bin/stick-calibrate.py"
sudo tee "$STICK_CALIBRATE" >/dev/null << 'EOF'
#!/usr/bin/env python3
'''
created BY marinP/stuffbymax
description: Samples a gamepad's analog stick at rest, works out how far it
             drifts from center, and writes a per-device deadzone that
             gamepad_to_keys.py picks up automatically. Also offers to patch
             the matching AntiMicroX profile's <deadZone> values so both
             tools agree on the same dead zone.
License: MIT
version: 0.0.1
'''

import evdev
import glob
import os
import re
import sys
import time

CALIBRATION_DIR = "/etc/sgbu"
SAMPLE_SECONDS = 4
SAFETY_MARGIN = 1.5   # multiply observed drift by this to leave headroom
MIN_DEADZONE = 2000
MAX_DEADZONE = 20000

EXCLUDE_NAMES = ["touchpad", "motion", "accelerometer", "gyro", "sensor", "rumble", "battery"]


def find_gamepads():
    pads = []
    for path in evdev.list_devices():
        dev = evdev.InputDevice(path)
        name_lower = dev.name.lower()
        if any(ex in name_lower for ex in EXCLUDE_NAMES):
            continue
        caps = dev.capabilities()
        if evdev.ecodes.EV_ABS in caps:
            abs_codes = [c for c, _ in caps[evdev.ecodes.EV_ABS]]
            if evdev.ecodes.ABS_X in abs_codes and evdev.ecodes.ABS_Y in abs_codes:
                pads.append(dev)
    return pads


def sample_axis_drift(dev, seconds=SAMPLE_SECONDS):
    print(f"[Calibrate] Sampling '{dev.name}' for {seconds}s.")
    print("[Calibrate] IMPORTANT: let go of the sticks now, don't touch them.")
    time.sleep(1.5)
    max_dev = {evdev.ecodes.ABS_X: 0, evdev.ecodes.ABS_Y: 0}
    absinfo = dict(dev.capabilities().get(evdev.ecodes.EV_ABS, []))
    centers = {}
    for code in (evdev.ecodes.ABS_X, evdev.ecodes.ABS_Y):
        info = absinfo.get(code)
        centers[code] = (info.min + info.max) // 2 if info else 0

    end_time = time.time() + seconds
    dev.grab()
    try:
        for event in dev.read_loop():
            if event.type == evdev.ecodes.EV_ABS and event.code in max_dev:
                deviation = abs(event.value - centers[event.code])
                if deviation > max_dev[event.code]:
                    max_dev[event.code] = deviation
            if time.time() > end_time:
                break
    finally:
        try:
            dev.ungrab()
        except Exception:
            pass

    observed = max(max_dev.values())
    print(f"[Calibrate] Observed max drift: {observed} raw units")
    return observed


def suggested_deadzone(observed):
    value = int(observed * SAFETY_MARGIN)
    return max(MIN_DEADZONE, min(MAX_DEADZONE, value))


def write_deadzone(device_name, deadzone):
    os.makedirs(CALIBRATION_DIR, exist_ok=True)
    safe = re.sub(r'[^a-zA-Z0-9_-]', '_', device_name)
    path = os.path.join(CALIBRATION_DIR, f"{safe}.deadzone")
    with open(path, "w") as f:
        f.write(str(deadzone))
    print(f"[Calibrate] Wrote {path} = {deadzone} (used by gamepad_to_keys.py)")
    return path


def patch_antimicrox_profiles(deadzone):
    # AntiMicroX raw deadzone range is roughly 0-32767, same order of
    # magnitude as evdev's, so we reuse the value directly.
    home = os.path.expanduser("~")
    # stick-calibrate.py normally runs via sudo from the boot menu; fall back
    # to the invoking user's home if SUDO_USER is set so we patch the right profile.
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        home = os.path.expanduser(f"~{sudo_user}")

    profiles = glob.glob(os.path.join(home, ".config", "antimicrox", "*.amgp"))
    profiles += glob.glob(os.path.join(home, ".config", "antimicrox", "*.gamecontroller.amgp"))
    if not profiles:
        print("[Calibrate] No AntiMicroX profiles found, skipping profile patch.")
        return

    for profile in profiles:
        answer = input(f"[Calibrate] Patch deadZone values in '{profile}'? [y/N]: ").strip().lower()
        if answer != "y":
            continue
        backup = f"{profile}.bak.{int(time.time())}"
        with open(profile, "r") as f:
            content = f.read()
        with open(backup, "w") as f:
            f.write(content)
        new_content = re.sub(r"<deadZone>\d+</deadZone>", f"<deadZone>{deadzone}</deadZone>", content)
        with open(profile, "w") as f:
            f.write(new_content)
        print(f"[Calibrate] Patched {profile} (backup saved to {backup})")


def main():
    pads = find_gamepads()
    if not pads:
        print("[Calibrate] No gamepad with analog sticks found.")
        sys.exit(1)

    if len(pads) == 1:
        dev = pads[0]
    else:
        print("[Calibrate] Multiple gamepads found:")
        for i, p in enumerate(pads):
            print(f"  {i+1}) {p.name} ({p.path})")
        choice = input("Select controller number: ").strip()
        try:
            dev = pads[int(choice) - 1]
        except (ValueError, IndexError):
            print("[Calibrate] Invalid selection.")
            sys.exit(1)

    observed = sample_axis_drift(dev)
    deadzone = suggested_deadzone(observed)
    print(f"[Calibrate] Suggested deadzone: {deadzone}")
    write_deadzone(dev.name, deadzone)
    patch_antimicrox_profiles(deadzone)
    print("[Calibrate] Done. Restart the gamepad mapper / AntiMicroX for changes to take effect.")


if __name__ == "__main__":
    main()
EOF
sudo chmod +x "$STICK_CALIBRATE"

# -------------------------------
# 9. BOOT MENU
# -------------------------------
echo -e "${YELLOW}Creating Boot Menu...${NC}"
sudo tee "$BOOTMENU" >/dev/null << 'BOOTMENU_EOF'
#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DIALOG_TOOL="dialog"
command -v dialog >/dev/null || DIALOG_TOOL="whiptail"
MAPPER="/usr/local/bin/gamepad_to_keys.py"
CALIBRATE="/usr/local/bin/stick-calibrate.py"
SPLASH_FILE="/etc/sgbu/splash.txt"

# -------------------------------
# SPLASH SCREEN
# -------------------------------
show_splash() {
    clear
    if [ -f "$SPLASH_FILE" ]; then
        cat "$SPLASH_FILE"
    elif command -v figlet >/dev/null; then
        figlet -f slant "SGBU" 2>/dev/null || echo "SGBU"
    else
        echo "============================"
        echo "   Simple Game Boot Utility "
        echo "============================"
    fi
    echo -e "${CYAN}Simple Game Boot Utility${NC}"
    sleep 1
}

detect_sessions() {
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2)
        exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2)
        [[ -n "$name" && -n "$exec" ]] && echo "$name|$exec"
    done
}

detect_steam() {
    for steam_path in "$HOME/.steam/steam/steam.sh" "/usr/bin/steam" "/usr/games/steam"; do
        [ -x "$steam_path" ] && echo "$steam_path" && return 0
    done
    return 1
}

get_system_info() {
    # 1. Memory Usage
    local mem
    mem=$(free -h --si 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}' | sed 's/i//g')

    # 2. CPU Model (cleaned of extra spaces and trademarks)
    local cpu
    cpu=$(awk -F: '/^model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^[ \t]*//;s/(R)//g;s/(TM)//g;s/  */ /g')
    # Shorten CPU name if it's too long
    cpu=$(echo "$cpu" | cut -c 1-20)

    # 3. CPU Temperature (tries sensors, falls back to sysfs)
    local temp="N/A"
    if command -v sensors >/dev/null; then
        temp=$(sensors 2>/dev/null | awk '/(Package id 0|Core 0|Tctl|temp1):/ {print $2; exit}' | tr -d '+')
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp="$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))°C"
    fi

    # 4. GPU Info (briefly identifies the driver/chip)
    local gpu
    gpu=$(lspci | grep -i 'vga\|display\|3d' | head -n1 | awk -F': ' '{print $2}' | awk '{print $1,$2}')

    # 5. IP Address (Local)
    local ip
    ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
    [ -z "$ip" ] && ip="Offline"

    # 6. Storage Usage (Root partition)
    local disk
    disk=$(df -h / | awk 'NR==2 {print $5}')

    # 7. Battery (Optional - checks for BAT0 or BAT1)
    local bat_str=""
    if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
        local bat_path="/sys/class/power_supply/BAT0"
        [ ! -d "$bat_path" ] && bat_path="/sys/class/power_supply/BAT1"
        local cap=$(cat "$bat_path/capacity" 2>/dev/null)
        local stat=$(cat "$bat_path/status" 2>/dev/null)
        # Simplify status (Charging -> CHG, Discharging -> DIS)
        [ "$stat" == "Charging" ] && stat="+" || stat="-"
        bat_str=" | Bat: $cap% [$stat]"
    fi

    # Return a single line for the Dialog Backtitle
    echo "CPU: $cpu ($temp) | Mem: $mem | Disk: $disk | IP: $ip$bat_str"
}

launch_steam_xinitrc() {
    local steam_flag="$1"

    pkill -f gamepad_to_keys.py || true

    mkdir -p "$HOME/.config/openbox"
    cat > "$HOME/.config/openbox/rc.xml" <<'OBCONF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc"
                xmlns:xi="http://www.w3.org/2001/XInclude">

  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>

  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>

  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names><name>Steam</name></names>
    <popupTime>0</popupTime>
  </desktops>

  <theme>
    <keepBorder>no</keepBorder>
  </theme>

  <applications>
    <!-- Force Steam GamepadUI fullscreen, no borders, no titlebar -->
    <application class="steam" name="steam">
      <decor>no</decor>
      <fullscreen>yes</fullscreen>
      <maximized>yes</maximized>
      <layer>normal</layer>
      <focus>yes</focus>
    </application>
    <!-- Catch any other Steam windows (e.g. updates, popups) -->
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>

  <!-- Disable right-click desktop menu -->
  <menu>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
    <applicationIcons>no</applicationIcons>
    <manageDesktops>no</manageDesktops>
  </menu>

</openbox_config>
OBCONF

    cat > "$HOME/.xinitrc" <<XINITRC
#!/bin/sh

# Disable screen blanking and power saving
xset s off
xset -dpms
xset s noblank

# Hide the cursor after 1 second of inactivity
command -v unclutter >/dev/null && unclutter -idle 1 -root &

# Environment
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export STEAM_FORCE_DESKTOPUI_SCALING=1
export STEAM_GAMEPADUI=1

# Force correct resolution
if command -v xrandr >/dev/null; then
    PRIMARY=\$(xrandr --query | awk '/ connected primary/ {print \$1; exit}')
    [ -z "\$PRIMARY" ] && PRIMARY=\$(xrandr --query | awk '/ connected/ {print \$1; exit}')
    if [ -n "\$PRIMARY" ]; then
        MODE=\$(xrandr | awk '/\*/ {print \$1; exit}')
        [ -n "\$MODE" ] && xrandr --output "\$PRIMARY" --mode "\$MODE"
    fi
fi

# Start Openbox first, wait for it to be ready
openbox &
OB_PID=\$!
sleep 1

# Launch Steam under Openbox
exec steam ${steam_flag}
XINITRC

    chmod +x "$HOME/.xinitrc"
    startx -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/steam.log"

    # Restart mapper after Steam exits
    [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
}

show_splash

# Start mapper
MAPPER_PID=""
if [ -x "$MAPPER" ]; then
    $MAPPER &
    MAPPER_PID=$!
    trap 'kill $MAPPER_PID 2>/dev/null' EXIT
fi

while true; do
    ITEMS=()
    ACTIONS=()
    i=1

    if command -v retroarch >/dev/null; then
        ITEMS+=($i "RetroArch")
        ACTIONS+=("retroarch")
        ((i++))
    fi

    STEAM=$(detect_steam || true)
    if [ -n "$STEAM" ]; then
        ITEMS+=($i "Steam (GamepadUI)")
        ACTIONS+=("steam_gamepadui:$STEAM")
        ((i++))

        ITEMS+=($i "Steam (Normal Mode)")
        ACTIONS+=("steam_normal:$STEAM")
        ((i++))
    fi

    while IFS='|' read -r name exec_cmd; do
        ITEMS+=($i "Desktop: $name")
        ACTIONS+=("session:$exec_cmd")
        ((i++))
    done < <(detect_sessions)

    ITEMS+=($i "Bluetooth Manager")
    ACTIONS+=("bluetooth")
    ((i++))

    ITEMS+=($i "Calibrate Stick Drift")
    ACTIONS+=("calibrate")
    ((i++))

    ITEMS+=($i "Terminal")
    ACTIONS+=("shell")
    ((i++))

    ITEMS+=($i "Run Diagnostics")
    ACTIONS+=("diagnostic")
    ((i++))

    ITEMS+=($i "Reboot")
    ACTIONS+=("reboot")
    ((i++))

    ITEMS+=($i "Shutdown")
    ACTIONS+=("shutdown")

    SYSINFO=$(get_system_info)
    CHOICE=$($DIALOG_TOOL --backtitle "SGBU | v0.0.8-multi | $SYSINFO" \
        --menu "Select Action" 22 70 14 "${ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 0

    ACTION="${ACTIONS[$((CHOICE-1))]}"

    case "$ACTION" in
        steam_gamepadui:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            STEAM_BIN="${ACTION#steam_gamepadui:}"
            launch_steam_xinitrc "-gamepadui" "-fullscreen" "$STEAM_BIN"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

        steam_normal:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            STEAM_BIN="${ACTION#steam_normal:}"
            launch_steam_xinitrc "" "-fullscreen" "$STEAM_BIN"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

        retroarch)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            # Use the bundled/deployed retroarch.cfg if present, otherwise fall back to defaults
            if [ -f "$HOME/.config/retroarch/retroarch.cfg" ]; then
                retroarch -f --config "$HOME/.config/retroarch/retroarch.cfg" 2>&1 | tee -a "$HOME/retroarch.log"
            else
                retroarch -f 2>&1 | tee -a "$HOME/retroarch.log"
            fi
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

bluetooth)
    [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null

    if command -v blueman-manager >/dev/null; then
        # Launch Openbox + blueman if no display is running
        if [ -z "${DISPLAY:-}" ]; then
            cat > "$HOME/.xinitrc.bt" <<'BTRC'
#!/bin/sh
xset s off
xset -dpms
openbox &
sleep 0.5
blueman-manager
# Return to menu when window is closed
BTRC
            chmod +x "$HOME/.xinitrc.bt"
            xinit "$HOME/.xinitrc.bt" -- :0 vt"${XDG_VTNR:-1}" 2>&1 | tee -a "$HOME/blueman.log"
        else
            # Display already running (e.g. called from within X session)
            blueman-manager &
            wait $!
        fi
    else
        echo -e "${RED}blueman not found. Install it via your package manager.${NC}"
        read -rp "Press Enter..."
    fi

    [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
    ;;

        calibrate)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            clear
            if [ -x "$CALIBRATE" ]; then
                sudo "$CALIBRATE"
            else
                echo -e "${RED}stick-calibrate.py not found or not executable.${NC}"
            fi
            read -rp "Press Enter to return to the menu..."
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

        session:*)
            [ -n "$MAPPER_PID" ] && kill $MAPPER_PID 2>/dev/null
            SESSION_EXEC="${ACTION#session:}"
            # Pick up a bundled AntiMicroX profile if one was deployed by the installer
            ANTIMICROX_PROFILE=$(find "$HOME/.config/antimicrox" -maxdepth 1 -type f \( -iname "*.amgp" -o -iname "*.gamecontroller.amgp" \) 2>/dev/null | head -n1)
            cat > "$HOME/.xinitrc" << XINITRC
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=\$HOME/.Xauthority
if command -v antimicrox >/dev/null; then
    if [ -n "$ANTIMICROX_PROFILE" ]; then
        antimicrox --profile "$ANTIMICROX_PROFILE" --hidden &
    else
        antimicrox --hidden &
    fi
fi
command -v onboard >/dev/null && onboard &
exec $SESSION_EXEC
XINITRC
            chmod +x "$HOME/.xinitrc"
            startx 2>&1 | tee -a "$HOME/xsession.log"
            [ -x "$MAPPER" ] && { $MAPPER & MAPPER_PID=$!; }
            ;;

        shell)
            clear
            echo -e "${CYAN}Entering shell. Type 'exit' to return.${NC}"
            bash
            ;;

        diagnostic)
            clear
            [ -x /usr/local/bin/diagnostic.sh ] && /usr/local/bin/diagnostic.sh || echo "Diagnostic not found"
            read -rp "Press Enter to continue..."
            ;;

        reboot)  sudo reboot ;;
        shutdown) sudo shutdown now ;;
    esac
done
BOOTMENU_EOF
sudo chmod +x "$BOOTMENU"

# -------------------------------
# 10. DIAGNOSTIC SCRIPT
# -------------------------------
echo -e "${YELLOW}Creating Diagnostic Script...${NC}"
sudo tee "$DIAGNOSTIC" >/dev/null << 'EOF'
#!/usr/bin/env bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect distro for hints
if command -v pacman >/dev/null 2>&1; then
    DISTRO="arch"
    PKG_HINT="pacman -S vulkan-tools"
elif command -v apt-get >/dev/null 2>&1; then
    DISTRO="debian"
    PKG_HINT="apt-get install vulkan-tools"
elif command -v emerge >/dev/null 2>&1; then
    DISTRO="gentoo"
    PKG_HINT="emerge dev-util/vulkan-tools"
else
    DISTRO="unknown"
    PKG_HINT="your package manager"
fi

echo -e "${CYAN}=============================="
echo -e "  SGBU SYSTEM DIAGNOSTICS"
echo -e "  Distro: $DISTRO"
echo -e "==============================${NC}"

echo -e "\n${CYAN}[Vulkan / GPU]${NC}"
if command -v vulkaninfo >/dev/null; then
    GPU=$(vulkaninfo 2>/dev/null | grep 'deviceName' | head -n1 | awk -F= '{print $2}' | xargs)
    echo -e "${GREEN}✓${NC} Vulkan device: ${GPU:-unknown}"
else
    echo -e "${YELLOW}!${NC} vulkan-tools not installed (run: $PKG_HINT)"
fi
if command -v glxinfo >/dev/null; then
    RENDERER=$(glxinfo 2>/dev/null | grep 'OpenGL renderer' | awk -F: '{print $2}' | xargs)
    echo -e "${GREEN}✓${NC} OpenGL renderer: ${RENDERER:-unknown}"
fi

echo -e "\n${CYAN}[Steam]${NC}"
if command -v steam >/dev/null || [ -x "$HOME/.steam/steam/steam.sh" ]; then
    echo -e "${GREEN}✓${NC} Steam found"
    STEAM_VER=$(steam --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1 || echo "unknown")
    echo -e "${GREEN}✓${NC} Steam version: $STEAM_VER"
else
    echo -e "${RED}✗${NC} Steam not found"
fi

echo -e "\n${CYAN}[Bluetooth]${NC}"
if command -v bluetoothctl >/dev/null; then
    echo -e "${GREEN}✓${NC} BlueZ installed"
    if systemctl is-active --quiet bluetooth 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Bluetooth service running"
    elif rc-service bluetooth status >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Bluetooth service running (OpenRC)"
    else
        echo -e "${RED}✗${NC} Bluetooth service NOT running"
    fi
else
    echo -e "${RED}✗${NC} BlueZ not found"
fi

echo -e "\n${CYAN}[X Server]${NC}"
command -v Xorg >/dev/null && echo -e "${GREEN}✓${NC} Xorg installed" || echo -e "${RED}✗${NC} Xorg missing"

echo -e "\n${CYAN}[RetroArch]${NC}"
command -v retroarch >/dev/null && echo -e "${GREEN}✓${NC} RetroArch installed" || echo -e "${RED}✗${NC} RetroArch missing"
if [ -f "$HOME/.config/retroarch/retroarch.cfg" ]; then
    echo -e "${GREEN}✓${NC} retroarch.cfg present at ~/.config/retroarch/retroarch.cfg"
else
    echo -e "${YELLOW}!${NC} No retroarch.cfg found (bundled config was not deployed)"
fi

echo -e "\n${CYAN}[AntiMicroX]${NC}"
command -v antimicrox >/dev/null && echo -e "${GREEN}✓${NC} AntiMicroX installed" || echo -e "${RED}✗${NC} AntiMicroX missing"
AMGP_COUNT=$(find "$HOME/.config/antimicrox" -maxdepth 1 -type f \( -iname "*.amgp" -o -iname "*.gamecontroller.amgp" \) 2>/dev/null | wc -l)
if [ "$AMGP_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $AMGP_COUNT AntiMicroX profile(s) found in ~/.config/antimicrox"
else
    echo -e "${YELLOW}!${NC} No AntiMicroX profile found (bundled config was not deployed)"
fi

echo -e "\n${CYAN}[Gamepad Mapper]${NC}"
if [ -x /usr/local/bin/gamepad_to_keys.py ]; then
    echo -e "${GREEN}✓${NC} gamepad_to_keys.py installed"
else
    echo -e "${RED}✗${NC} gamepad_to_keys.py missing"
fi
if python3 -c "import evdev" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} python-evdev importable (provides both device reading AND evdev.UInput for writing - no separate uinput package needed)"
else
    echo -e "${RED}✗${NC} python-evdev not importable"
fi
CAL_COUNT=$(find /etc/sgbu -maxdepth 1 -type f -iname "*.deadzone" 2>/dev/null | wc -l)
if [ "$CAL_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $CAL_COUNT stick-drift calibration profile(s) in /etc/sgbu"
else
    echo -e "${YELLOW}!${NC} No stick-drift calibration saved yet (run 'Calibrate Stick Drift' from the boot menu)"
fi

echo -e "\n${CYAN}[Input Devices]${NC}"
if ls /dev/input/event* >/dev/null 2>&1; then
    COUNT=$(ls /dev/input/event* | wc -l)
    echo -e "${GREEN}✓${NC} $COUNT input device(s) detected"
else
    echo -e "${RED}✗${NC} No input devices found"
fi

echo -e "\n${CYAN}[Init System]${NC}"
if command -v systemctl >/dev/null && systemctl --version >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} systemd detected"
elif command -v rc-service >/dev/null; then
    echo -e "${GREEN}✓${NC} OpenRC detected"
else
    echo -e "${YELLOW}!${NC} Init system not identified"
fi

echo -e "\n${CYAN}Done.${NC}"
EOF
sudo chmod +x "$DIAGNOSTIC"

# -------------------------------
# 11. AUTOLOGIN & SERVICE SETUP
# -------------------------------

# Detect init system
use_systemd=false
use_openrc=false
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    use_systemd=true
elif command -v rc-service >/dev/null 2>&1; then
    use_openrc=true
fi

if $use_systemd; then
    echo -e "${YELLOW}Configuring Autologin on TTY1 (systemd)...${NC}"
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
    sudo systemctl daemon-reload

    for dm in gdm sddm lightdm lxdm; do
        if systemctl is-enabled "$dm" >/dev/null 2>&1; then
            sudo systemctl disable "$dm" 2>/dev/null && echo "Disabled $dm"
        fi
    done

elif $use_openrc; then
    echo -e "${YELLOW}Configuring Autologin on TTY1 (OpenRC / agetty)...${NC}"
    # Gentoo / OpenRC: edit /etc/inittab to autologin
    if [ -f /etc/inittab ]; then
        if ! grep -q "autologin" /etc/inittab; then
            sudo sed -i "s|^c1:.*agetty.*tty1.*|c1:12345:respawn:/sbin/agetty --autologin $USER_NAME --noclear tty1 38400 linux|" /etc/inittab
            echo -e "${GREEN}inittab updated for autologin.${NC}"
        else
            echo -e "${GREEN}Autologin already set in inittab.${NC}"
        fi
    else
        echo -e "${YELLOW}Could not find /etc/inittab — configure autologin manually.${NC}"
    fi
fi

# -------------------------------
# 12. BLUETOOTH SERVICE
# -------------------------------
echo -e "${YELLOW}Configuring Bluetooth service...${NC}"

if $use_systemd; then
    sudo systemctl enable bluetooth.service 2>/dev/null || true
    sudo systemctl start bluetooth.service 2>/dev/null || true
elif $use_openrc; then
    sudo rc-update add bluetooth default 2>/dev/null || true
    sudo rc-service bluetooth start 2>/dev/null || true
fi

command -v rfkill >/dev/null && sudo rfkill unblock bluetooth 2>/dev/null || true

if command -v bluetoothctl >/dev/null; then
    printf 'power on\nagent on\ndefault-agent\n' | sudo bluetoothctl || true
fi

# -------------------------------
# 13. PS4 CONTROLLER BLUETOOTH FIX (ARCH ONLY)
# -------------------------------
run_ps4_fix() {
    local PS4_FIX="$SCRIPT_DIR/ps4-fix.sh"

    if [ "$DISTRO" != "arch" ]; then
        echo -e "${YELLOW}!${NC} ps4-fix.sh only supports Arch Linux (it calls pacman directly) — skipping on $DISTRO."
        return
    fi

    if [ ! -f "$PS4_FIX" ]; then
        echo -e "${YELLOW}!${NC} ps4-fix.sh not found next to this script ($SCRIPT_DIR) — skipping. Make sure you cloned the full repo."
        return
    fi

    echo ""
    echo -e "${CYAN}================================================"
    echo -e "   PS4 CONTROLLER BLUETOOTH FIX"
    echo -e "================================================${NC}"
    echo "This reloads the hid_sony kernel module and walks you through"
    echo "pairing a DualShock 4 over Bluetooth (fixes touchpad/button issues)."
    read -r -p "Run ps4-fix.sh now? [y/N]: " PS4_FIX_CONFIRM
    if [[ "${PS4_FIX_CONFIRM,,}" == "y" ]]; then
        echo -e "${YELLOW}Running ps4-fix.sh...${NC}"
        bash "$PS4_FIX" || echo -e "${YELLOW}ps4-fix.sh exited with an error — continuing installer...${NC}"
    else
        echo -e "${YELLOW}Skipping PS4 controller Bluetooth fix. You can run it later with: bash $PS4_FIX${NC}"
    fi
}
run_ps4_fix

# -------------------------------
# 14. SHELL TRIGGER
# -------------------------------
TARGET_PROFILE="$HOME/.bash_profile"
[[ ! -f "$TARGET_PROFILE" ]] && TARGET_PROFILE="$HOME/.profile"
TRIGGER='[ "$(tty)" = "/dev/tty1" ] && exec /usr/local/bin/bootmenu.sh'
if ! grep -q "bootmenu.sh" "$TARGET_PROFILE" 2>/dev/null; then
    echo "$TRIGGER" >> "$TARGET_PROFILE"
fi

# -------------------------------
# 15. RETROARCH CORES
# -------------------------------
echo -e "${YELLOW}Downloading RetroArch cores...${NC}"
mkdir -p "$HOME/.config/retroarch/cores"
if command -v wget >/dev/null; then
    cd "$HOME/.config/retroarch/cores/"
    wget -q -r -np -nd -R "index.html*" -A "*.zip" \
        https://buildbot.libretro.com/nightly/linux/x86_64/latest/ 2>/dev/null || true
    for z in *.zip; do [ -f "$z" ] && unzip -o "$z" && rm "$z"; done
    cd - >/dev/null
fi

# -------------------------------
# DONE
# -------------------------------
echo -e "\n${CYAN}================================================"
echo -e "   INSTALLATION COMPLETE"
echo -e "   Distro: $DISTRO"
echo -e "================================================${NC}"
echo -e "${GREEN}✓${NC} Boot menu:   $BOOTMENU"
echo -e "${GREEN}✓${NC} Gamepad mapper: $GAMEPAD_PYTHON (evdev only, no AUR uinput package needed)"
echo -e "${GREEN}✓${NC} Stick drift calibration: $STICK_CALIBRATE (menu: 'Calibrate Stick Drift')"
echo -e "${GREEN}✓${NC} Steam:       installed (GamepadUI enabled)"
echo -e "${GREEN}✓${NC} Vulkan:      choice applied (option $VULKAN_CHOICE)"
echo -e "${GREEN}✓${NC} Bluetooth:   enabled & started"
echo -e "${GREEN}✓${NC} Splash:      drop custom ASCII art at /etc/sgbu/splash.txt, else figlet is used"
if [ -f "$SCRIPT_DIR/sgbu_logo.png" ]; then
    echo -e "${GREEN}✓${NC} Plymouth boot splash: installed from sgbu_logo.png (reboot to see it)"
else
    echo -e "${YELLOW}!${NC} Plymouth boot splash: skipped (no sgbu_logo.png found next to the script)"
fi
if [ -d "$CONF_DIR" ]; then
    echo -e "${GREEN}✓${NC} Bundled configs: deployed from $CONF_DIR"
else
    echo -e "${YELLOW}!${NC} Bundled configs: skipped (no ./conf folder found — clone the full repo)"
fi
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} You must REBOOT for group permissions to apply."
echo "On next boot the menu will load automatically on TTY1."

if [ "$DISTRO" = "gentoo" ]; then
    echo ""
    echo -e "${YELLOW}Gentoo notes:${NC}"
    echo "  - Check USE flags for mesa/vulkan in /etc/portage/package.use/"
    echo "  - If using OpenRC, verify autologin in /etc/inittab"
    echo "  - Only dev-python/evdev is required for gamepad mapping now (evdev.UInput"
    echo "    handles event injection, no separate uinput package needed)."
fi

if [ "$DISTRO" = "debian" ]; then
    echo ""
    echo -e "${YELLOW}Debian/Ubuntu notes:${NC}"
    echo "  - For NVIDIA: you may need linux-headers and dkms installed first"
    echo "  - Steam may prompt for licence acceptance on first launch"
    echo "  - If steam-installer is unavailable, try: sudo apt-get install steam"
fi

echo ""
read -r -p "Press Enter to finish..."