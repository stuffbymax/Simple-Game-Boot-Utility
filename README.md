# Simple Game Boot Utility (SGBU)

Scripts to create an **automatic boot menu** on TTY1, integrate gamepad support, and get Steam (GamepadUI) + RetroArch booting straight into a console-like experience — with Vulkan driver selection, Bluetooth setup, and bundled controller/emulator configs.

> ⚠️ **Warning:** This is experimental and modifies system files (pacman/apt/emerge repos, autologin, udev rules, group memberships). Review the scripts before running them, and test in a disposable environment first.

---

## Which script do I run?

| Script | Status | Notes |
|---|---|---|
| **`SGBU.sh`** | ✅ **Active — use this one** | Multi-distro installer. Supports **Arch Linux, Debian/Ubuntu, and Gentoo**. This is where new features land first. |
| `install_sgbu_arch.sh` | 🟡 **Deprecated** | Arch-only installer. Being phased out in favor of `SGBU.sh` now that the multi-distro script has full feature parity. Still functional, but won't receive new features going forward. |
| `SGBU-debian-testing.sh` / `SGBU-debian-old.sh` | 🗄️ **Deprecated / archived** | Early Debian-specific experiments, superseded by `SGBU.sh`. Kept in `old/` for reference only — do not use for new installs. |

> `SGBU.sh` remains the core installer and boot-menu action script. The boot UI implementation has been moved out of the core script into `xmb-ui.sh`, which is installed and launched by the boot menu. Run `bash test_ui.sh` to preview the UI without installing the boot menu.

If you're starting fresh, **run `SGBU.sh`**.

---

> **GPU telemetry note:** NVIDIA temperature, utilization, and VRAM readings use `nvidia-smi` when the proprietary NVIDIA driver and utility are available. With Nouveau, these readings may be unavailable. Intel and AMD temperatures/load are best-effort readings from Linux kernel sensor interfaces; support and accuracy vary by GPU, driver, and system. Intel/AMD temperature reporting has not been verified across hardware, so treat those readings as informational and expect `N/A` when a sensor is not exposed.

## Features

* **Automatic Boot Menu** (`bootmenu.sh`, installed to `/usr/local/bin/`)
  `SGBU.sh` handles installation and game/session actions; the UI itself lives in `xmb-ui.sh` and is launched by the boot menu. During installation, you can choose whether to show the optional SGBU splash screen before the XMB UI. To customize the splash, place text or ASCII art in `/etc/sgbu/splash.txt`. It presents a horizontal row of category icons with vertically navigable items on TTY1. It shows the operating system, CPU model/core/thread counts, each detected GPU's model/driver/version/VRAM, live CPU/GPU usage and temperatures, RAM usage/capacity, and a live clock/date (`YYYY/MM/DD HH:MM`). NVIDIA temperature, utilization, and VRAM are queried with `nvidia-smi` when available; Nouveau may not expose those readings. Intel and AMD telemetry uses kernel sensor interfaces where available, but support and accuracy vary by hardware and driver and have not been verified across all systems. Intel GPU load may be estimated from the kernel RC6 residency counter. Unavailable readings display as `N/A`. A second detected Intel, AMD, or NVIDIA GPU gets its own hardware header and usage/temperature line. The Settings category lets you cycle the background color and icon set; choices are saved in `~/.config/sgbu/xmb.conf`. The background color changes by month in Auto mode; background particles respond to compatible PS3/PS4 gyro input when Linux exposes it, otherwise they move automatically. Navigate categories with left/right and items with up/down; Enter selects or changes a setting.

* **Multi-Distro Package Handling**
  Detects Arch (`pacman`), Debian/Ubuntu (`apt-get`), or Gentoo (`emerge`) and installs the right package names for each — base tools, Vulkan drivers, and Steam.

* **Vulkan Driver Selection**
  Interactive menu to pick AMD (amdvlk or RADV/mesa), NVIDIA (proprietary or open kernel module), or Intel drivers at install time.

* **Gamepad Support**
  `gamepad_to_keys.py` maps PS3, PS4, PS5, Xbox 360/One/Series, and generic controllers to keyboard keys for menu navigation, with analog-stick D-pad emulation.

* **Bundled Configs (RetroArch / AntiMicroX)**
  If you clone the full repo, the installer automatically deploys:
  * `conf/retroarch` → `~/.config/retroarch` (existing `retroarch.cfg` is backed up, not overwritten silently)
  * `conf/antimicrox` → `~/.config/antimicrox`
  The boot menu then launches RetroArch with that config and AntiMicroX with the bundled controller profile automatically — no manual setup needed. If the `conf` folder isn't found next to the script, this step is skipped with a clear notice instead of failing.

* **PS4 Controller Bluetooth Fix**
  Optional `ps4-fix.sh` reloads the `hid_sony` kernel module and walks you through pairing a DualShock 4 over Bluetooth (fixes touchpad/button issues). The installer asks if you want to run it (Arch-only for now, since it calls `pacman` directly).

* **RetroArch Cores**
  Automatically downloads the latest nightly cores for Linux x86_64.

* **Bluetooth & Autologin**
  Enables and starts Bluetooth (systemd or OpenRC), configures TTY1 autologin, and disables conflicting display managers so the boot menu takes over.

* **Diagnostics**
  Built-in `diagnostic.sh` reports Vulkan/GPU, Steam, Bluetooth, Xorg, RetroArch, AntiMicroX profile, input devices, and init system status — useful for troubleshooting after install.

---

## Prerequisites

* Arch Linux, Debian/Ubuntu, or Gentoo (or a close derivative)
* `sudo` access
* Python 3 with `evdev` (on Arch, install `python-evdev` if it is not available)

---

## Installation

```bash
git clone https://github.com/stuffbymax/Simple-Game-Boot-Utility.git
cd Simple-Game-Boot-Utility
chmod +x SGBU.sh
./SGBU.sh
reboot
```

Run it **from inside the cloned repo** — the installer looks for `conf/` and `ps4-fix.sh` next to itself, so those steps only work if the whole repo is present, not just the script on its own.

After reboot, the boot menu appears automatically on TTY1, showing all detected sessions and supported apps.

To preview the XMB interface without installing the boot menu or launching anything, run `bash test_ui.sh` from the repository on a local terminal or an interactive SSH session.

Customize the preview or boot menu with environment variables:

```bash
SGBU_XMB_COLOR=purple SGBU_XMB_ICONS=ascii bash test_ui.sh
```

`SGBU_XMB_COLOR` accepts `auto` (monthly colors), `blue`, `purple`, `green`, `red`, or `cyan`. `SGBU_XMB_ICONS` accepts `unicode` or `ascii`. In the UI, select **Settings → Background Color** or **Icon Set** and press Enter to cycle options; changes persist in `~/.config/sgbu/xmb.conf`. Environment variables override the saved choices for that process. Hardware sensors and detailed GPU information depend on what the OS and installed drivers expose; unavailable readings display as `N/A` or `Unknown`.

---

## File Locations

| File / Directory                | Purpose                                              |
| -------------------------------- | ----------------------------------------------------- |
| `/usr/local/bin/bootmenu.sh`      | Boot menu action/launcher script                      |
| `/usr/local/bin/sgbu-xmb-ui.sh`   | XMB-style interface, separated from the SGBU core script |
| `/usr/local/bin/sgbu-gyro-sensor.py` | Optional Sony controller gyro reader                 |
| `/usr/local/bin/gamepad_to_keys.py` | Python gamepad-to-keyboard mapper                    |
| `/usr/local/bin/diagnostic.sh`    | System diagnostics script                              |
| `conf/retroarch/`                 | Bundled RetroArch config, deployed to `~/.config/retroarch` |
| `conf/antimicrox/`                | Bundled AntiMicroX profile(s), deployed to `~/.config/antimicrox` |
| `~/.config/retroarch/cores/`      | Downloaded RetroArch cores                             |
| `~/.xinitrc`                      | Generated per-session X startup script                |
| `ps4-fix.sh`                       | Optional DualShock 4 Bluetooth pairing fix (Arch)      |
| `emulators/`                       | Emulator-related assets/configs                        |
| `old/`                             | Archived/deprecated scripts, kept for reference        |

---

## Controller Mapping

* **PS3 / PS4 / PS5**: Cross/X → Enter, Circle → Escape, Square → Backspace, Triangle → Space, D-Pad → Arrows
* **Xbox / Generic**: A → Enter, B → Escape, X → Backspace, Y → Space, D-Pad → Arrows

Mappings can be modified in `gamepad_to_keys.py`. Menu navigation also works via the left analog stick.

---

## Known Issues

* AntiMicroX/RetroArch configs only deploy if you clone the full repo (not if you download a single script file).
* `ps4-fix.sh` currently only runs automatically from `SGBU.sh` on Arch, since it calls `pacman` directly.
* Some settings may not apply automatically depending on your desktop environment — this project is still experimental.

See `todo.md` for planned work.

---

## License

[MIT License](https://raw.githubusercontent.com/stuffbymax/Simple-Game-Boot-Utility/main/LICENSE)

---

## Screenshots

<img width="1912" height="1005" alt="image" src="https://github.com/user-attachments/assets/8c392087-8ba0-4137-b247-f74bbbd7fa5b" />
