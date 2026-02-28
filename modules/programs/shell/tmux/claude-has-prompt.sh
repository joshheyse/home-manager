# shellcheck shell=bash
# Guard script for F-key if-shell bindings
# Exit 0 if any pane in current window has a pending permission or question
# Exit 1 otherwise (F-keys pass through normally)

STATE_DIR="${TMPDIR:-/tmp}/claude-tmux"

if [[ ! -d "$STATE_DIR" ]]; then
  exit 1
fi

current_window=$(tmux display-message -p '#{window_id}')

for state_file in "$STATE_DIR"/%*; do
  [[ -e "$state_file" ]] || continue
  pane_id=$(basename "$state_file")
  [[ "$pane_id" == *.detail ]] && continue
  [[ "$pane_id" == *.response ]] && continue

  state=$(cat "$state_file" 2>/dev/null || echo "")
  if [[ "$state" != "permission" && "$state" != "question" ]]; then
    continue
  fi

  # Check pane is in our current window
  pane_window=$(tmux display-message -t "$pane_id" -p '#{window_id}' 2>/dev/null || echo "")
  if [[ "$pane_window" == "$current_window" ]]; then
    exit 0
  fi
done

exit 1
