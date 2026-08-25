#!/usr/bin/env python3
# =============================================================================
# Waybar Weather Module & Interactive Forecast / Settings Menu
# Uses wttr.in with rich Pango markup popdown tooltip and robust Nerd Font icons
# =============================================================================
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

CONFIG_FILE = os.path.expanduser("~/.config/hypr/weather_location.json")
ROFI_CONFIG = os.path.expanduser("~/.config/rofi/config.rasi")

# Standard Nerd Font Weather Glyphs (MDI & Weather Icons, 100% universal support)
CODE_MAP = {
    # Sunny / Clear
    "113": ("󰖙", "󰖔"),
    # Partly cloudy
    "116": ("󰖕", "󰼱"),
    # Cloudy / Overcast
    "119": ("󰖐", "󰖐"),
    "122": ("󰖐", "󰖐"),
    # Mist / Fog / Haze
    "143": ("󰖑", "󰖑"),
    "248": ("󰖑", "󰖑"),
    "260": ("󰖑", "󰖑"),
    # Patchy rain / Drizzle
    "176": ("󰖖", "󰖖"),
    "185": ("󰖖", "󰖖"),
    "263": ("󰖖", "󰖖"),
    "266": ("󰖖", "󰖖"),
    "281": ("󰖖", "󰖖"),
    "284": ("󰖗", "󰖗"),
    "293": ("󰖖", "󰖖"),
    "296": ("󰖖", "󰖖"),
    "299": ("󰖖", "󰖖"),
    "302": ("󰖖", "󰖖"),
    "353": ("󰖖", "󰖖"),
    # Heavy rain / Torrential
    "305": ("󰖗", "󰖗"),
    "308": ("󰖗", "󰖗"),
    "356": ("󰖗", "󰖗"),
    "359": ("󰖗", "󰖗"),
    # Thunderstorms
    "200": ("󰖒", "󰖒"),
    "386": ("󰖓", "󰖓"),
    "389": ("󰖓", "󰖓"),
    "392": ("󰖓", "󰖓"),
    "395": ("󰖓", "󰖓"),
    # Snow
    "179": ("󰼶", "󰼶"),
    "227": ("󰼶", "󰼶"),
    "323": ("󰼶", "󰼶"),
    "326": ("󰼶", "󰼶"),
    "329": ("󰼶", "󰼶"),
    "332": ("󰼶", "󰼶"),
    "368": ("󰼶", "󰼶"),
    # Heavy Snow & Blizzard
    "230": ("󰼷", "󰼷"),
    "335": ("󰼷", "󰼷"),
    "338": ("󰼷", "󰼷"),
    "371": ("󰼷", "󰼷"),
    # Sleet & Hail
    "182": ("󰙾", "󰙾"),
    "311": ("󰙾", "󰙾"),
    "314": ("󰙾", "󰙾"),
    "317": ("󰙾", "󰙾"),
    "320": ("󰙾", "󰙾"),
    "350": ("󰙾", "󰙾"),
    "362": ("󰙾", "󰙾"),
    "365": ("󰙾", "󰙾"),
    "374": ("󰙾", "󰙾"),
    "377": ("󰙾", "󰙾"),
}

def get_weather_icon(code, desc_text="", is_day=True):
    desc = desc_text.lower()

    # 1. Keyword overrides for specific descriptions
    if "thunder" in desc or "lightning" in desc or "storm" in desc:
        if "rain" in desc or "shower" in desc:
            return "󰖓"
        return "󰖒"
    if "tornado" in desc or "hurricane" in desc:
        return "󰼸"
    if "blizzard" in desc or "heavy snow" in desc:
        return "󰼷"
    if "snow" in desc or "flurries" in desc:
        return "󰼶"
    if "sleet" in desc or "ice pellets" in desc or "hail" in desc or "freezing rain" in desc:
        return "󰙾"
    if "mist" in desc or "fog" in desc or "haze" in desc or "smoke" in desc or "smoky" in desc or "dust" in desc or "sand" in desc:
        return "󰖑"
    if "heavy rain" in desc or "torrential" in desc or "downpour" in desc:
        return "󰖗"
    if "rain" in desc or "drizzle" in desc or "shower" in desc:
        return "󰖖"
    if "overcast" in desc or "cloudy" in desc:
        if "partly" in desc:
            return "󰖕" if is_day else "󰼱"
        return "󰖐"
    if "sunny" in desc or "clear" in desc:
        return "󰖙" if is_day else "󰖔"

    # 2. Weather Code lookup
    if code in CODE_MAP:
        d_icon, n_icon = CODE_MAP[code]
        return d_icon if is_day else n_icon

    return "󰖙" if is_day else "󰖔"

def check_is_day(sunrise_str, sunset_str):
    try:
        now = datetime.datetime.now().time()
        sr = datetime.datetime.strptime(sunrise_str.strip(), "%I:%M %p").time()
        ss = datetime.datetime.strptime(sunset_str.strip(), "%I:%M %p").time()
        return sr <= now <= ss
    except Exception:
        hour = datetime.datetime.now().hour
        return 6 <= hour < 18

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"location": "slawi", "unit": "C"}

def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)

def fetch_weather(location=None):
    if location and location.lower() != "auto":
        url = f"https://wttr.in/{urllib.parse.quote(location)}?format=j1"
    else:
        url = "https://wttr.in/?format=j1"
    req = urllib.request.Request(url, headers={"User-Agent": "curl"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)

def signal_waybar():
    # Signal waybar custom/weather on SIGRTMIN+8 (34 + 8 = 42)
    subprocess.run(["pkill", "-42", "waybar"], check=False)

def waybar_output():
    cfg = load_config()
    loc = cfg.get("location", "").strip()
    data = fetch_weather(loc)

    current = data["current_condition"][0]
    temp = current["temp_C"]
    feel = current["FeelsLikeC"]
    code = current["weatherCode"]
    desc = current["weatherDesc"][0]["value"] if current.get("weatherDesc") else "Unknown"
    humidity = current.get("humidity", "")
    wind = current.get("windspeedKmph", "")
    uv = current.get("uvIndex", "")

    # Astronomy (sunrise / sunset)
    weather_days = data.get("weather", [])
    sr, ss = "", ""
    if weather_days:
        today_astro = weather_days[0].get("astronomy", [{}])[0]
        sr = today_astro.get("sunrise", "")
        ss = today_astro.get("sunset", "")

    is_day = check_is_day(sr, ss)
    icon = get_weather_icon(code, desc, is_day)

    try:
        area = data["nearest_area"][0]
        loc_name = area["areaName"][0]["value"]
        country = area["country"][0]["value"]
        if loc_name.lower() in country.lower():
            display_loc = loc_name
        else:
            display_loc = f"{loc_name}, {country}"
    except (KeyError, IndexError):
        display_loc = loc if loc and loc.lower() != "auto" else "Your Location"

    # 3-Day Forecast Monospace Table
    forecast_rows = []
    day_labels = ["Today", "Tomorrow", "Day After"]
    for i, w in enumerate(weather_days[:3]):
        d_name = f"{day_labels[i]:<9}"
        d_min = f"{w.get('mintempC', '')}°C"
        d_max = f"{w.get('maxtempC', '')}°C"
        hourly = w.get("hourly", [])
        d_desc = hourly[len(hourly)//2]["weatherDesc"][0]["value"] if hourly else "Clear"
        d_code = hourly[len(hourly)//2].get("weatherCode", "113") if hourly else "113"
        d_ico = get_weather_icon(d_code, d_desc, is_day=True)
        forecast_rows.append(f"{d_name} {d_ico}  {d_min:>3} ~ {d_max:>3}  {d_desc}")

    forecast_table = "\n".join(forecast_rows)
    astro_line = f"🌅 Sunrise: <b>{sr}</b>   🌇 Sunset: <b>{ss}</b>\n\n" if (sr and ss) else ""

    text = f"{icon} {temp}°C"
    tooltip = (
        f"<big><b>📍 {display_loc}</b></big>\n"
        f"<b>{desc}</b>  •  <b>{temp}°C</b> (Feels like {feel}°C)\n\n"
        f"💧 Humidity: <b>{humidity}%</b>   💨 Wind: <b>{wind} km/h</b>   ☀️ UV: <b>{uv}</b>\n"
        f"{astro_line}"
        f"<big><b>3-Day Forecast:</b></big>\n"
        f"<tt><small>{forecast_table}</small></tt>\n\n"
        f"<small><i>Left-Click: ⚙️ Change City / Location Settings</i></small>"
    )

    out = {
        "text": text,
        "tooltip": tooltip,
        "class": "weather",
        "alt": desc
    }
    print(json.dumps(out))

def show_location_menu():
    cfg = load_config()
    current_loc = cfg.get("location", "slawi")

    options = [
        "⚙️  Set Custom City / Location",
        "📍  Auto-Detect Location (by IP)",
        "🔄  Refresh Weather Now",
        "🌐  Open Full Forecast in Browser"
    ]

    menu_input = "\n".join(options)
    cmd = [
        "rofi", "-i", "-dmenu",
        "-config", ROFI_CONFIG,
        "-mesg", f"Weather Settings (Current Location: {current_loc})"
    ]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    stdout, _ = p.communicate(input=menu_input)
    choice = stdout.strip()

    if not choice:
        return

    if "Set Custom City" in choice:
        input_cmd = [
            "rofi", "-dmenu",
            "-config", ROFI_CONFIG,
            "-p", "City Name",
            "-mesg", f"Enter city name (current: '{current_loc}'):"
        ]
        p_in = subprocess.Popen(input_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        new_loc_out, _ = p_in.communicate(input="")
        new_loc = new_loc_out.strip()

        if new_loc:
            try:
                data = fetch_weather(new_loc)
                area = data.get("nearest_area", [{}])[0]
                loc_name = area.get("areaName", [{}])[0].get("value", new_loc)
                country = area.get("country", [{}])[0].get("value", "")
                resolved = f"{loc_name}, {country}" if country else loc_name

                cfg["location"] = new_loc
                save_config(cfg)
                signal_waybar()

                subprocess.run([
                    "notify-send", "-u", "low", "-i", "weather-clear",
                    "Weather Location Updated", f"Location set to: {resolved}"
                ], check=False)
            except Exception as e:
                subprocess.run([
                    "notify-send", "-u", "critical", "-i", "weather-severe-alert",
                    "Location Invalid", f"Could not find weather for '{new_loc}': {e}"
                ], check=False)

    elif "Auto-Detect" in choice:
        cfg["location"] = "auto"
        save_config(cfg)
        signal_waybar()
        subprocess.run([
            "notify-send", "-u", "low", "-i", "weather-clear",
            "Weather Updated", "Location set to Auto-Detect (by IP)"
        ], check=False)

    elif "Refresh Weather" in choice:
        signal_waybar()
        subprocess.run([
            "notify-send", "-u", "low", "-i", "weather-clear",
            "Weather Refreshed", "Weather data updated."
        ], check=False)

    elif "Open Full Forecast" in choice:
        loc_arg = urllib.parse.quote(current_loc) if current_loc and current_loc != "auto" else ""
        subprocess.run(["xdg-open", f"https://wttr.in/{loc_arg}"], check=False)

def main():
    if len(sys.argv) > 1:
        mode = sys.argv[1]
        if mode in ("--menu", "--config", "--settings"):
            show_location_menu()
            return
        elif mode == "--refresh":
            signal_waybar()
            return

    try:
        waybar_output()
    except Exception as e:
        print(f"Weather error: {e}", file=sys.stderr)
        print(json.dumps({"text": "", "tooltip": f"Weather unavailable: {e}", "class": "weather"}))

if __name__ == "__main__":
    main()
