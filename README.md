Readme is made by AI
# Boot Menu & Controller Mapper Setup

This repository provides scripts to create an **automatic boot menu** on TTY1, integrate gamepad support, and configure lightweight desktop environments (IceWM, XFCE4, TWM) on **Arch Linux**.

> ⚠️ **Warning:** External files like AntimicroX profiles and RetroArch keybinds are not included. This is experimental — some settings may not apply automatically. Test in a disposable environment.

---

## Features

* **Automatic Boot Menu**
  Detects available desktop sessions and applications such as RetroArch and Steam, then presents a menu on TTY1:

  1. RetroArch (fullscreen)
  2. Steam (if installed)
  3. Detected desktop environments (IceWM, XFCE4, TWM, etc.)
  4. Shell
  5. Reboot
  6. Shutdown

* **Gamepad Support**
  Python script maps PS3, PS4, Xbox, and generic controllers to keyboard keys.

* **Autostart Configurations**

  * AntimicroX profiles for gamepad mapping
  * Onboard on-screen keyboard for IceWM and XFCE4
  * DE-specific autostart scripts

* **Lightweight Desktop Environments**
  IceWM, XFCE4, TWM with minimal menus and configs.

* **RetroArch Cores**
  Automatically downloads latest cores for Linux x86_64.

---

## Prerequisites

* Arch Linux (or derivatives)
* `sudo` access
* Python 3 with `evdev` and `uinput` modules

---

## Installation

```bash
git clone https://github.com/stuffbymax/retro
cd retro
chmod +x setup_bootmenu.sh
./setup_bootmenu.sh
reboot
```

Boot menu will appear automatically on TTY1 after reboot, showing **all detected sessions and supported applications**.

---

## File Locations

| File / Directory                | Purpose                                           |
| ------------------------------- | ------------------------------------------------- |
| `/usr/local/bin/bootmenu.sh`    | Boot menu launcher script (auto-detects apps/DEs) |
| `/usr/local/bin/ps3_to_keys.py` | Python gamepad-to-keyboard mapper                 |
| `$HOME/.icewm/menu`             | IceWM menu configuration                          |
| `$HOME/.icewm/startup`          | IceWM autostart (AntimicroX + Onboard)            |
| `$HOME/.config/autostart/`      | XFCE4 autostart entries (AntimicroX + Onboard)    |
| `$HOME/.twm/startup`            | TWM autostart script                              |
| `$HOME/.twm/colors`             | TWM color configuration                           |
| `$HOME/.twm/twmrc`              | TWM main configuration                            |
| `.config/retroarch/cores/`      | Downloaded RetroArch cores                        |

---

## Controller Mapping

* **PS3 / PS4**:
  X → Enter, Circle → Escape, Square → Backspace, Triangle → Space, D-Pad → Arrows

* **Xbox / Generic**:
  A → Enter, B → Escape, X → Backspace, Y → Space, D-Pad → Arrows

Mappings can be modified in `ps3_to_keys.py`.

---

## Known Issues

* TWM autostart does not fully support AntimicroX yet.
* External AntimicroX profiles must be added manually (`bootmenu_gamepad_profile.amgp`).

---

## License

[MIT License](https://raw.githubusercontent.com/stuffbymax/retro/refs/heads/main/LICENSE)

---

## Screenshots

<img width="962" height="799" alt="Boot Menu" src="https://github.com/user-attachments/assets/3664ebfe-f984-45ec-b301-235b3ea437b8" />  

<img width="482" height="319" alt="RetroArch" src="https://github.com/user-attachments/assets/9cdc5bde-563e-4475-87a2-d78870f416f1" />  

---
