#!/usr/bin/env python3
# Waybar weather module - wttr.in based
# Outputs JSON for the "custom/weather" module (return-type json)
import json
import sys
import urllib.parse
import urllib.request

LOCATION = "slawi"  # empty = auto-detect from IP; set e.g. "Bandung" to pin it

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def main():
    if LOCATION:
        url = f"https://wttr.in/{urllib.parse.quote(LOCATION)}?format=j1"
    else:
        url = "https://wttr.in/?format=j1"
    data = fetch(url)

    current = data["current_condition"][0]
    temp = current["temp_C"]
    feel = current["FeelsLikeC"]
    code = current["weatherCode"]
    desc = current["weatherDesc"][0]["value"] if current.get("weatherDesc") else "Unknown"
    try:
        hh = int(current.get("observation_time", "").split(":")[0])
    except (ValueError, IndexError):
        hh = 12
    is_day = 6 <= hh < 18

    icons = {
        "113": "󰖙",  # sunny
        "116": "󰖕",  # partly cloudy
        "119": "󰖐",  # cloudy
        "122": "󰖐",  # overcast
        "143": "󰜖",  # mist
        "176": "󰖖",  # patchy rain
        "179": "󰖖",  # patchy snow
        "182": "󰖖",  # patchy sleet
        "185": "󰖖",  # patchy freezing drizzle
        "200": "󰖕",  # thundery outbreaks
        "227": "󰖖",  # blowing snow
        "230": "󰖖",  # blizzard
        "248": "󰜖",  # fog
        "260": "󰜖",  # freezing fog
        "263": "󰖖",  # patchy light drizzle
        "266": "󰖖",  # light drizzle
        "281": "󰖖",  # freezing drizzle
        "284": "󰖖",  # heavy freezing drizzle
        "293": "󰖖",  # patchy light rain
        "296": "󰖖",  # light rain
        "299": "󰖖",  # moderate rain at times
        "302": "󰖖",  # moderate rain
        "305": "󰖖",  # heavy rain at times
        "308": "󰖖",  # heavy rain
        "311": "󰖖",  # light freezing rain
        "314": "󰖖",  # moderate/heavy freezing rain
        "317": "󰖖",  # light sleet
        "320": "󰖖",  # moderate sleet
        "323": "󰖖",  # patchy light snow
        "326": "󰖖",  # light snow
        "329": "󰖖",  # patchy moderate snow
        "332": "󰖖",  # moderate snow
        "335": "󰖖",  # patchy heavy snow
        "338": "󰖖",  # heavy snow
        "350": "󰖖",  # ice pellets
        "353": "󰖖",  # light rain shower
        "356": "󰖖",  # moderate/heavy rain shower
        "359": "󰖖",  # torrential rain shower
        "362": "󰖖",  # light sleet showers
        "365": "󰖖",  # moderate/heavy sleet showers
        "368": "󰖖",  # light snow showers
        "371": "󰖖",  # moderate/heavy snow showers
        "374": "󰖖",  # light showers of ice pellets
        "377": "󰖖",  # moderate/heavy showers of ice pellets
        "386": "󰖕",  # patchy light rain with thunder
        "389": "󰖕",  # moderate/heavy rain with thunder
        "392": "󰖕",  # patchy light snow with thunder
        "395": "󰖕",  # moderate/heavy snow with thunder
    }
    icon = icons.get(code, "󰖙")
    if not is_day and code == "113":
        icon = "󰖔"

    humidity = current["humidity"]
    wind = current["windspeedKmph"]
    feels = f" (feels {feel}°)" if feel != temp else ""

    try:
        area = data["nearest_area"][0]
        loc_name = area["areaName"][0]["value"]
        region = area["region"][0]["value"]
        country = area["country"][0]["value"]
        if loc_name.lower() in country.lower():
            location = loc_name
        else:
            location = f"{loc_name}, {country}"
    except (KeyError, IndexError):
        location = LOCATION or "Your location"

    text = f"{icon} {temp}°C"
    tooltip = f"{location}\n{desc}\nFeels like {feel}°C\nHumidity: {humidity}%\nWind: {wind} km/h"
    out = {"text": text, "tooltip": tooltip, "class": "weather", "alt": desc}
    print(json.dumps(out))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Keep the module silent on errors, but log to stderr for debuggability
        print(f"Weather error: {e}", file=sys.stderr)
        print(json.dumps({"text": "", "tooltip": f"Weather unavailable: {e}", "class": "weather"}))
        sys.exit(0)
