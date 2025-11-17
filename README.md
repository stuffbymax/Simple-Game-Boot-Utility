### README made BY AI

# Boot Menu & Controller Mapper Setup

This repository contains a Bash script to set up a boot menu on Debian-based systems, integrate gamepad support via AntimicroX and Python, and configure multiple lightweight desktop environments (IceWM, XFCE4, TWM).

> ⚠️ **Note:** External files like AntimicroX profiles and retroarch gamepad keybinds are not yet uploaded to GitHub. This script is provided "as is". It may fail to apply some settings, leave keybindings unset, or choose different drivers (Intel by default). Do not run on critical systems — test in a disposable environment first. By continuing you acknowledge these limitations.

> also I will never make this as Linux distro because is pointless
---

## Features

* **Boot Menu**
  Provides a menu on TTY1 to launch:

1. RetroArch (fullscreen)
2. IceWM desktop
3. XFCE4 desktop
4. TWM desktop
5. Reboot
6. Shutdown

* **Gamepad Support**
  Python script maps PS3, PS4, Xbox, and generic controllers to keyboard keys for menus and games.

* **Autostart Configurations**

  * AntimicroX profiles for gamepad mapping
  * Onboard on-screen keyboard for IceWM and XFCE4
  * Desktop environment-specific autostart scripts

* **Lightweight Desktop Environments**
  IceWM, XFCE4, and TWM with basic menus and configurations.

* **RetroArch Cores**
  Automatically downloads and extracts the latest RetroArch cores for Linux x86_64.

---

## Prerequisites

* Debian-based Linux distribution (Debian, Ubuntu, etc.)
* Access to `sudo`
* Python 3 with `evdev` and `uinput` modules

---

## Installation

```bash
git clone https://github.com/stuffbymax/retro
cd retro
chmod +X setup_bootmenu_testing.sh
./setup_bootmenu_testing.sh
```

3. **Reboot**
   The boot menu will appear automatically on TTY1.

---

## File Locations

| File / Directory                | Purpose                                                |
| ------------------------------- | ------------------------------------------------------ |
| `/usr/local/bin/bootmenu.sh`    | Boot menu launcher script                              |
| `/usr/local/bin/ps3_to_keys.py` | Python gamepad-to-keyboard mapper                      |
| `$HOME/.icewm/menu`             | IceWM menu configuration                               |
| `$HOME/.icewm/startup`          | IceWM autostart script (AntimicroX + Onboard)          |
| `$HOME/.config/autostart/`      | XFCE4 autostart desktop entries (AntimicroX + Onboard) |
| `$HOME/.twm/startup`            | TWM autostart script                                   |
| `$HOME/.twm/colors`             | TWM color configuration                                |
| `$HOME/.twm/twmrc`              | TWM main configuration                                 |
| `.config/retroarch/cores/`      | Downloaded RetroArch cores                             |

---

## Controller Mapping

Supported controllers and mappings:

* **PS3 / PS4**: X/Cross → Enter, Circle → Escape, Square → Backspace, Triangle → Space, D-Pad → Arrow keys
* **Xbox / Generic**: A → Enter, B → Escape, X → Backspace, Y → Space, D-Pad → Arrow keys

> You can modify the mapping inside `ps3_to_keys.py`.

---

## Known Issues
* TWM autostart currently does not fully support gamepad input with AntimicroX.
* External AntimicroX profiles must be added manually (`bootmenu_gamepad_profile.amgp`).

---

## License Under

[MIT License](https://raw.githubusercontent.com/stuffbymax/retro/refs/heads/main/LICENSE)

---

## screenshots

<img width="962" height="799" alt="Screenshot 2025-10-16 114801" src="https://github.com/user-attachments/assets/3664ebfe-f984-45ec-b301-235b3ea437b8" />

<img width="482" height="319" alt="image" src="https://github.com/user-attachments/assets/9cdc5bde-563e-4475-87a2-d78870f416f1" />




