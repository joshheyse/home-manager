# shellcheck shell=bash
# Tmux window type and icon manager.
# Centralizes the mapping between window types and Nerd Font icons.
#
# Usage:
#   pane-icon.sh set <type> [window_id]   - Set @window_type and @pane_icon
#   pane-icon.sh get [window_id]          - Print current @window_type
#   pane-icon.sh icon [type]              - Print icon character for a type

# Icon characters (Nerd Font codepoints)
# ssh:     󰣀  U+F08C0  nf-md-ssh
# dev:     󰅩  U+F0169  nf-md-code_braces  (U+F0205)
# monitor: 󰓅  U+F04C5  nf-md-speedometer
# default:   U+E795   nf-dev-terminal

icon_for_type() {
  case "$1" in
    ssh) printf '\U000f08c0' ;;
    dev) printf '\U000f0205' ;;
    monitor) printf '\U000f04c5' ;;
    *) printf '\ue795' ;;
  esac
}

case "${1:-}" in
  set)
    type="${2:?Usage: pane-icon.sh set <type> [window_id]}"
    window_target="${3:-}"
    icon=$(icon_for_type "$type")
    # shellcheck disable=SC2086
    tmux set-window-option ${window_target:+-t "$window_target"} @window_type "$type"
    # shellcheck disable=SC2086
    tmux set-window-option ${window_target:+-t "$window_target"} @pane_icon "$icon"
    ;;
  get)
    window_target="${2:-}"
    # shellcheck disable=SC2086
    tmux show-window-option ${window_target:+-t "$window_target"} -v @window_type 2>/dev/null || true
    ;;
  icon)
    icon_for_type "${2:-}"
    ;;
  *)
    echo "Usage: pane-icon.sh {set|get|icon} [args...]" >&2
    exit 1
    ;;
esac
