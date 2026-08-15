#!/usr/bin/env bash
# =============================================================================
# Hyprland Rice Setup Script
# =============================================================================
# Targets : Arch / Artix (+ OpenRC) with pacman + yay
# Render  : Intel iGPU (NVIDIA left for offload/docker, no hyprland changes)
# Assumes : repo root contains .config/ and wallpapers/
#
# Run:  bash setup.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$REPO_DIR/.config"
WALL_DIR="$REPO_DIR/wallpapers"
HOME_CONFIG="$HOME/.config"
WALL_TARGET="$HOME/Pictures/wallpapers"
BACKUP_DIR="$HOME_CONFIG.bak.$(date +%Y%m%d-%H%M%S)"

# Which .config/* entries to install (skip backups / junk)
INSTALL_DIRS=(
  hypr
  waybar
  swaync
  wlogout
  rofi
  kitty
  cava
  matugen
  fastfetch
)

# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------
c_red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
c_blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }

need_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    c_yellow "Running as root. Note: yay/pacman fine, but dotfiles will go to /root instead of $HOME."
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    return 0
  fi
  c_red "Please re-run with sudo (or install sudo)."
  exit 1
}

run() { printf '==> '; c_blue "$*"; "$@"; }

# -----------------------------------------------------------------------------
# 1. PACKAGES
# -----------------------------------------------------------------------------
install_packages() {
  c_blue "\n[1/5] Installing packages (pacman + yay)..."

  local repo_pkgs=(
    hyprland hyprlock hypridle hyprpicker
    waybar swaync wlogout rofi kitty cava awww
    nautilus yazi grim slurp brightnessctl playerctl pamixer
    network-manager-applet blueman hyprpolkitagent polkit
    xdg-desktop-portal-hyprland
    ttf-jetbrains-mono-nerd ttf-font-awesome
    pipewire wireplumber pipewire-pulse
  )

  # install missing repo packages
  local missing=()
  for p in "${repo_pkgs[@]}"; do
    pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p")
  done

  if (( ${#missing[@]} )); then
    c_yellow "Installing: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  else
    c_green "All repo packages already installed."
  fi

  # AUR package
  if ! command -v matugen >/dev/null 2>&1; then
    c_yellow "Installing matugen-bin from AUR..."
    yay -S --needed --noconfirm matugen-bin
  else
    c_green "matugen already installed."
  fi

  # NVIDIA (render on Intel; keep drivers for offload/docker)
  if pacman -Qi nvidia-580xx-utils >/dev/null 2>&1 || pacman -Qi nvidia-utils >/dev/null 2>&1; then
    c_green "NVIDIA drivers present (offload/docker only, no hyprland changes)."
  else
    c_yellow "NVIDIA drivers not detected. If you need them for docker/offload, install:"
    c_yellow "  sudo pacman -S nvidia-utils nvidia-dkms"
  fi
}

# -----------------------------------------------------------------------------
# 2. BACKUP + COPY
# -----------------------------------------------------------------------------
copy_dotfiles() {
  c_blue "\n[2/5] Backing up and copying dotfiles..."

  local need_backup=()
  for d in "${INSTALL_DIRS[@]}"; do
    [[ -e "$HOME_CONFIG/$d" ]] && need_backup+=("$d")
  done

  if (( ${#need_backup[@]} )); then
    c_yellow "Existing configs will be backed up to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    for d in "${need_backup[@]}"; do
      mv "$HOME_CONFIG/$d" "$BACKUP_DIR/$d"
    done
  fi

  for d in "${INSTALL_DIRS[@]}"; do
    if [[ -d "$CONFIG_DIR/$d" ]]; then
      run cp -r "$CONFIG_DIR/$d" "$HOME_CONFIG/"
    else
      c_red "Missing $CONFIG_DIR/$d - skipping."
    fi
  done

  # wallpapers (exclude junk like 'newfile')
  if [[ -d "$WALL_DIR" ]]; then
    mkdir -p "$WALL_TARGET"
    local wp
    for wp in "$WALL_DIR"/*; do
      [[ -f "$wp" && "$(basename "$wp")" != "newfile" ]] && run cp -n "$wp" "$WALL_TARGET/" || true
    done
    c_green "Wallpapers copied to $WALL_TARGET"
  fi
}

# -----------------------------------------------------------------------------
# 3. FIXES
# -----------------------------------------------------------------------------
fixes() {
  c_blue "\n[3/5] Applying Artix/OpenRC + repo fixes..."

  # swww -> awww rename (package 'awww' ships awww/awww-daemon)
  if ! command -v swww >/dev/null 2>&1 && command -v awww >/dev/null 2>&1; then
    c_yellow "Symlinking awww -> swww (swww was renamed to awww)"
    for b in awww awww-daemon; do
      src="$(command -v "$b")"
      dest="/usr/local/bin/${b/awww/swww}"
      if [[ -n "$src" && ! -e "$dest" ]]; then
        sudo ln -sf "$src" "$dest"
      fi
    done
  fi

  local HYPR="$HOME_CONFIG/hypr"

  # 3.1 screenshot shebang
  sed -i '1s|^!#|#!|' "$HYPR/scripts/screenshot.sh"
  chmod +x "$HYPR/scripts/"*.sh 2>/dev/null || true
  c_green "  screenshot.sh shebang fixed + scripts made executable."

  # 3.2 hyprland.lua: no systemd needed — autostarts already use full path
  # (hyprpolkitagent spawned as /usr/lib/hyprpolkitagent/hyprpolkitagent in hyprland.lua)

  # 3.3 hypridle.conf: systemctl suspend -> loginctl suspend
  sed -i 's|systemctl suspend|loginctl suspend|g' "$HYPR/hypridle.conf"

  # 3.4 wlogout layout: systemctl -> loginctl
  if [[ -f "$HOME_CONFIG/wlogout/layout" ]]; then
    sed -i -e 's|systemctl reboot|loginctl reboot|g' \
           -e 's|systemctl poweroff|loginctl poweroff|g' \
           -e 's|systemctl suspend|loginctl suspend|g' \
           -e 's|systemctl hibernate|loginctl hibernate|g' \
           "$HOME_CONFIG/wlogout/layout"
  fi

  # 3.5 waybar ModulesCustom: systemctl reboot
  if [[ -f "$HOME_CONFIG/waybar/ModulesCustom" ]]; then
    sed -i 's|systemctl reboot|loginctl reboot|g' "$HOME_CONFIG/waybar/ModulesCustom"
  fi

  # 3.6 Waybar: create empty UserModules + default symlinks
  local WB="$HOME_CONFIG/waybar"
  [[ -f "$WB/UserModules" && -s "$WB/UserModules" ]] || printf '{\n}\n' > "$WB/UserModules"
  ln -sf "$WB/configs/bintang default" "$WB/config"
  ln -sf "$WB/style/bintang default.css" "$WB/style.css"
  c_green "  Waybar default layout/style symlinked (bintang default)."

  # 3.7 hyprlock wallpaper symlink
  local current_wall
  current_wall="$(find "$WALL_TARGET" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -n1)"
  if [[ -n "$current_wall" ]]; then
    ln -sf "$current_wall" "$HYPR/current_wallpaper"
    c_green "  hyprlock current_wallpaper -> $(basename "$current_wall")"
  else
    c_yellow "  No wallpapers found; run the wppicker after first boot to set one."
  fi

  # 3.8 monitor line: default eDP-1 1920x1080@60 (laptop)
  c_yellow "  NOTE: monitor line in hyprland.lua is 'eDP-1, 1920x1080@60, 0x0, 1'."
  c_yellow "        Adjust resolution/monitor name if it doesn't match your display."

  # 3.9 colors.lua hardcoded wallpaper path is regenerated by matugen (phase 4)
}

# -----------------------------------------------------------------------------
# 4. MATUGEN
# -----------------------------------------------------------------------------
run_matugen() {
  c_blue "\n[4/5] Generating colors with Matugen..."

  local wall=""
  wall="$(find "$WALL_TARGET" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -n1)"
  if [[ -z "$wall" ]]; then
    c_yellow "  No wallpaper available - skipping matugen. Run 'matugen image <wall>' later."
    return 0
  fi

  # matugen uses swww (via awww symlink) for [config.wallpaper] set
  c_yellow "  Using wallpaper: $(basename "$wall")"
  ( command -v swww-daemon >/dev/null 2>&1 && swww-daemon >/dev/null 2>&1 & ) || true
  sleep 0.5

  if matugen image --prefer=lightness "$wall" 2>&1; then
    c_green "  Matugen colors generated for: hypr, kitty, waybar, rofi, cava."
  else
    c_red "  Matugen failed (exit $?). Colors can be regenerated anytime with:"
    c_red "    matugen image ~/Pictures/wallpapers/<your-wallpaper>"
  fi
}

# -----------------------------------------------------------------------------
# 5. SERVICES + SUMMARY
# -----------------------------------------------------------------------------
services_and_summary() {
  c_blue "\n[5/5] Services + summary..."

  if command -v rc-update >/dev/null 2>&1; then
    sudo rc-update add NetworkManager default 2>/dev/null || c_yellow "  NetworkManager service: skip/error"
    # optional bluetooth
    if pacman -Qi bluez >/dev/null 2>&1; then
      sudo rc-update add bluetoothd default 2>/dev/null || true
    fi
    c_green "  NetworkManager added to OpenRC default runlevel."
  else
    c_yellow "  Not OpenRC - enable NetworkManager with your init manually."
  fi

  c_green "\n===== SETUP COMPLETE ====="
  c_blue "Next steps:"
  printf '  1. Confirm monitor line: %s/hypr/hyprland.lua (line 5)\n' "$HOME_CONFIG"
  printf '  2. Start Hyprland from a TTY:  Hyprland\n'
  printf '  3. Wallpaper picker (rofi):      SUPER + W\n'
  printf '  4. NVIDIA apps (offload):        __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <cmd>\n'
  printf '  5. Backups saved to:             %s\n' "$BACKUP_DIR"
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
  need_root

  local pkg_install=1
  local do_copy=1

  if [[ "${1:-}" == "--no-packages" ]]; then pkg_install=0; fi
  if [[ "${2:-}" == "--no-copy" ]]; then do_copy=0; fi

  (( pkg_install )) && install_packages
  (( do_copy )) && copy_dotfiles
  (( do_copy )) && fixes
  (( do_copy )) && run_matugen
  services_and_summary
}

main "$@"
