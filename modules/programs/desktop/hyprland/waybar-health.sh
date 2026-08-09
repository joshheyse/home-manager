# shellcheck shell=bash
# Adapt the system daemon's atomic snapshot to Waybar's JSON form. This reader
# owns staleness detection: a dead daemon must never leave a healthy-looking
# heart behind indefinitely.

state=${HEALTH_STATE:-/run/health/state.json}

if [ "${1:-}" = "--open" ]; then
  port=$(jq -r '.port // empty' "$state" 2> /dev/null || true)
  case "$port" in
    '' | *[!0-9]*) exit 0 ;;
  esac
  exec xdg-open "http://127.0.0.1:$port/"
fi

unknown() {
  jq -cn --arg detail "$1" \
    '{text: "♥", class: "unknown", tooltip: ("System health: unknown\n" + $detail)}'
}

if [ ! -r "$state" ]; then
  unknown "no state yet — health-check.service may not have run"
  exit 0
fi

if ! snapshot=$(jq -c '
  select(type == "object")
  | select((.generated | type) == "number")
  | select((.intervalSeconds | type) == "number")
  | select((.checks | type) == "array")
  ' "$state" 2> /dev/null) || [ -z "$snapshot" ]; then
  unknown "state.json is malformed"
  exit 0
fi

now=$(date +%s)
generated=$(printf '%s' "$snapshot" | jq -r '.generated')
interval=$(printf '%s' "$snapshot" | jq -r '.intervalSeconds')
age=$((now - generated))
stale_after=$((interval * 2 + 60))

if [ "$age" -lt 0 ] || [ "$age" -gt "$stale_after" ]; then
  unknown "last report is ${age}s old (expected every ${interval}s)"
  exit 0
fi

printf '%s' "$snapshot" | jq -c '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
  def status_label: {crit: "critical", warn: "warning", unknown: "unknown", ok: "healthy"}[.] // "unknown";
  .status as $status
  | ([.checks[] | select(.status == "crit" or .status == "warn" or .status == "unknown")]
     | sort_by(if .status == "crit" then 0 elif .status == "warn" then 1 else 2 end)
     | .[:6]) as $findings
  | {
      text: "♥",
      class: $status,
      tooltip: (("System health: " + ($status | status_label)
        + "\n" + (.summary.crit | tostring) + " critical, "
        + (.summary.warn | tostring) + " warning, "
        + (.summary.unknown | tostring) + " unknown")
        + (if ($findings | length) == 0 then "\nAll checks passed"
           else "\n\n" + ($findings | map((.title | esc) + ": " + (.detail | esc)) | join("\n")) end))
    }'

# Always exit successfully. Waybar hides a custom module that exits non-zero,
# which would make a broken reader indistinguishable from a healthy machine.
exit 0
