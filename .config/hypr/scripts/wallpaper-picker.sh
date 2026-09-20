#!/usr/bin/env bash
# =============================================================================
# Wallpaper Picker Launcher: Launches 3D Tilted Carousel Picker
# (or fallback to Rofi with --rofi)
# =============================================================================

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
SYMLINK_PATH="$HOME/.config/hypr/current_wallpaper"

if [[ "$1" == "--rofi" ]]; then
    cd "$WALLPAPER_DIR" || exit 1
    IFS=$'\n'
    SELECTED_WALL=$(for a in $(ls -t *.jpg *.png *.gif *.jpeg 2>/dev/null); do echo -en "$a\0icon\x1f$a\n"; done | rofi -dmenu -p "")
    [ -z "$SELECTED_WALL" ] && exit 1
    SELECTED_PATH="$WALLPAPER_DIR/$SELECTED_WALL"

    matugen image --prefer=lightness "$SELECTED_PATH"
    mkdir -p "$(dirname "$SYMLINK_PATH")"
    ln -sf "$SELECTED_PATH" "$SYMLINK_PATH"
    exit 0
fi

# Launch 3D Tilted Animated Carousel
python3 "$SCRIPTS_DIR/wallpaper-carousel.py"
