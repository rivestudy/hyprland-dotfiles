#!/usr/bin/env python3
# =============================================================================
# PipeWire 16-Band Equalizer & Audio Enhancer - Click Popup GUI
# Instant 0ms latency real-time slider updates, persistent on screen, close with Esc/toggle
# =============================================================================
import json
import os
import re
import subprocess
import sys
import time

STATE_FILE = os.path.expanduser("~/.config/pipewire/eq16_state.json")
CONF_FILE = os.path.expanduser("~/.config/pipewire/standalone_eq16.conf")
PID_FILE = "/tmp/pipewire-eq16.pid"
GUI_PID_FILE = "/tmp/pipewire-eq16-gui.pid"

FREQS = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000, 20000]
FREQ_LABELS = ["25", "40", "63", "100", "160", "250", "400", "630", "1k", "1.6k", "2.5k", "4k", "6.3k", "10k", "16k", "20k"]

DEFAULT_PRESETS = {
    "Flat": [0.0] * 16,
    "Bass Boost": [7.0, 6.5, 5.5, 4.0, 2.5, 1.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
    "Vocal Clarity": [-2.5, -2.0, -1.0, 0.0, 1.0, 2.0, 3.5, 4.5, 5.0, 4.5, 3.5, 2.0, 1.0, 0.0, -0.5, -1.0],
    "Gaming / Footsteps": [-4.0, -3.0, -2.0, -1.0, 0.0, 1.5, 3.0, 4.0, 5.0, 6.0, 5.5, 4.5, 3.0, 2.0, 1.0, 0.0],
    "Movie / Cinematic": [6.0, 5.5, 4.5, 3.0, 1.5, 0.5, 0.0, 1.0, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.0],
    "Rock & Metal": [5.5, 5.0, 4.0, 2.5, 0.0, -1.5, -1.0, 0.5, 1.5, 2.5, 3.5, 4.0, 4.5, 5.0, 5.0, 4.5],
    "Electronic / EDM": [7.0, 6.5, 5.5, 4.0, 2.0, 0.5, 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 5.5, 6.0, 6.0],
    "Acoustic & Classical": [3.0, 2.5, 2.0, 1.5, 1.0, 0.5, 0.0, 0.0, 1.0, 1.5, 2.0, 3.0, 3.5, 4.0, 4.0, 3.5]
}

CSS_STYLE = b"""
window {
    background-color: #181825;
    border: 2px solid #45475a;
    border-radius: 16px;
}
.header-box {
    padding: 14px 18px 10px 18px;
    border-bottom: 1px solid #313244;
}
.title-label {
    font-size: 15px;
    font-weight: bold;
    color: #cdd6f4;
}
.sub-label {
    font-size: 12px;
    color: #a6adc8;
}
.slider-column {
    padding: 6px 3px;
}
.slider-val {
    font-size: 11px;
    font-weight: bold;
    color: #89b4fa;
}
.slider-freq {
    font-size: 11px;
    font-weight: bold;
    color: #a6adc8;
}
scale trough {
    background-color: #313244;
    border-radius: 4px;
    min-width: 6px;
}
scale highlight {
    background-color: #89b4fa;
    border-radius: 4px;
}
scale slider {
    background-color: #cdd6f4;
    border-radius: 50%;
    min-width: 18px;
    min-height: 18px;
}
scale slider:hover {
    background-color: #b4befe;
}
button {
    background-color: #313244;
    color: #cdd6f4;
    border-radius: 8px;
    border: 1px solid #45475a;
    padding: 6px 14px;
    font-weight: bold;
}
button:hover {
    background-color: #45475a;
}
.close-btn {
    background-color: #f38ba8;
    color: #11111b;
    border-radius: 8px;
    padding: 4px 10px;
    font-weight: bold;
}
.close-btn:hover {
    background-color: #eba0ac;
}
switch {
    border-radius: 12px;
}
switch:checked {
    background-color: #a6e3a1;
}
combobox button {
    background-color: #313244;
    color: #cdd6f4;
    border-radius: 8px;
}
"""

def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "enabled": True,
        "active_preset": "Bass Boost",
        "custom_gains": [0.0] * 16,
        "presets": DEFAULT_PRESETS,
        "device_presets": {}
    }

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)

def is_running():
    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
            return pid
        except Exception:
            try:
                os.remove(PID_FILE)
            except Exception:
                pass
    return None

def stop_eq():
    pid = is_running()
    if pid:
        try:
            os.kill(pid, 15)
            time.sleep(0.15)
        except Exception:
            pass
    if os.path.exists(PID_FILE):
        try:
            os.remove(PID_FILE)
        except Exception:
            pass

def find_node_id(node_name):
    try:
        out = subprocess.check_output(["pw-cli", "list-objects", "Node"], text=True)
        blocks = out.split("\tid ")
        for b in blocks:
            if f'node.name = "{node_name}"' in b:
                m = re.search(r"^(\d+)", b)
                if m:
                    return m.group(1)
    except Exception:
        pass
    return None

def get_physical_default_sink():
    try:
        out = subprocess.check_output(["pw-cli", "list-objects", "Node"], text=True)
        blocks = out.split("\tid ")
        sinks = []
        for b in blocks:
            if 'media.class = "Audio/Sink"' in b and "effect_input" not in b:
                m_id = re.search(r"^(\d+)", b)
                m_name = re.search(r'node\.name = "(.*?)"', b)
                m_desc = re.search(r'node\.description = "(.*?)"', b)
                if m_id and m_desc:
                    node_id = m_id.group(1)
                    desc = m_desc.group(1)
                    name = m_name.group(1) if m_name else ""
                    vol = 0.5
                    try:
                        v_out = subprocess.check_output(["wpctl", "get-volume", node_id], text=True)
                        for part in v_out.split():
                            try:
                                vol = float(part)
                                break
                            except ValueError:
                                pass
                    except Exception:
                        pass
                    sinks.append((node_id, desc, vol, name))
        
        status = subprocess.check_output(["wpctl", "status"], text=True)
        for s in sinks:
            if s[1] in status and "*" in status.split(s[1])[0].splitlines()[-1]:
                return s
        if sinks:
            return sinks[0]
    except Exception:
        pass
    return ("0", "Built-in Audio", 0.5, "default")

def generate_pipewire_conf(gains, device_desc=""):
    nodes = []
    links = []
    for i, (f, g) in enumerate(zip(FREQS, gains)):
        name = f"eq_band_{i+1}"
        if i == 0:
            lbl = "bq_lowshelf"
            q = 1.0
        elif i == len(FREQS) - 1:
            lbl = "bq_highshelf"
            q = 1.0
        else:
            lbl = "bq_peaking"
            q = 1.4
        nodes.append(
            f"                    {{\n"
            f"                        type  = builtin\n"
            f"                        name  = {name}\n"
            f"                        label = {lbl}\n"
            f"                        control = {{ \"Freq\" = {f}.0 \"Q\" = {q} \"Gain\" = {g:.1f} }}\n"
            f"                    }}"
        )
        if i > 0:
            prev_name = f"eq_band_{i}"
            links.append(f"                    {{ output = \"{prev_name}:Out\" input = \"{name}:In\" }}")

    nodes_str = "\n".join(nodes)
    links_str = "\n".join(links)
    clean_desc = device_desc.split("[")[0].strip() if device_desc else "Built-in Audio"

    return f"""# PipeWire Complete 16-Band Equalizer Filter Chain
context.properties = {{
    log.level = 0
}}

context.spa-libs = {{
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}}

context.modules = [
    {{ name = libpipewire-module-rt flags = [ ifexists nofail ] }}
    {{ name = libpipewire-module-protocol-native }}
    {{ name = libpipewire-module-client-node }}
    {{ name = libpipewire-module-adapter }}
    {{ name = libpipewire-module-filter-chain
        args = {{
            node.description = "{clean_desc} (Enhanced)"
            media.name       = "{clean_desc} (Enhanced)"
            filter.graph = {{
                nodes = [
{nodes_str}
                ]
                links = [
{links_str}
                ]
            }}
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {{
                node.name   = "effect_input.eq16"
                media.class = "Audio/Sink"
                node.description = "{clean_desc} (Enhanced)"
            }}
            playback.props = {{
                node.name   = "effect_output.eq16"
                node.passive = true
            }}
        }}
    }}
]
"""

def set_realtime_gains(gains):
    eq_node_id = find_node_id("effect_input.eq16")
    if not eq_node_id:
        return False

    params_parts = []
    for i, g in enumerate(gains):
        params_parts.append(f'"eq_band_{i+1}:Gain" {g:.1f}')
    params_str = " ".join(params_parts)

    cmd = ["pw-cli", "s", str(eq_node_id), "Props", f"{{ params = [ {params_str} ] }}"]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return True

def apply_eq(gains):
    if is_running() and set_realtime_gains(gains):
        return

    phys_id, phys_desc, _, _ = get_physical_default_sink()
    stop_eq()

    conf_content = generate_pipewire_conf(gains, phys_desc)
    os.makedirs(os.path.dirname(CONF_FILE), exist_ok=True)
    with open(CONF_FILE, "w", encoding="utf-8") as f:
        f.write(conf_content)

    p = subprocess.Popen(["pipewire", "-c", CONF_FILE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(PID_FILE, "w") as f:
        f.write(str(p.pid))
    time.sleep(0.35)

    eq_node_id = find_node_id("effect_input.eq16")
    if eq_node_id:
        subprocess.run(["wpctl", "set-volume", eq_node_id, "1.0"], check=False)
        subprocess.run(["wpctl", "set-default", eq_node_id], check=False)

    try:
        subprocess.run(["pactl", "set-default-sink", "effect_input.eq16"], check=False)
        inputs = subprocess.check_output(["pactl", "list", "sink-inputs", "short"], text=True)
        for line in inputs.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                stream_id = parts[0]
                subprocess.run(["pactl", "move-sink-input", stream_id, "effect_input.eq16"], check=False)
    except Exception:
        pass

def waybar_output():
    state = load_state()
    enabled = state.get("enabled", True)
    _, phys_desc, _, device_name = get_physical_default_sink()
    active = state.get("device_presets", {}).get(device_name, state.get("active_preset", "Bass Boost"))
    clean_dev = phys_desc.split("[")[0].strip()

    if enabled and is_running():
        text = f"󱡏 {active}"
        tooltip = (
            f"<b>PipeWire 16-Band Equalizer</b>\n"
            f"Device: <b>{clean_dev}</b>\n"
            f"Status: <b>Active (Real-time)</b>\n"
            f"Preset: <b>{active}</b>\n"
            f"────────────────────────\n"
            f"󰍹 Left Click: Toggle Equalizer Menu\n"
            f"󰐥 Right Click: Toggle Bypass / Enable"
        )
        cls = "active"
    else:
        text = "󱡏 Bypass"
        tooltip = (
            f"<b>PipeWire 16-Band Equalizer</b>\n"
            f"Device: <b>{clean_dev}</b>\n"
            f"Status: <b>Bypassed (Direct Hardware)</b>\n"
            f"────────────────────────\n"
            f"󰍹 Left Click: Toggle Equalizer Menu\n"
            f"󰐥 Right Click: Turn On Equalizer"
        )
        cls = "bypassed"

    print(json.dumps({"text": text, "tooltip": tooltip, "class": cls, "alt": active}))


def launch_gui_popup():
    """Toggle or launch the persistent window (active on click, toggleable)."""
    # Check if GUI is already open -> toggle close it
    if os.path.exists(GUI_PID_FILE):
        try:
            with open(GUI_PID_FILE, "r") as f:
                gui_pid = int(f.read().strip())
            os.kill(gui_pid, 15)
            os.remove(GUI_PID_FILE)
            return
        except Exception:
            try:
                os.remove(GUI_PID_FILE)
            except Exception:
                pass

    with open(GUI_PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gtk, Gdk

    class EqualizerPopup(Gtk.Window):
        def __init__(self):
            super().__init__(title="PipeWire 16-Band Equalizer")
            self.set_wmclass("pipewire-eq-gui", "pipewire-eq-gui")
            self.set_default_size(860, 480)
            self.set_position(Gtk.WindowPosition.CENTER)
            self.set_resizable(False)

            self.state = load_state()
            self.scales = []
            self.val_labels = []
            self.updating_ui = False

            if self.state.get("enabled", True) and not is_running():
                curr_g = self.get_active_gains()
                apply_eq(curr_g)

            main_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            self.add(main_vbox)

            style_provider = Gtk.CssProvider()
            style_provider.load_from_data(CSS_STYLE)
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                style_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

            # Header
            header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
            header.get_style_context().add_class("header-box")
            main_vbox.pack_start(header, False, False, 0)

            title_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            header.pack_start(title_vbox, True, True, 0)

            t_lbl = Gtk.Label(label="󱡏 16-Band Real-Time Equalizer", xalign=0)
            t_lbl.get_style_context().add_class("title-label")
            title_vbox.pack_start(t_lbl, False, False, 0)

            _, phys_desc, _, self.device_name = get_physical_default_sink()
            clean_dev = phys_desc.split("[")[0].strip()
            self.dev_lbl = Gtk.Label(label=f"Active Output: {clean_dev}", xalign=0)
            self.dev_lbl.get_style_context().add_class("sub-label")
            title_vbox.pack_start(self.dev_lbl, False, False, 0)

            preset_lbl = Gtk.Label(label="Preset:")
            header.pack_start(preset_lbl, False, False, 0)

            self.preset_combo = Gtk.ComboBoxText()
            all_presets = list(DEFAULT_PRESETS.keys()) + ["Custom"]
            for p in all_presets:
                self.preset_combo.append_text(p)

            active_p = self.state.get("device_presets", {}).get(self.device_name, self.state.get("active_preset", "Bass Boost"))
            if active_p in all_presets:
                self.preset_combo.set_active(all_presets.index(active_p))
            else:
                self.preset_combo.set_active(1)
            self.preset_combo.connect("changed", self.on_preset_changed)
            header.pack_start(self.preset_combo, False, False, 0)

            reset_btn = Gtk.Button(label="🔄 Reset")
            reset_btn.connect("clicked", self.on_reset_clicked)
            header.pack_start(reset_btn, False, False, 0)

            self.power_switch = Gtk.Switch()
            self.power_switch.set_active(self.state.get("enabled", True) and (is_running() is not None))
            self.power_switch.connect("notify::active", self.on_power_toggled)
            header.pack_start(self.power_switch, False, False, 0)

            close_btn = Gtk.Button(label="✕")
            close_btn.get_style_context().add_class("close-btn")
            close_btn.connect("clicked", lambda b: Gtk.main_quit())
            header.pack_start(close_btn, False, False, 0)

            # Sliders
            sliders_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            sliders_box.set_margin_top(14)
            sliders_box.set_margin_bottom(14)
            sliders_box.set_margin_left(16)
            sliders_box.set_margin_right(16)
            main_vbox.pack_start(sliders_box, True, True, 0)

            curr_gains = self.get_active_gains()

            for i, (freq, label_text) in enumerate(zip(FREQS, FREQ_LABELS)):
                col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
                col.get_style_context().add_class("slider-column")
                sliders_box.pack_start(col, True, True, 0)

                v_lbl = Gtk.Label(label=f"{curr_gains[i]:+.1f}")
                v_lbl.get_style_context().add_class("slider-val")
                self.val_labels.append(v_lbl)
                col.pack_start(v_lbl, False, False, 0)

                adj = Gtk.Adjustment(value=curr_gains[i], lower=-12.0, upper=12.0, step_increment=0.5, page_increment=1.0)
                scale = Gtk.Scale(orientation=Gtk.Orientation.VERTICAL, adjustment=adj)
                scale.set_inverted(True)
                scale.set_draw_value(False)
                scale.set_vexpand(True)
                scale.add_mark(0.0, Gtk.PositionType.LEFT, None)
                scale.connect("value-changed", self.on_slider_changed, i)
                self.scales.append(scale)
                col.pack_start(scale, True, True, 0)

                f_lbl = Gtk.Label(label=label_text)
                f_lbl.get_style_context().add_class("slider-freq")
                col.pack_start(f_lbl, False, False, 0)

            # Close on Escape key
            self.connect("key-press-event", self.on_key_press)
            self.connect("destroy", Gtk.main_quit)

        def on_key_press(self, widget, event):
            if event.keyval == Gdk.KEY_Escape:
                Gtk.main_quit()
                return True
            return False

        def get_active_gains(self):
            dev_presets = self.state.get("device_presets", {})
            active = dev_presets.get(self.device_name, self.state.get("active_preset", "Bass Boost"))
            if active == "Custom":
                return list(self.state.get("custom_gains", [0.0] * 16))
            presets = self.state.get("presets", DEFAULT_PRESETS)
            return list(presets.get(active, DEFAULT_PRESETS["Bass Boost"]))

        def on_slider_changed(self, scale, band_idx):
            if self.updating_ui:
                return
            val = scale.get_value()
            self.val_labels[band_idx].set_text(f"{val:+.1f}")

            self.updating_ui = True
            self.preset_combo.set_active(len(DEFAULT_PRESETS))
            self.updating_ui = False

            gains = [s.get_value() for s in self.scales]
            self.state["custom_gains"] = gains
            self.state["active_preset"] = "Custom"
            self.state["device_presets"][self.device_name] = "Custom"
            save_state(self.state)

            if self.power_switch.get_active():
                set_realtime_gains(gains)

        def on_preset_changed(self, combo):
            if self.updating_ui:
                return
            p_name = combo.get_active_text()
            if not p_name:
                return

            if p_name in DEFAULT_PRESETS:
                gains = DEFAULT_PRESETS[p_name]
            else:
                gains = self.state.get("custom_gains", [0.0] * 16)

            self.updating_ui = True
            for i, scale in enumerate(self.scales):
                scale.set_value(gains[i])
                self.val_labels[i].set_text(f"{gains[i]:+.1f}")
            self.updating_ui = False

            self.state["active_preset"] = p_name
            self.state["device_presets"][self.device_name] = p_name
            save_state(self.state)

            if self.power_switch.get_active():
                set_realtime_gains(gains)

        def on_reset_clicked(self, btn):
            self.preset_combo.set_active(0)

        def on_power_toggled(self, switch, gparam):
            is_on = switch.get_active()
            self.state["enabled"] = is_on
            save_state(self.state)

            if is_on:
                gains = [s.get_value() for s in self.scales]
                apply_eq(gains)
            else:
                stop_eq()
                phys_id, _, _, _ = get_physical_default_sink()
                if phys_id and phys_id != "0":
                    subprocess.run(["wpctl", "set-default", phys_id], check=False)

    try:
        win = EqualizerPopup()
        win.show_all()
        Gtk.main()
    finally:
        if os.path.exists(GUI_PID_FILE):
            try:
                os.remove(GUI_PID_FILE)
            except Exception:
                pass

def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg in ("--waybar", "-w"):
            waybar_output()
            return
        elif arg in ("--start", "-s"):
            state = load_state()
            if state.get("enabled", True):
                _, _, _, dev_name = get_physical_default_sink()
                p_name = state.get("device_presets", {}).get(dev_name, state.get("active_preset", "Bass Boost"))
                if p_name == "Custom":
                    gains = state.get("custom_gains", [0.0] * 16)
                else:
                    gains = state.get("presets", DEFAULT_PRESETS).get(p_name, DEFAULT_PRESETS["Bass Boost"])
                apply_eq(gains)
            return
        elif arg in ("--stop", "-k"):
            stop_eq()
            return
        elif arg in ("--toggle", "-t"):
            state = load_state()
            enabled = not state.get("enabled", True)
            state["enabled"] = enabled
            save_state(state)
            if enabled:
                _, _, _, dev_name = get_physical_default_sink()
                p_name = state.get("device_presets", {}).get(dev_name, state.get("active_preset", "Bass Boost"))
                gains = state.get("presets", DEFAULT_PRESETS).get(p_name, DEFAULT_PRESETS["Bass Boost"])
                apply_eq(gains)
                subprocess.run(["notify-send", "-u", "low", "-i", "audio-speakers", "Equalizer ON", f"Active: {p_name}"], check=False)
            else:
                stop_eq()
                phys_id, _, _, _ = get_physical_default_sink()
                if phys_id and phys_id != "0":
                    subprocess.run(["wpctl", "set-default", phys_id], check=False)
                subprocess.run(["notify-send", "-u", "low", "-i", "audio-speakers", "Equalizer Bypassed", "Hardware Direct"], check=False)
            return

    # Popup GUI trigger (Click to open, click to toggle close)
    launch_gui_popup()

if __name__ == "__main__":
    main()
