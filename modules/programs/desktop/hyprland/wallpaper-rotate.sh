#!/usr/bin/env bash
# wallpaper-rotate — Pick a random wallpaper and apply via hyprpaper IPC
# Usage: wallpaper-rotate <wallpaper-dir> <monitor1> [monitor2] ...

set -euo pipefail

# Auto-detect HYPRLAND_INSTANCE_SIGNATURE when not in environment (e.g. systemd service)
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  sig_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
  if [[ -d "$sig_dir" ]]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(find "$sig_dir" -maxdepth 1 -mindepth 1 -printf '%f\n' -quit)"
    export HYPRLAND_INSTANCE_SIGNATURE
  fi
fi

WALLPAPER_DIR="${1:?Usage: wallpaper-rotate <dir> <monitor1> [monitor2] ...}"
shift
MONITORS=("$@")

if [[ ${#MONITORS[@]} -eq 0 ]]; then
  echo "Error: At least one monitor name required" >&2
  exit 1
fi

# Find all image files
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null)

if [[ ${#WALLPAPERS[@]} -eq 0 ]]; then
  echo "No wallpapers found in $WALLPAPER_DIR" >&2
  exit 0
fi

# Pick a random wallpaper
WALLPAPER="${WALLPAPERS[RANDOM % ${#WALLPAPERS[@]}]}"
echo "Selected: $WALLPAPER"

# Unload all current wallpapers first
hyprctl hyprpaper unload all 2>/dev/null || true

# Preload the new wallpaper
hyprctl hyprpaper preload "$WALLPAPER"

# Apply to each monitor
for monitor in "${MONITORS[@]}"; do
  hyprctl hyprpaper wallpaper "${monitor},${WALLPAPER}"
  echo "Applied to ${monitor}"
done
