# 🌌 Arch Hyprland Custom Dotfiles

A sleek, lightweight, and modern Hyprland configuration for Arch Linux featuring fluid spring animations, native 16-band PipeWire audio processing, dynamic Material You theming, and an interactive modular Waybar.

---

## ✨ Features

* **🎛️ Native 16-Band PipeWire Equalizer (`audio-enhancer.sh`)**:
  * Near-zero CPU native PipeWire DSP filter chain replacing heavy electron/GTK equalizers.
  * Real-time $0\text{ms}$ latency slider tuning via SPA Props without daemon restarts.
  * Per-device preset memory (Bass Boost, Vocal Clarity, Gaming, Movie, Rock, Custom) with hardware volume normalization.
  * Interactive floating GTK3 popup GUI with single-instance click toggle.

* **🔊 Multi-Output Audio Switcher (`audio-switcher.sh`)**:
  * Seamless switching between USB DACs, HDMI displays, Bluetooth, and internal speakers.
  * Preserves and restores distinct volume levels per output device.

* **🖥️ Display Mode Manager (`display-mode.sh`)**:
  * 1-Click Rofi menu for Mirroring / Duplicating, Extending, and External/Internal monitor switching.

* **🎵 CJK-Aware MPRIS Media Scroller (`mpris-scroll`)**:
  * Native C daemon supporting multi-byte non-ASCII characters (Japanese, Korean, Chinese) without jitter or boundary clipping.
  * Configurable bounce pause, speed, and track metadata marquee.

* **⛅ Weather Forecast & Location Selector (`weather.py`)**:
  * 47 WWO condition code mapping with astronomical day/night icon calculation.
  * Rich calendar-style hover popdown card with 3-day forecast table, humidity, wind, and UV index.
  * Interactive Rofi dialog to set any city or auto-detect by IP.

* **🎨 Dynamic Theming & Glass Aesthetics**:
  * Integrated **Matugen** color palette generation from active wallpaper.
  * Fluid spring workspace pill expansion with cubic-bezier physics.
  * Fully customizable SwayNC notification center and control drawer.

---

## 📂 Repository Structure

```
.
├── .config/
│   ├── cava/               # Audio visualizer configurations and GLSL shaders
│   ├── fastfetch/          # System information fetch display configs
│   ├── hypr/               # Hyprland core configuration
│   │   ├── configs/        # Modular Lua config files (keybinds, window rules, animations)
│   │   ├── scripts/        # System actions, audio, display, and utility scripts
│   │   └── UserScripts/    # Weather and wallpaper helper scripts
│   ├── kitty/              # Kitty terminal emulator configuration
│   ├── matugen/            # Material You theme generator templates
│   ├── rofi/               # Rofi app launcher and menu themes
│   ├── swaync/             # Sway Notification Center config, themes, and icons
│   ├── waybar/             # Waybar modular configs, custom modules, and CSS styles
│   └── wlogout/            # Power / Session logout menu
├── wallpapers/             # Curated aesthetic wallpapers
├── compile_commands.json   # Clangd compilation database for C components
└── README.md
```

---

## ⌨️ Keybindings Cheat Sheet

Modifier: <kbd>Super</kbd> (Windows Key)

| Keybinding | Action | Description |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Return</kbd> | Terminal | Open Kitty terminal |
| <kbd>Super</kbd> + <kbd>D</kbd> | App Launcher | Open Rofi application launcher |
| <kbd>Super</kbd> + <kbd>E</kbd> | File Manager | Open Nautilus file manager |
| <kbd>Super</kbd> + <kbd>Q</kbd> | Close Window | Close active focused window |
| <kbd>Super</kbd> + <kbd>Space</kbd> | Toggle Float | Toggle floating state for active window |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>F</kbd> | Fullscreen | Toggle fullscreen mode |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>A</kbd> | Audio Switcher | Select audio output device (Speakers, DAC, HDMI) |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>A</kbd> | Audio Enhancer | Open 16-band PipeWire Equalizer GUI |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>P</kbd> | Display Modes | Switch monitor layout (Mirror, Extend, Laptop only) |
| <kbd>Super</kbd> + <kbd>W</kbd> | Wallpaper Picker | Open wallpaper selection menu |
| <kbd>Super</kbd> + <kbd>V</kbd> | Clipboard | Open clipboard history with image preview |
| <kbd>Super</kbd> + <kbd>C</kbd> | Color Picker | Pick screen color with `hyprpicker` |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | Screenshot | Capture area screenshot |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>B</kbd> | Waybar Styles | Choose Waybar visual theme |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>B</kbd> | Waybar Layouts | Choose Waybar module layout |
| <kbd>Super</kbd> + <kbd>H</kbd> | Hide Waybar | Toggle Waybar visibility |
| <kbd>Super</kbd> + <kbd>L</kbd> | Lock Screen | Lock session with `hyprlock` |
| <kbd>Super</kbd> + <kbd>X</kbd> | Power Menu | Open Wlogout power menu |

---

## 🛠️ Requirements & Dependencies

* **Compositor**: `hyprland` (0.55+)
* **Bar & Notifications**: `waybar`, `swaync`
* **Audio & Processing**: `pipewire`, `wireplumber`, `pipewire-pulse`, `pamixer`, `playerctl`
* **Menus & Dialogs**: `rofi-wayland`, `wlogout`
* **Theming**: `matugen-bin`, `swww`, `kitty`, `libpipewire`
* **Python Dependencies**: `python`, `python-gobject`, `gtk3`
