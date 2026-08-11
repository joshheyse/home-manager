#!/usr/bin/env python3
"""Render Open-Meteo conditions and NWS alerts as Waybar JSON."""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from html import escape
from zoneinfo import ZoneInfo

UA = "waybar-weather/1.0 (personal bar widget)"
TIMEOUT = 8

# WMO code: Nerd Font glyph, emoji, short description.
WMO = {
    0: ("\ue30d", "☀️", "Clear"),
    1: ("\ue302", "🌤️", "Mostly clear"),
    2: ("\ue302", "⛅", "Partly cloudy"),
    3: ("\ue312", "☁️", "Overcast"),
    45: ("\ue313", "🌫️", "Fog"),
    48: ("\ue313", "🌫️", "Freezing fog"),
    51: ("\ue309", "🌧️", "Light drizzle"),
    53: ("\ue309", "🌧️", "Drizzle"),
    55: ("\ue309", "🌧️", "Heavy drizzle"),
    56: ("\ue3ad", "🌧️", "Freezing drizzle"),
    57: ("\ue3ad", "🌧️", "Freezing drizzle"),
    61: ("\ue318", "🌧️", "Light rain"),
    63: ("\ue318", "🌧️", "Rain"),
    65: ("\ue318", "🌧️", "Heavy rain"),
    66: ("\ue3ad", "🌧️", "Freezing rain"),
    67: ("\ue3ad", "🌧️", "Freezing rain"),
    71: ("\ue31a", "🌨️", "Light snow"),
    73: ("\ue31a", "🌨️", "Snow"),
    75: ("\ue31a", "🌨️", "Heavy snow"),
    77: ("\ue31a", "🌨️", "Snow grains"),
    80: ("\ue309", "🌦️", "Light showers"),
    81: ("\ue309", "🌦️", "Showers"),
    82: ("\ue318", "🌦️", "Heavy showers"),
    85: ("\ue31a", "🌨️", "Snow showers"),
    86: ("\ue31a", "🌨️", "Snow showers"),
    95: ("\ue31d", "⛈️", "Thunderstorm"),
    96: ("\ue31d", "⛈️", "Thunderstorm, hail"),
    99: ("\ue31d", "⛈️", "Thunderstorm, hail"),
}

NIGHT = {0: "\ue32b", 1: "\ue379", 2: "\ue379"}
COMPASS = [
    "N",
    "NNE",
    "NE",
    "ENE",
    "E",
    "ESE",
    "SE",
    "SSE",
    "S",
    "SSW",
    "SW",
    "WSW",
    "W",
    "WNW",
    "NW",
    "NNW",
]
SEVERITY_RANK = ["Extreme", "Severe", "Moderate", "Minor", "Unknown"]


def condition(code, is_day=True, emoji=False):
    glyph, icon, label = WMO.get(code, ("\ue374", "❓", f"Code {code}"))
    if emoji:
        return icon, label
    if not is_day and code in NIGHT:
        glyph = NIGHT[code]
    return glyph, label


def bearing(degrees):
    return COMPASS[int((degrees % 360) / 22.5 + 0.5) % 16]


def temperature_color(temperature, args):
    """Return a five-band color, with thresholds expressed in Fahrenheit."""
    fahrenheit = temperature if args.units == "imperial" else temperature * 9 / 5 + 32
    if fahrenheit < 20:
        return args.color_temp_very_low
    if fahrenheit < 40:
        return args.color_temp_low
    if fahrenheit <= 75:
        return args.color_temp_normal
    if fahrenheit < 90:
        return args.color_temp_high
    return args.color_temp_very_high


def colored(text, color, size=None, rise=None):
    size_attribute = f" size='{escape(size, quote=True)}'" if size else ""
    rise_attribute = f" rise='{rise}'" if rise is not None else ""
    return (
        f"<span color='{escape(color, quote=True)}'{size_attribute}{rise_attribute}>"
        f"{escape(text)}</span>"
    )


def get_json(url, params=None):
    if params:
        url = f"{url}?{urllib.parse.urlencode(params, doseq=True)}"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": UA, "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


def fetch_weather(args):
    metric = args.units == "metric"
    return get_json(
        "https://api.open-meteo.com/v1/forecast",
        {
            "latitude": args.lat,
            "longitude": args.lon,
            "timezone": args.tz,
            "forecast_days": 4,
            "temperature_unit": "celsius" if metric else "fahrenheit",
            "wind_speed_unit": "kmh" if metric else "mph",
            "precipitation_unit": "mm" if metric else "inch",
            "current": ",".join(
                [
                    "temperature_2m",
                    "apparent_temperature",
                    "relative_humidity_2m",
                    "weather_code",
                    "wind_speed_10m",
                    "wind_gusts_10m",
                    "wind_direction_10m",
                    "is_day",
                ]
            ),
            "hourly": ",".join(
                [
                    "temperature_2m",
                    "precipitation_probability",
                    "weather_code",
                    "is_day",
                ]
            ),
            "daily": ",".join(
                [
                    "weather_code",
                    "temperature_2m_max",
                    "temperature_2m_min",
                    "precipitation_probability_max",
                    "sunrise",
                    "sunset",
                ]
            ),
        },
    )


def fetch_alerts(args):
    """Return active alerts as (severity, event, headline) tuples."""
    data = get_json(
        "https://api.weather.gov/alerts/active",
        {
            "point": f"{args.lat},{args.lon}",
            "status": "actual",
            "message_type": "alert,update",
        },
    )
    alerts = []
    for feature in data.get("features", []):
        properties = feature.get("properties", {}) or {}
        alerts.append(
            (
                properties.get("severity") or "Unknown",
                properties.get("event") or "Alert",
                (properties.get("headline") or "").strip(),
            )
        )
    alerts.sort(
        key=lambda alert: (
            SEVERITY_RANK.index(alert[0])
            if alert[0] in SEVERITY_RANK
            else len(SEVERITY_RANK)
        )
    )
    return alerts


def build(weather, alerts, args):
    degree = "°C" if args.units == "metric" else "°F"
    speed = "km/h" if args.units == "metric" else "mph"
    current = weather["current"]
    glyph, label = condition(
        current["weather_code"], bool(current.get("is_day", 1)), args.emoji
    )
    temperature = round(current["temperature_2m"])
    feels = round(current["apparent_temperature"])
    temperature_text = f"{temperature}{degree if args.unit_in_bar else '°'}"
    text = (
        f"{colored(temperature_text, temperature_color(temperature, args), rise=1024)} "
        f"{colored(glyph, args.color_status, size='xx-large', rise=-2048)}"
    )
    lines = []

    for severity, event, headline in alerts[:3]:
        lines.append(
            f"<span weight='bold'>{escape(event)}</span> "
            f"<span size='small'>({escape(severity)})</span>"
        )
        if headline and args.alert_headlines:
            lines.append(f"<span size='small'>{escape(headline[:120])}</span>")
    if alerts:
        lines.append("")

    lines.append(
        f"<span size='x-large'>{escape(str(temperature))}{degree}</span>  "
        f"{escape(label)}"
    )
    details = [
        f"feels {feels}{degree}",
        f"{current['relative_humidity_2m']}% RH",
    ]
    wind = (
        f"{bearing(current['wind_direction_10m'])} {round(current['wind_speed_10m'])}"
    )
    if current.get("wind_gusts_10m"):
        wind += f"g{round(current['wind_gusts_10m'])}"
    details.append(f"{wind} {speed}")
    lines.append(f"<span size='small'>{escape('  ·  '.join(details))}</span>")
    lines.append("")

    hourly = weather["hourly"]
    now = datetime.now(ZoneInfo(args.tz)).strftime("%Y-%m-%dT%H:00")
    try:
        start = hourly["time"].index(now)
    except ValueError:
        start = next(
            (
                index
                for index, timestamp in enumerate(hourly["time"])
                if timestamp >= now
            ),
            0,
        )

    lines.extend(["<span weight='bold'>Next 8 hours</span>", "<tt>"])
    for index in range(start, min(start + 8, len(hourly["time"]))):
        when = datetime.fromisoformat(hourly["time"][index])
        hour = when.strftime("%H") if args.h24 else when.strftime("%-I%p").lower()
        hour_glyph, hour_label = condition(
            hourly["weather_code"][index],
            bool(hourly["is_day"][index]),
            args.emoji,
        )
        precipitation = hourly["precipitation_probability"][index] or 0
        precipitation_text = (
            f"{precipitation:>3}%" if precipitation >= args.pop_floor else "    "
        )
        lines.append(
            f"{hour:>4}  {hour_glyph}  "
            f"{round(hourly['temperature_2m'][index]):>3}°  "
            f"{precipitation_text}  {escape(hour_label)}"
        )
    lines.extend(["</tt>", "", "<span weight='bold'>Outlook</span>", "<tt>"])

    daily = weather["daily"]
    for index in range(1, min(4, len(daily["time"]))):
        day = datetime.fromisoformat(daily["time"][index]).strftime("%a")
        day_glyph, day_label = condition(daily["weather_code"][index], True, args.emoji)
        precipitation = daily["precipitation_probability_max"][index] or 0
        lines.append(
            f"{day}  {day_glyph}  "
            f"{round(daily['temperature_2m_max'][index]):>3}° / "
            f"{round(daily['temperature_2m_min'][index]):>3}°  "
            f"{precipitation:>3}%  {escape(day_label)}"
        )
    lines.append("</tt>")

    sunrise = datetime.fromisoformat(daily["sunrise"][0]).strftime("%H:%M")
    sunset = datetime.fromisoformat(daily["sunset"][0]).strftime("%H:%M")
    lines.append("")
    if args.emoji:
        lines.append(f"<span size='small'>🌅 {sunrise}   🌇 {sunset}</span>")
    else:
        lines.append(f"<span size='small'>\ue34c {sunrise}   \ue34d {sunset}</span>")

    classes = ["weather"]
    if alerts:
        top_severity = alerts[0][0]
        classes.extend(
            [
                "alert",
                "alert-"
                + (
                    top_severity.lower() if top_severity in SEVERITY_RANK else "unknown"
                ),
            ]
        )
        if args.alert_in_bar:
            text = f"{colored('', args.color_alert)} {text}"

    return {
        "text": text,
        "tooltip": "\n".join(lines),
        "class": classes,
        "alt": alerts[0][1] if alerts else label,
    }


def cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "waybar-weather.json")


def cache_write(payload):
    try:
        path = cache_path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as cache_file:
            json.dump({"t": time.time(), "payload": payload}, cache_file)
    except OSError:
        pass


def cache_read(max_age):
    try:
        with open(cache_path(), encoding="utf-8") as cache_file:
            cache = json.load(cache_file)
    except (OSError, ValueError):
        return None
    age = time.time() - cache.get("t", 0)
    if age > max_age:
        return None
    payload = cache["payload"]
    minutes = int(age // 60)
    if minutes >= 2:
        payload["text"] = f"{payload['text']}·"
        payload["tooltip"] = f"<i>stale, {minutes}m old</i>\n\n{payload['tooltip']}"
        payload["class"] = list(payload.get("class", [])) + ["stale"]
    return payload


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lat", type=float, default=41.7705)
    parser.add_argument("--lon", type=float, default=-87.5760)
    parser.add_argument("--tz", default="America/Chicago")
    parser.add_argument("--units", choices=["imperial", "metric"], default="imperial")
    parser.add_argument("--emoji", action="store_true")
    parser.add_argument("--h24", action="store_true")
    parser.add_argument("--no-alerts", dest="alerts", action="store_false")
    parser.add_argument(
        "--alert-in-bar",
        action=argparse.BooleanOptionalAction,
        default=True,
    )
    parser.add_argument("--alert-headlines", action="store_true")
    parser.add_argument("--unit-in-bar", action="store_true")
    parser.add_argument("--pop-floor", type=int, default=10)
    parser.add_argument("--stale-after", type=int, default=7200)
    parser.add_argument("--color-alert", default="#f7768e")
    parser.add_argument("--color-status", default="#7aa2f7")
    parser.add_argument("--color-temp-very-low", default="#7aa2f7")
    parser.add_argument("--color-temp-low", default="#7dcfff")
    parser.add_argument("--color-temp-normal", default="#9ece6a")
    parser.add_argument("--color-temp-high", default="#ff9e64")
    parser.add_argument("--color-temp-very-high", default="#f7768e")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        weather = fetch_weather(args)
    except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as error:
        fallback = cache_read(args.stale_after)
        if fallback:
            print(json.dumps(fallback), flush=True)
            return 0
        print(
            json.dumps(
                {
                    "text": "",
                    "tooltip": f"weather unavailable: {escape(str(error))}",
                    "class": ["weather", "error"],
                }
            ),
            flush=True,
        )
        return 0

    alerts = []
    if args.alerts:
        try:
            alerts = fetch_alerts(args)
        except (urllib.error.URLError, TimeoutError, ValueError, KeyError):
            pass

    payload = build(weather, alerts, args)
    cache_write(payload)
    print(json.dumps(payload), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
