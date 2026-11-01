#!/usr/bin/env python3
"""Stream normalized gyro readings from a supported Sony controller."""

try:
    import evdev
except ImportError:
    print("STATUS|unavailable|python-evdev is not installed", flush=True)
    raise SystemExit(0)


CONTROLLER_NAMES = ("sony", "playstation", "dualshock", "sixaxis", "wireless controller")
GYRO_AXES = (evdev.ecodes.ABS_RX, evdev.ecodes.ABS_RY)


def find_gyro_device():
    for path in evdev.list_devices():
        try:
            device = evdev.InputDevice(path)
            name = device.name.lower()
            if not any(controller in name for controller in CONTROLLER_NAMES):
                device.close()
                continue

            capabilities = device.capabilities()
            axes = {code for code, _ in capabilities.get(evdev.ecodes.EV_ABS, [])}
            if all(axis in axes for axis in GYRO_AXES):
                return device
            device.close()
        except OSError:
            continue
    return None


def main():
    try:
        device = find_gyro_device()
    except OSError as error:
        print(f"STATUS|unavailable|cannot inspect input devices: {error}", flush=True)
        return

    if device is None:
        print("STATUS|unavailable|no supported gyro input device found", flush=True)
        return

    try:
        print(f"STATUS|active|{device.name}", flush=True)
        for event in device.read_loop():
            if event.type != evdev.ecodes.EV_ABS or event.code not in GYRO_AXES:
                continue
            value = max(-100, min(100, int(event.value / 327.68)))
            if event.code == evdev.ecodes.ABS_RX:
                print(f"MOTION|{value}|", flush=True)
            else:
                print(f"MOTION||{value}", flush=True)
    except OSError as error:
        print(f"STATUS|unavailable|gyro read failed: {error}", flush=True)
    finally:
        device.close()


if __name__ == "__main__":
    main()
