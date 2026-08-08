# shellcheck shell=bash
# Waybar custom module: microphone state, including whether anything is
# actually capturing.
#
# Mute state alone answers "what did I set", which is the less useful
# question. PipeWire also knows "is audio being pulled from the mic right
# now", and the interesting combinations only exist when you have both:
#
#   unmuted + idle       armed, nobody listening
#   unmuted + capturing  hot mic
#   muted   + idle       off
#   muted   + capturing  an app is recording silence -- the "why can't they
#                        hear me" state, which nothing else in the bar surfaces
#
# Detection rests on node STATE, not node existence. Asahi's mic DSP publishes
# `audio_effect.j416-mic` as a permanent Stream/Input/Audio node, so counting
# consumers would report "in use" forever; it sits `idle` and flips to
# `running` along with real consumers, which is the signal. Verified by
# capturing for three seconds and watching it move and settle back.
#
# Filter-chain nodes are excluded from the app list by name -- they are
# plumbing, not an app that is listening to you.

status=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null) || {
  printf '{"text":"","tooltip":"Microphone: no default source","class":"unavailable"}\n'
  exit 0
}

case "$status" in
  *"[MUTED]"*) muted=1 ;;
  *) muted=0 ;;
esac

# "Volume: 0.70 [MUTED]" -> 70
#
# The END block matters: a bare '{ ... }' prints nothing at all when the input
# is empty, so a momentarily blank wpctl reply left $volume unset, the final
# printf failed with "invalid number", the script exited non-zero and waybar
# -- which hides a custom module that produces no output -- made the whole
# indicator vanish. A mic indicator that disappears under load is worse than
# useless, so this always yields a number.
volume=$(printf '%s' "$status" | awk '
  BEGIN { v = 0 }
  /Volume:/ { v = ($2 * 100) + 0.5 }
  END { printf "%d", v }')

# Names of everything currently pulling from an input, minus the DSP plumbing.
# @html so an application.name containing markup metacharacters can neither
# break the Pango tooltip nor the JSON assembled below.
apps=$(pw-dump 2>/dev/null | jq -r '
  [ .[]
    | select(.type == "PipeWire:Interface:Node")
    | .info // {}
    | select((.props."media.class" // "") == "Stream/Input/Audio")
    | select(.state == "running")
    | select(((.props."node.name" // "") | startswith("audio_effect.")) | not)
    | (.props."application.name" // .props."node.name" // "unknown")
  ] | unique | .[] | @html' 2>/dev/null)

if [ -n "$apps" ]; then
  capturing=1
  count=$(printf '%s\n' "$apps" | grep -c .)
else
  capturing=0
  count=0
fi

label() { printf "<span color='%s'>%s</span>" "$TN_DIM" "$1"; }

# The glyph carries mute, the class carries capture. Width is fixed at three
# digits so the module never resizes -- see the percentage padding elsewhere.
if [ "$muted" -eq 1 ]; then
  icon=""
  state_text="muted"
else
  icon=""
  state_text="live"
fi

if [ "$capturing" -eq 1 ]; then
  if [ "$muted" -eq 1 ]; then
    class="muted-capturing"
    heading="Microphone — muted, but $count app(s) recording"
    colour="$TN_RED"
  else
    class="capturing"
    heading="Microphone — in use by $count app(s)"
    colour="$TN_RED"
  fi
else
  if [ "$muted" -eq 1 ]; then
    class="muted"
    heading="Microphone — muted"
    colour="$TN_DIM"
  else
    class="idle"
    heading="Microphone — idle"
    colour="$TN_GREEN"
  fi
fi

tooltip=$(printf "<span color='%s'><b>%s</b></span>" "$colour" "$heading")
tooltip="$tooltip\n$(label 'state  ') $state_text"
tooltip="$tooltip\n$(label 'volume ') $volume%"

if [ "$capturing" -eq 1 ]; then
  tooltip="$tooltip\n$(label 'used by')"
  while IFS= read -r app; do
    [ -n "$app" ] || continue
    tooltip="$tooltip\n  $app"
  done <<< "$apps"
fi

printf '{"text":"%s %3d%%","tooltip":"%s","class":"%s"}\n' "$icon" "$volume" "$tooltip" "$class"
