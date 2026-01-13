'''
created BY marinP/stuffbymax
description: a tool thats allows user to use gamepad as keyboard
License MIT
'''

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