#!/usr/bin/env bash
# =============================================================================
# Hyprland Display Mode Switcher (Mirror / Extend / Single Screen)
# =============================================================================
set -euo pipefail

ROFI_CONFIG="$HOME/.config/rofi/config.rasi"

# Detect monitors using hyprctl
get_monitors() {
    hyprctl -j monitors all 2>/dev/null || true
}

MONITORS_JSON="$(get_monitors)"

if [[ -z "$MONITORS_JSON" || "$MONITORS_JSON" == "[]" ]]; then
    notify-send -u critical "Display Manager" "Could not detect any monitors from Hyprland."
    exit 1
fi

# Detect internal (laptop) display
INTERNAL_MON="$(python3 -c "
import json, sys
data = json.loads('''$MONITORS_JSON''')
internal = None
for m in data:
    name = m.get('name', '')
    if name.startswith('eDP') or name.startswith('LVDS'):
        internal = name
        break
if not internal and data:
    internal = data[0].get('name', 'eDP-1')
print(internal or 'eDP-1')
")"

# Detect external display(s)
EXTERNAL_MONS="$(python3 -c "
import json
data = json.loads('''$MONITORS_JSON''')
exts = [m.get('name') for m in data if m.get('name') and m.get('name') != '$INTERNAL_MON']
print(' '.join(exts))
")"

# Primary external monitor
FIRST_EXT="$(echo "$EXTERNAL_MONS" | awk '{print $1}')"

if [[ -z "$FIRST_EXT" ]]; then
    # No external monitor connected
    OPTIONS="󰑓 Reset Laptop Display (auto, 1x)\n⚙️ Toggle Laptop Display Off/On"
    CHOICE="$(echo -e "$OPTIONS" | rofi -i -dmenu -config "$ROFI_CONFIG" -mesg "Display: No external monitor detected ($INTERNAL_MON)")"
    
    case "$CHOICE" in
        *"Reset Laptop Display"*)
            hyprctl keyword monitor "$INTERNAL_MON,preferred,0x0,1"
            notify-send -u low "Display Manager" "Reset $INTERNAL_MON to default"
            ;;
    esac
    exit 0
fi

# Options when external display is connected
EXT_DESC="$(python3 -c "
import json
data = json.loads('''$MONITORS_JSON''')
for m in data:
    if m.get('name') == '$FIRST_EXT':
        print(m.get('description', m.get('model', '$FIRST_EXT')))
        break
")"

OPTIONS="󰍹 Mirror Displays (Duplicate Screen)
󰍹 Extend Right ($FIRST_EXT on Right)
󰍹 Extend Left ($FIRST_EXT on Left)
󰍹 Extend Above ($FIRST_EXT on Top)
󰍹 Extend Below ($FIRST_EXT on Bottom)
󰌢 Laptop Display Only (Turn off $FIRST_EXT)
󰍹 External Display Only (Turn off $INTERNAL_MON)
󰑓 Reset All Displays (Auto Detect)"

CHOICE="$(echo -e "$OPTIONS" | rofi -i -dmenu -config "$ROFI_CONFIG" -mesg "Display Setup: $INTERNAL_MON + $FIRST_EXT ($EXT_DESC)")"

if [[ -z "$CHOICE" ]]; then
    exit 0
fi

case "$CHOICE" in
    *"Mirror Displays"*)
        hyprctl keyword monitor "$INTERNAL_MON,preferred,0x0,1"
        hyprctl keyword monitor "$FIRST_EXT,preferred,auto,1,mirror,$INTERNAL_MON"
        notify-send -u low -i video-display "Display Manager" "Mirrored $INTERNAL_MON to $FIRST_EXT"
        ;;
    *"Extend Right"*)
        hyprctl keyword monitor "$INTERNAL_MON,preferred,0x0,1"
        hyprctl keyword monitor "$FIRST_EXT,preferred,auto-right,1"
        notify-send -u low -i video-display "Display Manager" "Extended desktop to the right ($FIRST_EXT)"
        ;;
    *"Extend Left"*)
        hyprctl keyword monitor "$INTERNAL_MON,preferred,auto,1"
        hyprctl keyword monitor "$FIRST_EXT,preferred,auto-left,1"
        notify-send -u low -i video-display "Display Manager" "Extended desktop to the left ($FIRST_EXT)"
        ;;
    *"Extend Above"*)
        hyprctl keyword monitor "$INTERNAL_MON,preferred,0x0,1"
        hyprctl keyword monitor "$FIRST_EXT,preferred,auto-up,1"
        notify-send -u low -i video-display "Display Manager" "Extended desktop above ($FIRST_EXT)"
        ;;
    *"Extend Below"*)
        hyprctl keyword monitor "$INTERNAL_MON,preferred,0x0,1"
        hyprctl keyword monitor "$FIRST_EXT,preferred,auto-down,1"
        notify-send -u low -i video-display "Display Manager" "Extended desktop below ($FIRST_EXT)"
        ;;
    *"Laptop Display Only"*)
        hyprctl keyword monitor "$FIRST_EXT,disable"
        hyprctl keyword monitor "$INTERNAL_MON,preferred,0x0,1"
        notify-send -u low -i video-display "Display Manager" "Enabled $INTERNAL_MON only ($FIRST_EXT disabled)"
        ;;
    *"External Display Only"*)
        hyprctl keyword monitor "$INTERNAL_MON,disable"
        hyprctl keyword monitor "$FIRST_EXT,preferred,0x0,1"
        notify-send -u low -i video-display "Display Manager" "Enabled $FIRST_EXT only ($INTERNAL_MON disabled)"
        ;;
    *"Reset All Displays"*)
        hyprctl keyword monitor ",preferred,auto,1"
        notify-send -u low -i video-display "Display Manager" "Reset all monitors to default auto layout"
        ;;
esac
