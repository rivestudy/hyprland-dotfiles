#!/usr/bin/env python3
# =============================================================================
# Quick Audio Output Switcher (Speakers / HDMI / USB DAC / Bluetooth)
# =============================================================================
import subprocess
import json
import re
import time
import os
import sys

ROFI_CONFIG = os.path.expanduser("~/.config/rofi/config.rasi")

def get_audio_devices():
    status_out = subprocess.check_output(['wpctl', 'status'], text=True)
    cards_out = subprocess.check_output(['pactl', '-f', 'json', 'list', 'cards'], text=True)
    cards = json.loads(cards_out) if cards_out.strip() else []
    
    sinks = []
    in_sinks = False
    for line in status_out.splitlines():
        if 'Sinks:' in line:
            in_sinks = True
            continue
        if in_sinks:
            if 'Sources:' in line or 'Filters:' in line or 'Streams:' in line or line.startswith(' ├─') or line.startswith(' └─'):
                break
            m = re.search(r'([* ])\s+(\d+)\.\s+(.*?)\s+\[vol:\s*([\d\.]+)\]', line)
            if m:
                is_def = (m.group(1) == '*')
                node_id = int(m.group(2))
                desc = m.group(3).strip()
                vol = int(round(float(m.group(4)) * 100))
                
                icon = '󰓃'
                if 'hdmi' in desc.lower() or 'digital' in desc.lower():
                    icon = '󰓃'
                elif 'cx31993' in desc.lower() or 'usb' in desc.lower() or 'hifi' in desc.lower():
                    icon = '󰓃'
                elif 'speaker' in desc.lower() or 'analog' in desc.lower():
                    icon = '󰋋'
                elif 'bluez' in desc.lower() or 'bluetooth' in desc.lower():
                    icon = '󰂯'
                    
                sinks.append({
                    'id': node_id,
                    'desc': f"{icon} {desc}",
                    'vol': vol,
                    'is_default': is_def,
                    'type': 'sink'
                })
                
    # Also check if built-in card has an alternate inactive profile (e.g. Analog vs HDMI)
    for c in cards:
        card_name = c.get('name', '')
        active_prof = c.get('active_profile', '')
        profiles = c.get('profiles', {})
        
        # If currently HDMI, offer Analog Stereo (Speakers)
        if 'hdmi' in active_prof and 'output:analog-stereo+input:analog-stereo' in profiles:
            sinks.append({
                'id': None,
                'card': card_name,
                'profile': 'output:analog-stereo+input:analog-stereo',
                'desc': '󰋋 Built-in Audio Analog Stereo (Speakers)',
                'vol': None,
                'is_default': False,
                'type': 'card_profile'
            })
        # If currently Analog, offer HDMI
        elif 'analog' in active_prof and 'output:hdmi-stereo+input:analog-stereo' in profiles:
            sinks.append({
                'id': None,
                'card': card_name,
                'profile': 'output:hdmi-stereo+input:analog-stereo',
                'desc': '󰓃 Built-in Audio Digital Stereo (HDMI / TV)',
                'vol': None,
                'is_default': False,
                'type': 'card_profile'
            })
            
    return sinks

def find_target(devices, clean_choice):
    # 1. Exact match
    for d in devices:
        if d.get('desc', '').strip() == clean_choice:
            return d
    # 2. Substring match
    for d in devices:
        if clean_choice in d.get('desc', ''):
            return d
    # 3. Keyword match
    c_low = clean_choice.lower()
    if 'cx31993' in c_low or 'usb' in c_low:
        for d in devices:
            if 'cx31993' in d.get('desc', '').lower() or 'usb' in d.get('desc', '').lower():
                return d
    if 'hdmi' in c_low:
        for d in devices:
            if 'hdmi' in d.get('desc', '').lower() or 'hdmi' in d.get('profile', '').lower():
                return d
    if 'speaker' in c_low or 'analog' in c_low:
        for d in devices:
            if ('analog' in d.get('desc', '').lower() or 'speaker' in d.get('desc', '').lower()) and 'cx31993' not in d.get('desc', '').lower():
                return d
    if 'bluez' in c_low or 'bluetooth' in c_low:
        for d in devices:
            if 'bluez' in d.get('desc', '').lower() or 'bluetooth' in d.get('desc', '').lower():
                return d
    return None

def apply_device(target):
    t_type = target.get('type')
    sink_id = target.get('id')
    
    if t_type == 'card_profile':
        card = target.get('card')
        profile = target.get('profile')
        subprocess.run(['pactl', 'set-card-profile', card, profile], check=False)
        time.sleep(0.2)
        status_out = subprocess.check_output(['wpctl', 'status'], text=True)
        in_sinks = False
        target_term = 'hdmi' if 'hdmi' in profile else 'analog'
        for line in status_out.splitlines():
            if 'Sinks:' in line:
                in_sinks = True
                continue
            if in_sinks:
                if 'Sources:' in line or 'Filters:' in line or 'Streams:' in line:
                    break
                m = re.search(r'([* ])\s+(\d+)\.\s+(.*?)\s+\[vol:\s*([\d\.]+)\]', line)
                if m:
                    n_id = int(m.group(2))
                    d_text = m.group(3).lower()
                    if target_term in d_text and 'cx31993' not in d_text:
                        sink_id = n_id
                        break
                        
    if sink_id:
        subprocess.run(['wpctl', 'set-default', str(sink_id)], check=False)
        
    try:
        def_sink_name = subprocess.check_output(['pactl', 'get-default-sink'], text=True).strip()
        inputs_out = subprocess.check_output(['pactl', 'list', 'short', 'sink-inputs'], text=True)
        for line in inputs_out.splitlines():
            parts = line.split()
            if parts:
                stream_id = parts[0]
                subprocess.run(['pactl', 'move-sink-input', stream_id, def_sink_name], check=False)
    except Exception:
        pass
        
    desc = target.get('desc', '')
    subprocess.run(['notify-send', '-u', 'low', '-i', 'audio-speakers', 'Audio Output Switcher', f'Switched to: {desc}'], check=False)

def main():
    devices = get_audio_devices()
    if not devices:
        subprocess.run(['notify-send', '-u', 'critical', 'Audio Switcher', 'No audio outputs detected.'], check=False)
        return
        
    menu_lines = []
    for d in devices:
        vol_str = f" ({d['vol']}%)" if d.get('vol') is not None else ""
        active_str = " [ACTIVE]" if d.get('is_default') else ""
        menu_lines.append(f"{d['desc']}{vol_str}{active_str}")
        
    menu_input = "\n".join(menu_lines)
    
    # Run rofi
    cmd = ['rofi', '-i', '-dmenu', '-config', ROFI_CONFIG, '-mesg', 'Select Audio Output (Volume saved per device)']
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    stdout, _ = p.communicate(input=menu_input)
    
    choice = stdout.strip()
    if not choice:
        return
        
    clean_choice = re.sub(r'\s*\(\d+%\)', '', choice)
    clean_choice = clean_choice.replace(' [ACTIVE]', '').strip()
    
    target = find_target(devices, clean_choice)
    if target:
        apply_device(target)

if __name__ == '__main__':
    main()
