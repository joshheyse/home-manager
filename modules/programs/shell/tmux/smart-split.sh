# shellcheck shell=bash
# Query the window type to determine split behavior
window_type=$(tmux show-window-option -v @window_type 2>/dev/null) || true

if [[ "$window_type" == "ssh" ]]; then
  # SSH window: split and connect to the same host
  host=$(tmux show-window-option -v @ssh_host 2>/dev/null) || true
  if [[ -n "$host" ]]; then
    tmux split-window "$@" -c "#{pane_current_path}" "ssh $host"
  else
    tmux split-window "$@" -c "#{pane_current_path}"
  fi
else
  tmux split-window "$@" -c "#{pane_current_path}"
fi
