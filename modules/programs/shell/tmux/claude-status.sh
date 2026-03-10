# shellcheck shell=bash
# Tmux status bar widget for Claude Code integration
# Called by: tmux status-right via #(script)
# Output: tmux format string with ✦ icon

STATE_DIR="${TMPDIR:-/tmp}/claude-tmux"

if [[ ! -d "$STATE_DIR" ]]; then
  exit 0
fi

needs_attention=false
has_session=false

for state_file in "$STATE_DIR"/%*; do
  # Skip if glob didn't match
  [[ -e "$state_file" ]] || continue

  pane_id=$(basename "$state_file")

  # Skip detail/response files
  [[ "$pane_id" == *.detail ]] && continue
  [[ "$pane_id" == *.response ]] && continue

  # Verify pane still exists, clean up stale files
  if ! tmux has-session -t "$pane_id" 2>/dev/null; then
    rm -f "$state_file" "${state_file}.detail" "${state_file}.response"
    continue
  fi

  has_session=true
  state=$(cat "$state_file" 2>/dev/null || echo "")

  if [[ "$state" == "permission" || "$state" == "question" ]]; then
    needs_attention=true
    break
  fi
done

if [[ "$needs_attention" == true ]]; then
  echo "#[fg=#e0af68,blink]✦#[noblink,fg=default] "
elif [[ "$has_session" == true ]]; then
  echo "#[fg=#9ece6a]✦#[fg=default] "
fi
