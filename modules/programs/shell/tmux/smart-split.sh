# shellcheck shell=bash
# Get the current window name
window_name=$(tmux display-message -p '#{window_name}')

# Check if we're in an ssh: window
if [[ "$window_name" =~ ^ssh:\ (.+)$ ]]; then
  # Extract the hostname (everything after "ssh: ")
  host="${BASH_REMATCH[1]}"

  # Split with SSH to the same host, passing through split args
  tmux split-window "$@" -c "#{pane_current_path}" "ssh $host"
else
  # Normal split for non-SSH windows
  tmux split-window "$@" -c "#{pane_current_path}"
fi
