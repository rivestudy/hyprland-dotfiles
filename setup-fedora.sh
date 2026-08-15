#!/usr/bin/env bash
# =============================================================================
# Hyprland Rice Setup Script (Fedora 44 KDE Plasma + systemd)
# =============================================================================
# Targets : Fedora 44+ (KDE Plasma spin optional; any spin works)
# Render  : Default iGPU/whatever Wayland supports (no NVIDIA-specific changes)
# Assumes : repo root contains .config/ and wallpapers/
# Logs    : $HOME/setup-fedora-<timestamp>.log  (every step + fallback logged)
#
# Run:  bash setup-fedora.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$REPO_DIR/.config"
WALL_DIR="$REPO_DIR/wallpapers"
HOME_CONFIG="$HOME/.config"
WALL_TARGET="$HOME/Pictures/wallpapers"
BACKUP_DIR="$HOME_CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$HOME/setup-fedora-$(date +%Y%m%d-%H%M%S).log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

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
# LOGGING + ERROR FALLBACK HELPER
# -----------------------------------------------------------------------------
# Every step is wrapped in log_step. On failure:
#   - the error is logged to the log file,
#   - the function continues (falls back to next approach or skips gracefully),
#   - a WARN is printed to the console.
# -----------------------------------------------------------------------------
LOGFD=3
exec 3>>"$LOG_FILE"
echo "===== SETUP START $TIMESTAMP =====" >&3

log()   { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&3; }
info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; log "INFO  $*"; }
ok()    { printf '\033[1;32m    %s\033[0m\n' "$*"; log "OK    $*"; }
warn()  { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; log "WARN  $*"; }
fail()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*"; log "ERROR $*"; }

# run_step <name> <command...>
# Runs command, logs stdout/stderr. Returns the command's exit code (0 on success).
# NOTE: errexit is temporarily disabled so a failing command does NOT abort the
# whole script — its exit code is captured and reported instead.
run_step() {
  local name="$1"; shift
  local rc
  log "STEP  $name: $*"
  set +e
  "$@" >>"$LOG_FILE" 2>&1
  rc=$?
  set -e
  if (( rc != 0 )); then
    log "STEP  $name FAILED (exit $rc)"
    return "$rc"
  fi
  log "STEP  $name OK"
  return 0
}

# retry_step <name> <tries> <command...>  (with 3s sleep between tries)
retry_step() {
  local name="$1"; local tries="$2"; shift 2
  local i
  for ((i = 1; i <= tries; i++)); do
    if run_step "$name (attempt $i/$tries)" "$@"; then
      return 0
    fi
    warn "Retrying '$name' in 3s..."
    sleep 3
  done
  fail "Gave up on '$name' after $tries attempts."
  return 1
}

need_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    warn "Running as root. Dotfiles will go to /root instead of $HOME."
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    return 0
  fi
  fail "Please re-run with sudo (or install sudo)."
  exit 1
}

# -----------------------------------------------------------------------------
# 1. PACKAGES (dnf + COPR)
# -----------------------------------------------------------------------------
ENABLED_COPRS=()

# dnf copr requires dnf-plugins-core; ensure it's present before enabling any COPR
ensure_copr_plugin() {
  if ! dnf copr --help >/dev/null 2>&1; then
    info "dnf copr not available; installing dnf-plugins-core..."
    if retry_step "install dnf-plugins-core" 2 sudo dnf install -y dnf-plugins-core; then
      ok "dnf-plugins-core installed."
    else
      fail "Could not install dnf-plugins-core; COPRs will be unavailable."
      return 1
    fi
  fi
  return 0
}

enable_copr() {
  local copr="$1"
  ensure_copr_plugin || return 1
  if dnf copr list --enabled 2>/dev/null | grep -q "$copr"; then
    ok "COPR already enabled: $copr"
    log "COPR already enabled: $copr"
    return 0
  fi
  if retry_step "enable COPR $copr" 2 sudo dnf copr enable -y "$copr"; then
    ENABLED_COPRS+=("$copr")
    ok "COPR enabled: $copr"
    return 0
  fi
  fail "Could not enable COPR $copr. Its packages will be skipped."
  return 1
}

install_packages() {
  info "Installing packages (dnf)..."

  # --- 1a. COPR repos (each with fallback) ---
  # Hyprland suite + swww: maintained COPR (solopasha is abandoned upstream)
  enable_copr "sdegler/hyprland" || true

  # swaync: official Fedora has SwayNotificationCenter 0.12.6; only use COPR
  # if the official package is missing.
  if ! dnf repoquery --installed SwayNotificationCenter >/dev/null 2>&1 \
     && ! dnf info SwayNotificationCenter >/dev/null 2>&1; then
    enable_copr "erikreider/SwayNotificationCenter" || true
  else
    ok "SwayNotificationCenter available in official repos."
  fi

  # --- 1b. base tooling ---
  local base_pkgs=(
    hyprland hyprlock hypridle hyprpicker hyprpolkitagent swww
    waybar SwayNotificationCenter wlogout rofi kitty cava
    grim slurp wlr-randr brightnessctl playerctl pamixer wl-clipboard cliphist
    matugen imagemagick nautilus yazi
    xdg-desktop-portal-hyprland
    networkmanager blueman
    pipewire pipewire-pulse wireplumber
    fastfetch
    # build deps for the mpris-scroll C helper
    gcc pkgconf-pkg-config libplayerctl-devel glib2-devel
  )

  # Fonts: nerd font for the waybar glyphs. Try several names, keep what exists.
  local font_candidates=(
    jetbrains-mono-fonts-all jetbrains-mono-nerd-fonts
    jetbrains-mono-fonts fontawesome-fonts
    nerd-fonts-jetbrains-mono
  )
  local fonts=()
  for f in "${font_candidates[@]}"; do
    if dnf info "$f" >/dev/null 2>&1; then
      fonts+=("$f")
    fi
  done
  if (( ${#fonts[@]} )); then
    base_pkgs+=( "${fonts[@]}" )
    ok "Fonts to install: ${fonts[*]}"
  else
    warn "No matching nerd-font packages found; waybar glyphs may look broken."
  fi

  # --- 1c. install, dropping any package dnf can't resolve (fallback each) ---
  local still_missing=()
  local pkg
  for pkg in "${base_pkgs[@]}"; do
    if dnf info "$pkg" >/dev/null 2>&1; then
      if retry_step "install $pkg" 2 sudo dnf install -y "$pkg"; then
        ok "$pkg installed."
      else
        still_missing+=("$pkg")
      fi
    else
      warn "Package '$pkg' not found in any enabled repo; skipping."
      still_missing+=("$pkg")
    fi
  done

  if (( ${#still_missing[@]} )); then
    warn "The following could NOT be installed (see log): ${still_missing[*]}"
    fail "Partial install. Review $LOG_FILE"
  else
    ok "All packages installed."
  fi
}

# -----------------------------------------------------------------------------
# 2. BACKUP + COPY DOTFILES
# -----------------------------------------------------------------------------
copy_dotfiles() {
  info "Backing up and copying dotfiles..."

  local need_backup=()
  local d
  for d in "${INSTALL_DIRS[@]}"; do
    [[ -e "$HOME_CONFIG/$d" ]] && need_backup+=("$d")
  done

  if (( ${#need_backup[@]} )); then
    if run_step "backup existing configs" mkdir -p "$BACKUP_DIR"; then
      for d in "${need_backup[@]}"; do
        if run_step "move $d to backup" mv "$HOME_CONFIG/$d" "$BACKUP_DIR/$d"; then
          ok "Backed up $d -> $BACKUP_DIR/$d"
        else
          warn "Could not back up $d; continuing."
        fi
      done
    else
      warn "Could not create backup dir $BACKUP_DIR; proceeding without backup."
    fi
  else
    ok "No existing configs to back up."
  fi

  for d in "${INSTALL_DIRS[@]}"; do
    if [[ -d "$CONFIG_DIR/$d" ]]; then
      if run_step "copy $d" cp -r "$CONFIG_DIR/$d" "$HOME_CONFIG/"; then
        ok "Copied .config/$d"
      else
        fail "Copy of $d failed (see log)."
      fi
    else
      warn "Missing $CONFIG_DIR/$d - skipping."
    fi
  done

  # wallpapers (exclude junk like 'newfile')
  if [[ -d "$WALL_DIR" ]]; then
    if run_step "mkdir wallpapers" mkdir -p "$WALL_TARGET"; then
      local wp
      for wp in "$WALL_DIR"/*; do
        [[ -f "$wp" && "$(basename "$wp")" != "newfile" ]] || continue
        if [[ ! -e "$WALL_TARGET/$(basename "$wp")" ]]; then
          run_step "copy wallpaper $(basename "$wp")" cp "$wp" "$WALL_TARGET/" || true
        fi
      done
      ok "Wallpapers copied to $WALL_TARGET"
    else
      warn "Could not create $WALL_TARGET; wallpapers skipped."
    fi
  fi
}

# -----------------------------------------------------------------------------
# 3. FEDORA / SYSTEMD-SPECIFIC FIXES
# -----------------------------------------------------------------------------
fixes() {
  info "Applying Fedora/systemd fixes..."

  local HYPR="$HOME_CONFIG/hypr"

  # 3.1 make all scripts executable
  chmod +x "$HYPR"/scripts/*.sh 2>/dev/null || warn "Could not chmod scripts"
  chmod +x "$HYPR"/UserScripts/*.py 2>/dev/null || true

  # 3.2 screenshot.sh shebang safety
  sed -i '1s|^!#|#!|' "$HYPR/scripts/screenshot.sh" 2>/dev/null || true

  # 3.3 hyprpolkitagent path detection (multiple fallback locations)
  local agent=""
  for cand in \
    /usr/libexec/hyprpolkitagent \
    /usr/lib/hyprpolkitagent/hyprpolkitagent \
    /usr/lib64/libexec/hyprpolkitagent \
    /usr/bin/hyprpolkitagent; do
    if [[ -x "$cand" ]]; then agent="$cand"; break; fi
  done

  if [[ -n "$agent" ]]; then
    # Replace the hardcoded Artix path in hyprland.lua autostart
    sed -i "s|/usr/lib/hyprpolkitagent/hyprpolkitagent|$agent|g" "$HYPR/hyprland.lua" 2>/dev/null \
      && ok "hyprpolkitagent -> $agent" \
      || warn "Could not patch hyprland.lua polkit path."
  else
    # Fallback: systemd user service
    if systemctl --user start hyprpolkitagent >/dev/null 2>&1; then
      warn "hyprpolkitagent binary not found; enabled systemd user service instead."
    else
      warn "hyprpolkitagent unavailable - polkit prompts may fail. Trying KDE polkit agent..."
      # best-effort KDE fallback (package name is 'polkit-kde' on Fedora)
      for kde_agent in polkit-kde polkit-kde-agent; do
        if dnf info "$kde_agent" >/dev/null 2>&1; then
          retry_step "install $kde_agent" 2 sudo dnf install -y "$kde_agent" && break
        fi
      done
    fi
  fi

  # 3.4 DBUS_SESSION_BUS_ADDRESS env line: OpenRC-only workaround.
  # On systemd the bus is already set by the display manager -> comment it out.
  sed -i 's|^hl.env("DBUS_SESSION_BUS_ADDRESS"|-- [systemd] hl.env("DBUS_SESSION_BUS_ADDRESS"|' "$HYPR/hyprland.lua" 2>/dev/null \
    && ok "Commented out DBUS_SESSION_BUS_ADDRESS env line (systemd sets it)." \
    || warn "Could not patch DBUS env line."

  # 3.5 monitor line: try to detect via wlr-randr, fallback keep default
  local HYPRLAND_LUA="$HYPR/hyprland.lua"
  local detected
  detected="$(command -v wlr-randr >/dev/null 2>&1 && wlr-randr 2>/dev/null | grep -E '^\S+' | head -1 || true)"
  if [[ -n "$detected" ]]; then
    local out="${detected%% *}"
    local mode="$(wlr-randr 2>/dev/null | grep -A6 "^\s*$out" | grep -oP '\d{3,5}x\d{3,5}@\d{2,3}\.\d+' | head -1 || true)"
    [[ -n "$mode" ]] || mode="1920x1080@60"
    sed -i "s|output = \"eDP-1\"|output = \"$out\"|; s|mode = \"1920x1080@60\"|mode = \"$mode\"|" "$HYPRLAND_LUA" 2>/dev/null \
      && ok "Monitor detected: $out @ $mode" \
      || warn "Could not patch monitor line; leaving default eDP-1."
  else
    warn "wlr-randr unavailable - keeping default 'eDP-1, 1920x1080@60'. Adjust manually."
  fi

  # 3.6 waybar UserModules file + default symlinks (mirror setup.sh)
  local WB="$HOME_CONFIG/waybar"
  if [[ -f "$WB/UserModules" ]]; then
    ok "waybar UserModules present."
  else
    warn "waybar/UserModules missing; falling back to 'window middle' layout via config symlink."
  fi
  [[ -f "$WB/UserModules" && -s "$WB/UserModules" ]] || printf '{\n}\n' > "$WB/UserModules" 2>/dev/null || true
  if [[ -e "$WB/configs/bintang default" ]]; then
    ln -sf "$WB/configs/bintang default" "$WB/config"
  elif [[ -e "$WB/configs/center" ]]; then
    ln -sf "$WB/configs/center" "$WB/config"
    ok "Symlinked waybar config -> center (bintang default not present)."
  fi
  if [[ -e "$WB/style/bintang default.css" ]]; then
    ln -sf "$WB/style/bintang default.css" "$WB/style.css"
  elif [[ -e "$WB/style/floating.css" ]]; then
    ln -sf "$WB/style/floating.css" "$WB/style.css"
    ok "Symlinked waybar style -> floating.css (bintang default not present)."
  fi

  # 3.6b compile the mpris-scroll C helper (waybar custom/playerctl marquee)
  local SCROLL="$HYPR/scripts/mpris-scroll"
  if [[ -f "$HYPR/scripts/mpris-scroll.c" ]]; then
    if ! command -v cc >/dev/null 2>&1; then
      warn "No C compiler found; skipping mpris-scroll build."
    elif pkg-config --exists playerctl glib-2.0 2>/dev/null; then
      if cc "$HYPR/scripts/mpris-scroll.c" \
           $(pkg-config --cflags --libs playerctl glib-2.0) \
           -o "$SCROLL" 2>/dev/null; then
        ok "Compiled mpris-scroll C helper."
      else
        warn "mpris-scroll compile failed; falling back to the .sh script."
      fi
    else
      warn "libplayerctl dev headers missing; skipping mpris-scroll build."
    fi
  fi

  # 3.7 hyprlock wallpaper symlink
  local current_wall
  current_wall="$(find "$WALL_TARGET" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -n1 || true)"
  if [[ -n "$current_wall" ]]; then
    ln -sf "$current_wall" "$HYPR/current_wallpaper" 2>/dev/null \
      && ok "hyprlock current_wallpaper -> $(basename "$current_wall")" \
      || warn "Could not symlink current_wallpaper."
  else
    warn "No wallpapers found; run the wppicker after first boot."
  fi
}

# -----------------------------------------------------------------------------
# 4. MATUGEN (colors + wallpaper)
# -----------------------------------------------------------------------------
run_matugen() {
  info "Generating colors with Matugen..."

  local wall=""
  wall="$(find "$WALL_TARGET" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -n1 || true)"
  if [[ -z "$wall" ]]; then
    warn "No wallpaper available - skipping matugen. Run 'matugen image <wall>' later."
    return 0
  fi

  # make sure a wallpaper daemon is running (swww package on Fedora)
  if ! pgrep -x swww-daemon >/dev/null 2>&1; then
    ( swww-daemon >/dev/null 2>&1 & ) || true
    sleep 0.5
  fi

  # matugen 3.x (Rust) uses '--prefer lightness' with a space, older used '='.
  local prefer=""
  if matugen --help 2>&1 | grep -q -- "--prefer"; then
    prefer="--prefer lightness"
  fi

  if retry_step "matugen image $wall" 2 matugen image $prefer "$wall"; then
    ok "Matugen colors generated for hypr, kitty, waybar, rofi, cava, gtk."
  else
    fail "Matugen failed. Re-run later with: matugen image ~/Pictures/wallpapers/<wall>"
  fi
}

# -----------------------------------------------------------------------------
# 5. PORTAL DARK-MODE FIX (GTK apps under Hyprland)
# -----------------------------------------------------------------------------
portal_darkmode() {
  info "Applying xdg-desktop-portal dark-mode override..."

  local portal_dir="$HOME/.local/share/xdg-desktop-portal/portals"
  local portal_file="$portal_dir/gtk.portal"

  if run_step "mkdir portals" mkdir -p "$portal_dir"; then
    cat > "$portal_file" <<'EOF'
[preferred]
default=gtk
[gtk]
name=gtk
use_in=gnome;Hyprland;wlroots;sway;Wayfire;river
EOF
    ok "gtk.portal override written (UseIn includes Hyprland)."
    # restart portal service on systemd
    systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal-hyprland 2>/dev/null || true
    ok "Portals restarted (best effort)."
  else
    warn "Could not create portal dir; dark-mode fix skipped."
  fi
}

# -----------------------------------------------------------------------------
# 6. SDDM + SESSION
# -----------------------------------------------------------------------------
enable_sddm() {
  info "Enabling SDDM display manager..."

  if command -v sddm >/dev/null 2>&1; then
    if retry_step "enable sddm" 2 sudo systemctl enable --now sddm; then
      ok "SDDM enabled. Both Hyprland and Plasma sessions should be listed at login."
    else
      warn "Could not enable sddm. Start Hyprland from a TTY with: Hyprland"
    fi
  else
    warn "sddm not installed; skipping (start Hyprland from TTY or use another DM)."
  fi
}

# -----------------------------------------------------------------------------
# 7. SUMMARY
# -----------------------------------------------------------------------------
summary() {
  info "SETUP COMPLETE. Log written to: $LOG_FILE"
  warn "If any step failed above, review the log and re-run the specific command."
  printf '  - Confirm monitor line: %s/hypr/hyprland.lua\n' "$HOME_CONFIG"
  printf '  - Reboot, pick Hyprland at SDDM login (Plasma remains as fallback).\n'
  printf '  - Wallpaper picker: SUPER + W\n'
  printf '  - Clipboard history: SUPER + V\n'
  printf '  - Backups: %s\n' "$BACKUP_DIR"
  printf '  - Full log: %s\n' "$LOG_FILE"
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

  info "Logging to: $LOG_FILE"

  (( pkg_install )) && install_packages
  (( do_copy )) && copy_dotfiles
  (( do_copy )) && fixes
  (( do_copy )) && run_matugen
  (( do_copy )) && portal_darkmode
  enable_sddm
  summary
}

main "$@"