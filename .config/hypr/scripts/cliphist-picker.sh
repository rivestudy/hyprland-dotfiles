#!/bin/zsh
# cliphist-picker: rofi clipboard history with image thumbnails
# Requires: cliphist, wl-clipboard, rofi, ImageMagick (magick)
# Usage: bound to SUPER+V in keybinds.lua

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

build_input() {
    local line desc thumb dims imgid
    while IFS=$'\t' read -r imgid desc; do
        if [[ "$desc" == *"binary data"* ]]; then
            thumb="$tmpdir/thumb-$imgid.png"
            if printf '%s\t%s\n' "$imgid" "$desc" | cliphist decode | magick - -resize 48x48 "$thumb" 2>/dev/null; then
                # keep id prefix (decode needs it), label with dimensions, add icon hint
                dims="${desc##*png }"
                dims="${dims%% *}"
                printf '%s\t󰋼  Image %s\0icon\x1f%s\n' "$imgid" "${dims%%]]*}" "$thumb"
            else
                printf '%s\t%s\n' "$imgid" "$desc"
            fi
        else
            printf '%s\t%s\n' "$imgid" "$desc"
        fi
    done < <(cliphist list)
}

# rofi returns the selected row; cliphist decode extracts the id prefix itself
sel="$(build_input | rofi -dmenu -p 'Clipboard' -show-icons -i)"

[[ -z "$sel" ]] && exit 0

printf '%s\n' "$sel" | cliphist decode | wl-copy