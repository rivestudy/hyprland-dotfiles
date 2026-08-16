#!/usr/bin/env bash
# =============================================================================
# Quick Audio Output Switcher (Speakers / HDMI / Bluetooth / USB)
# =============================================================================
set -euo pipefail

ROFI_CONFIG="$HOME/.config/rofi/config.rasi"

# Helper to move all active audio streams to the current default sink
move_streams_to_default() {
    local default_sink
    default_sink="$(pactl get-default-sink 2>/dev/null || true)"
    if [[ -n "$default_sink" ]]; then
        pactl list short sink-inputs 2>/dev/null | awk '{print $1}' | while read -r stream_id; do
            [[ -n "$stream_id" ]] && pactl move-sink-input "$stream_id" "$default_sink" 2>/dev/null || true
        done
    fi
}

# Discover devices and current state
PY_SCRIPT="
import subprocess, json

# Sinks
p = subprocess.Popen(['pactl', '-f', 'json', 'list', 'sinks'], stdout=subprocess.PIPE, text=True)
out_sinks, _ = p.communicate()
sinks = json.loads(out_sinks) if out_sinks.strip() else []

# Current default sink
try:
    def_sink = subprocess.check_output(['pactl', 'get-default-sink'], text=True).strip()
except Exception:
    def_sink = ''

# Cards for profile detection (e.g. HDMI vs Analog on Intel HDA)
p_card = subprocess.Popen(['pactl', '-f', 'json', 'list', 'cards'], stdout=subprocess.PIPE, text=True)
out_cards, _ = p_card.communicate()
cards = json.loads(out_cards) if out_cards.strip() else []

results = []

# Check built-in card profiles (HDMI & Analog)
for c in cards:
    card_name = c.get('name', '')
    active_prof = c.get('active_profile', {}).get('name', '')
    profiles = c.get('profiles', {})
    
    # Check if card supports HDMI output
    has_hdmi = any('hdmi' in p_name for p_name in profiles.keys())
    has_analog = any('analog' in p_name for p_name in profiles.keys())
    
    if has_analog:
        is_active = ('analog' in active_prof and ('analog' in def_sink or not def_sink))
        results.append({
            'type': 'analog_card',
            'card': card_name,
            'profile': 'output:analog-stereo+input:analog-stereo' if 'output:analog-stereo+input:analog-stereo' in profiles else 'output:analog-stereo',
            'label': '󰋋 Built-in Speakers / Headphones (Analog)',
            'active': is_active
        })
        
    if has_hdmi:
        is_active = ('hdmi' in active_prof and 'hdmi' in def_sink)
        # Find description if available
        desc = 'External Display / TV (HDMI)'
        for port in c.get('ports', []):
            if 'hdmi' in port.get('name', '') and port.get('product', ''):
                desc = f\"External Display ({port.get('product')})\"
        results.append({
            'type': 'hdmi_card',
            'card': card_name,
            'profile': 'output:hdmi-stereo+input:analog-stereo' if 'output:hdmi-stereo+input:analog-stereo' in profiles else 'output:hdmi-stereo',
            'label': f'󰓃 {desc}',
            'active': is_active
        })

# Check other standalone sinks (Bluetooth, USB DAC, etc.)
for s in sinks:
    s_name = s.get('name', '')
    if 'pci-0000' in s_name:
        continue # handled by card profiles above
    s_desc = s.get('description', s_name)
    is_active = (s_name == def_sink)
    if 'bluez' in s_name:
        icon = '󰂯'
    elif 'usb' in s_name.lower():
        icon = '󰓃'
    else:
        icon = '󰕾'
    results.append({
        'type': 'sink',
        'sink_name': s_name,
        'label': f'{icon} {s_desc}',
        'active': is_active
    })

print(json.dumps(results))
"

DEV_JSON="$(python3 -c "$PY_SCRIPT")"

# Generate menu lines
MENU_LINES="$(python3 -c "
import json
data = json.loads('''$DEV_JSON''')
for i, d in enumerate(data):
    marker = ' [ACTIVE]' if d.get('active') else ''
    print(f\"{d.get('label')}{marker}\")
")"

if [[ -z "$MENU_LINES" ]]; then
    notify-send -u critical "Audio Switcher" "No audio output devices found."
    exit 1
fi

CHOICE="$(echo -e "$MENU_LINES" | rofi -i -dmenu -config "$ROFI_CONFIG" -mesg "Select Audio Output Device")"

if [[ -z "$CHOICE" ]]; then
    exit 0
fi

# Clean selection
CLEAN_CHOICE="$(echo "$CHOICE" | sed 's/ \[ACTIVE\]//')"

# Apply the selection
python3 -c "
import json, subprocess, sys

data = json.loads('''$DEV_JSON''')
choice = '''$CLEAN_CHOICE'''.strip()

target = None
for d in data:
    if d.get('label', '').strip() == choice:
        target = d
        break

if not target:
    sys.exit(0)

t_type = target.get('type')
if t_type in ('analog_card', 'hdmi_card'):
    card = target.get('card')
    profile = target.get('profile')
    subprocess.run(['pactl', 'set-card-profile', card, profile], check=False)
    # Set matching sink as default
    out_sinks = subprocess.check_output(['pactl', '-f', 'json', 'list', 'sinks'], text=True)
    sinks = json.loads(out_sinks) if out_sinks.strip() else []
    target_match = 'hdmi' if t_type == 'hdmi_card' else 'analog'
    for s in sinks:
        if target_match in s.get('name', ''):
            subprocess.run(['pactl', 'set-default-sink', s.get('name')], check=False)
            break
elif t_type == 'sink':
    sink_name = target.get('sink_name')
    subprocess.run(['pactl', 'set-default-sink', sink_name], check=False)

label = target.get('label', '')
subprocess.run(['notify-send', '-u', 'low', '-i', 'audio-speakers', 'Audio Switcher', f'Audio Output set to: {label}'], check=False)
"

# Move all existing running streams to new default sink immediately
move_streams_to_default
