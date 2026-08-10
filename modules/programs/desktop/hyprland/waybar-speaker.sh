#!/usr/bin/env bash

status=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || {
  printf '{"text":"󰖁","tooltip":"Speaker: no default output","class":"unavailable"}\n'
  exit 0
}

case "$status" in
  *"[MUTED]"*) muted=1 ;;
  *) muted=0 ;;
esac

volume=$(printf '%s' "$status" | awk '
  BEGIN { v = 0 }
  /Volume:/ { v = ($2 * 100) + 0.5 }
  END { printf "%d", v }')

sink_info=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
if printf '%s\n' "$sink_info" | grep -Eq \
  'node\.name = "bluez_output\.|device\.api = "bluez5"|api\.bluez5\.'; then
  bluetooth=1
else
  bluetooth=0
fi

if [ "$bluetooth" -eq 1 ]; then
  if [ "$muted" -eq 1 ]; then
    icon="󰟎"
  else
    icon=""
  fi
elif [ "$muted" -eq 1 ]; then
  icon="󰖁"
elif [ "$volume" -lt 34 ]; then
  icon=""
elif [ "$volume" -lt 67 ]; then
  icon=""
else
  icon=""
fi

description=$(printf '%s\n' "$sink_info" | awk -F ' = ' '
  /node.description/ { gsub(/^"|"$/, "", $2); print $2; found=1; exit }
  END { if (!found) print "Audio output" }')
description=$(printf '%s' "$description" | jq -Rr @html)

if [ "$muted" -eq 1 ]; then
  class="muted"
else
  class="active"
fi

tooltip=$(printf \
  "<span color='%s'><b>%s</b></span>\n<span color='%s'>output </span> %s%%" \
  "$TN_ORANGE" "$description" "$TN_DIM" "$volume")
jq -cn \
  --arg text "$(printf '%3d%% %s' "$volume" "$icon")" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text: $text, tooltip: $tooltip, class: $class}'
