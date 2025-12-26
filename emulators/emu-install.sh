# name: emu-installer
# version: 0.1.0
# creator: stuffbymax (martinP)
# description: Distro-agnostic script to install or compile popular emulators.

#!/bin/bash


set -e

# Detect package manager
if command -v apt >/dev/null 2>&1; then
    PKG_INSTALL="sudo apt install -y"
    PKG_UPDATE="sudo apt update"
elif command -v pacman >/dev/null 2>&1; then
    PKG_INSTALL="sudo pacman -S --noconfirm"
    PKG_UPDATE="sudo pacman -Sy"
elif command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL="sudo dnf install -y"
    PKG_UPDATE="sudo dnf check-update"
else
    echo "No supported package manager found (apt, pacman, dnf). Exiting."
    exit 1
fi

echo "Choose installation method:"
echo "1) Install prebuilt packages"
echo "2) Compile from source"
echo "3) Exit"
read -rp "Enter 1, 2, or 3: " method

if [ "$method" = "1" ]; then
    echo "Updating package list..."
    $PKG_UPDATE

    echo "Installing emulators..."
    for pkg in qemu bochs dosbox bsnes snes9x fceux genesis-plus-gx mednafen ppsspp pcsx2 dolphin \
               atari800 aranym arcem b-em vice arnold advancemame blastem cannonball \
               emulationstation retroarch; do
        $PKG_INSTALL "$pkg" || echo "Package $pkg not available for your distro."
    done

    echo "All available emulators installed."

elif [ "$method" = "2" ]; then
    echo "Compiling emulators from source..."
    SRC_DIR="$HOME/src_emulators"
    mkdir -p "$SRC_DIR"
    cd "$SRC_DIR" || exit 1

    # Example: DOSBox
    if [ ! -d "dosbox" ]; then
        git clone https://github.com/dosbox-staging/dosbox-staging.git dosbox
    fi
    cd dosbox || exit
    ./autogen.sh
    ./configure
    make -j"$(nproc)"
    sudo make install
    cd "$SRC_DIR"

    # Example: RetroArch
    if [ ! -d "retroarch" ]; then
        git clone https://github.com/libretro/RetroArch.git retroarch
    fi
    cd retroarch || exit
    ./configure
    make -j"$(nproc)"
    sudo make install

    echo "Repeat compilation steps for other emulators as needed."

elif [ "$method" = "3" ]; then
    echo "Exiting..."
    exit 0

else
    echo "Invalid choice. Exiting."
    exit 1
fi

echo "Emulator setup complete!"
