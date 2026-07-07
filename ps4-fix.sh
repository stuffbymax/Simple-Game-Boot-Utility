#!/usr/bin/env bash
set -e

echo "== DS4 Bluetooth fix script =="

# 1. Install required packages (safe to re-run)
sudo pacman -S --needed bluez bluez-utils

# 2. Enable Bluetooth service
sudo systemctl enable --now bluetooth.service

# 3. Reload kernel modules (DS4 support lives here)
sudo modprobe -r hid_sony || true
sudo modprobe hid_sony

# 4. Restart Bluetooth to clear bad state
sudo systemctl restart bluetooth

echo "== Remove old controller pairing (if exists) =="

# 5. Remove previously paired DS4 devices
bluetoothctl <<EOF
power on
devices
remove
quit
EOF

echo "== Put controller into pairing mode =="
echo "Hold SHARE + PS button until light flashes rapidly"

sleep 5

echo "== Starting pairing process =="

# 6. Auto-pair DS4
bluetoothctl <<EOF
power on
agent on
default-agent
scan on
EOF

echo ""
echo "Now manually pick the controller MAC address from scan output above."
echo "Then run:"
echo "  bluetoothctl"
echo "  pair XX:XX:XX:XX:XX:XX"
echo "  trust XX:XX:XX:XX:XX:XX"
echo "  connect XX:XX:XX:XX:XX:XX"
echo ""

echo "Done. Touchpad + buttons should work once connected."
