# shellcheck shell=bash
# Waybar custom module: per-core CPU load, as a row of heat bars.
#
# This exists because waybar's built-in `cpu` module cannot be made to do it.
# That module sets its tooltip with set_tooltip_text from a string it builds
# internally (src/modules/cpu.cpp) — it honours no `tooltip-format` key at all,
# so neither the layout nor the Pango markup every other tooltip in this bar
# uses is reachable from configuration. Driving it from a script is the only
# way to get a styled, per-core tooltip.
#
# Usage is a delta between polls, so a single sample means nothing: the
# previous /proc/stat snapshot is kept in $XDG_RUNTIME_DIR (tmpfs, cleared on
# logout, never persisted). The first run after boot has no predecessor and
# deliberately reports 0% rather than inventing a number from uptime totals.
#
# Colours arrive as TN_* from the wrapping module so the theme stays in one
# place. Values interpolated here are numbers and kernel-supplied hwmon labels;
# the labels are passed through a scrub for markup metacharacters anyway, since
# an unescaped '&' would make Pango render the whole tooltip as raw text.

state="${XDG_RUNTIME_DIR:-/tmp}/waybar-cpu.prev"

# ▁▂▃▄▅▆▇█ — eight levels, so a core's bar height is legible at a glance
# without reading any number.
bars=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

scrub() { printf '%s' "$1" | tr -d '<>&"'\''' ; }

# One <span> per core: height encodes load, colour encodes the same thing in a
# second channel so a wall of bars still reads at a glance.
heat() {
  local pct=$1 idx colour
  idx=$((pct * 8 / 100))
  [ "$idx" -gt 7 ] && idx=7
  [ "$idx" -lt 0 ] && idx=0
  if [ "$pct" -ge 80 ]; then
    colour="$TN_RED"
  elif [ "$pct" -ge 50 ]; then
    colour="$TN_YELLOW"
  else
    colour="$TN_GREEN"
  fi
  printf "<span color='%s'>%s</span>" "$colour" "${bars[$idx]}"
}

label() { printf "<span color='%s'>%s</span>" "$TN_DIM" "$1"; }

# Snapshot every cpuN line as "name idle total".
snapshot() {
  awk '/^cpu[0-9]/ {
    idle = $5 + $6
    total = 0
    for (i = 2; i <= NF; i++) total += $i
    print $1, idle, total
  }' /proc/stat
}

now=$(snapshot)

if [ ! -r "$state" ]; then
  printf '%s\n' "$now" > "$state" 2>/dev/null || true
  printf '{"text":"   0%%","tooltip":"CPU: sampling","class":"cpu"}\n'
  exit 0
fi

prev=$(cat "$state" 2>/dev/null)
printf '%s\n' "$now" > "$state" 2>/dev/null || true

# Per-core percentages, in core order, as a space-separated list.
percents=$(
  printf '%s\n===\n%s\n' "$prev" "$now" | awk '
    /^===$/ { second = 1; next }
    !second { pidle[$1] = $2; ptotal[$1] = $3; order[++n] = $1; next }
    { idle[$1] = $2; total[$1] = $3 }
    END {
      for (i = 1; i <= n; i++) {
        c = order[i]
        dt = total[c] - ptotal[c]
        di = idle[c] - pidle[c]
        pct = (dt > 0) ? int((dt - di) * 100 / dt + 0.5) : 0
        if (pct < 0) pct = 0
        if (pct > 100) pct = 100
        printf "%d ", pct
      }
    }'
)

read -r -a core <<< "$percents"
count=${#core[@]}

if [ "$count" -eq 0 ]; then
  printf '{"text":"   0%%","tooltip":"CPU: no samples","class":"cpu"}\n'
  exit 0
fi

total=0
for p in "${core[@]}"; do total=$((total + p)); done
avg=$((total / count))

row=""
for p in "${core[@]}"; do row="$row$(heat "$p")"; done

# Apple silicon runs asymmetric clusters and cpufreq groups them by policy —
# one policy per cluster — so a single "CPU frequency" would be a fiction and
# each cluster gets its own line.
#
# That only holds where policies ARE clusters. This module is shared with the
# desktop, and x86 drivers commonly expose one policy per core, which would
# turn this into a 16-line wall. Above a handful of policies the per-policy
# breakdown stops being information, so it collapses to a single range.
policies=()
for pol in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "$pol" ] && policies+=("$pol")
done

clusters=""
if [ "${#policies[@]}" -le 4 ]; then
  for pol in "${policies[@]}"; do
    cpus=$(cat "$pol/affected_cpus" 2>/dev/null) || continue
    [ -n "$cpus" ] || continue
    khz=$(cat "$pol/scaling_cur_freq" 2>/dev/null) || continue
    first=${cpus%% *}
    last=${cpus##* }
    ghz=$(awk -v k="$khz" 'BEGIN { printf "%.2f", k / 1000000 }')
    clusters="$clusters\n$(label "$(printf '%-8s' "cpu $first-$last")") $ghz GHz"
  done
elif [ "${#policies[@]}" -gt 0 ]; then
  lo=""
  hi=""
  for pol in "${policies[@]}"; do
    khz=$(cat "$pol/scaling_cur_freq" 2>/dev/null) || continue
    if [ -z "$lo" ] || [ "$khz" -lt "$lo" ]; then lo=$khz; fi
    if [ -z "$hi" ] || [ "$khz" -gt "$hi" ]; then hi=$khz; fi
  done
  if [ -n "$lo" ]; then
    range=$(awk -v l="$lo" -v h="$hi" 'BEGIN { printf "%.2f-%.2f", l / 1000000, h / 1000000 }')
    clusters="\n$(label 'freq   ') $range GHz"
  fi
fi

read -r l1 l5 l15 _ < /proc/loadavg

# No SoC/die temperature exists to report: the macsmc driver exposes battery,
# NAND, charge-regulator and WiFi sensors only. Rather than mislabel one of
# those as "CPU temp", every sensor is listed under its own kernel label and
# the caller can draw their own conclusions.
temps=""
for h in /sys/class/hwmon/hwmon*; do
  name=$(cat "$h/name" 2>/dev/null) || continue
  [ "$name" = "macsmc_hwmon" ] || continue
  for input in "$h"/temp*_input; do
    [ -r "$input" ] || continue
    lbl_file="${input%_input}_label"
    lbl=$(cat "$lbl_file" 2>/dev/null) || lbl="sensor"
    milli=$(cat "$input" 2>/dev/null) || continue
    deg=$(awk -v m="$milli" 'BEGIN { printf "%.1f", m / 1000 }')
    temps="$temps\n$(label "$(printf '%-22s' "$(scrub "$lbl")")") $deg°C"
  done
done

tooltip="<span color='$TN_BLUE'><b>CPU  $avg%</b></span>"
tooltip="$tooltip\n$(label 'cores  ') $row"
tooltip="$tooltip\n$(label 'load   ') $l1 $l5 $l15$clusters"
[ -n "$temps" ] && tooltip="$tooltip\n$(label 'sensors')$temps"

printf '{"text":" %3d%%","tooltip":"%s","class":"cpu"}\n' "$avg" "$tooltip"
