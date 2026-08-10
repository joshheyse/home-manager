#!/usr/bin/env python3
"""Smoothly map Asahi's ambient-light sensor to panel and keyboard light."""

import argparse
import math
import os
import sys
import time
from pathlib import Path

IIO_ROOT = Path("/sys/bus/iio/devices")
DISPLAY = Path("/sys/class/backlight/apple-panel-bl")
KEYBOARD = Path("/sys/class/leds/kbd_backlight")

# Lux-to-percent control points. Interpolation happens in log(lux + 1) space,
# which tracks human perception better than a linear response.
DISPLAY_CURVE = [(0, 18), (5, 25), (20, 34), (80, 48), (300, 62), (1000, 78), (5000, 100)]
KEYBOARD_CURVE = [(0, 40), (3, 35), (10, 24), (30, 12), (80, 0)]


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--manual-pause-seconds", type=int, default=900)
    return parser.parse_args()


def find_sensor():
    for device in sorted(IIO_ROOT.glob("iio:device*")):
        try:
            name = (device / "name").read_text(encoding="utf-8").strip()
            if name == "aop-sensors-als":
                reading = device / "in_illuminance_input"
                if reading.is_file():
                    return reading
        except OSError:
            continue
    raise RuntimeError("Asahi ambient-light sensor aop-sensors-als was not found")


def interpolate(lux, curve):
    if lux <= curve[0][0]:
        return curve[0][1]
    for (low_lux, low_value), (high_lux, high_value) in zip(curve, curve[1:]):
        if lux <= high_lux:
            low = math.log1p(low_lux)
            high = math.log1p(high_lux)
            position = (math.log1p(lux) - low) / (high - low)
            return round(low_value + position * (high_value - low_value))
    return curve[-1][1]


class Light:
    def __init__(self, device):
        self.brightness = device / "brightness"
        self.maximum = int((device / "max_brightness").read_text(encoding="utf-8"))

    def percent(self):
        value = int(self.brightness.read_text(encoding="utf-8"))
        return round(value * 100 / self.maximum)

    def set_percent(self, percent):
        raw = round(max(0, min(100, percent)) * self.maximum / 100)
        self.brightness.write_text(f"{raw}\n", encoding="utf-8")

    def approach(self, target, step=1):
        current = self.percent()
        if abs(target - current) < 2:
            return
        self.set_percent(current + max(-step, min(step, target - current)))


def display_is_paused(pause_file, seconds):
    try:
        return time.time() - pause_file.stat().st_mtime < seconds
    except FileNotFoundError:
        return False


def main():
    args = arguments()
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise RuntimeError("XDG_RUNTIME_DIR is not set")

    sensor = find_sensor()
    display = Light(DISPLAY)
    keyboard = Light(KEYBOARD)
    pause_file = Path(runtime) / "auto-brightness.pause"
    smoothed_lux = None

    while True:
        try:
            lux = max(0.0, float(sensor.read_text(encoding="utf-8")))
            smoothed_lux = lux if smoothed_lux is None else 0.15 * lux + 0.85 * smoothed_lux

            if not display_is_paused(pause_file, args.manual_pause_seconds):
                display.approach(interpolate(smoothed_lux, DISPLAY_CURVE))
            keyboard.approach(interpolate(smoothed_lux, KEYBOARD_CURVE))
        except OSError as error:
            print(f"auto-brightness: {error}", file=sys.stderr)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
