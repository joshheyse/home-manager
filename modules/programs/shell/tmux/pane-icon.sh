# shellcheck shell=bash
# Resolve a window icon based on @window_type (explicit) or pane_current_command (auto-detect).
# Usage: pane-icon.sh <window_id>
# Prints the appropriate Nerd Font icon for the given window.

window_id="${1:-}"
if [[ -z "$window_id" ]]; then
  echo ""
  exit 0
fi

# Prefer explicit window type if set
window_type=$(tmux show-window-option -t "$window_id" -v @window_type 2>/dev/null) || true

if [[ -z "$window_type" ]]; then
  # Auto-detect from the active pane's command
  window_type=$(tmux display-message -t "$window_id" -p '#{pane_current_command}')
fi

case "$window_type" in
  ssh) echo "󰣀" ;;       # nf-md-ssh
  dev) echo "" ;;       # nf-dev-code
  btop | btm | htop | top) echo "󰄪" ;; # nf-md-chart_line
  *) echo "" ;;         # nf-dev-terminal (default)
esac
