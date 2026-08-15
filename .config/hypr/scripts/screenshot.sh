#!/bin/zsh
# Region screenshot: copy to clipboard AND save to disk
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"
grim -g "$(slurp)" - | tee "$file" | wl-copy