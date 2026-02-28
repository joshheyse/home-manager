# shellcheck shell=bash
set -euo pipefail

# F-key response handler for Claude Code tmux integration
# Args: $1 = action (1|2|3|focus)

ACTION="${1:-}"
STATE_DIR="${TMPDIR:-/tmp}/claude-tmux"

if [[ -z "$ACTION" ]]; then
  exit 1
fi

# Find a Claude pane in the CURRENT WINDOW that has a pending prompt
find_claude_pane() {
  local current_window
  current_window=$(tmux display-message -p '#{window_id}')

  for state_file in "$STATE_DIR"/%*; do
    [[ -e "$state_file" ]] || continue
    local pane_id
    pane_id=$(basename "$state_file")
    [[ "$pane_id" == *.detail ]] && continue
    [[ "$pane_id" == *.response ]] && continue

    local state
    state=$(cat "$state_file" 2>/dev/null || echo "")
    if [[ "$state" != "permission" && "$state" != "question" ]]; then
      continue
    fi

    # Check pane is in our current window
    local pane_window
    pane_window=$(tmux display-message -t "$pane_id" -p '#{window_id}' 2>/dev/null || echo "")
    if [[ "$pane_window" == "$current_window" ]]; then
      echo "$pane_id"
      return 0
    fi
  done
  return 1
}

pane_id=$(find_claude_pane) || exit 0

state_file="${STATE_DIR}/${pane_id}"
detail_file="${STATE_DIR}/${pane_id}.detail"
response_file="${STATE_DIR}/${pane_id}.response"

state=$(cat "$state_file" 2>/dev/null || echo "")
tool_name=$(jq -r '.tool_name // "tool"' < "$detail_file" 2>/dev/null || echo "tool")

set_running_icon() {
  local window_id
  window_id=$(tmux display-message -t "$pane_id" -p '#{window_id}' 2>/dev/null) || return
  tmux set-option -w -t "$window_id" @claude_icon " #[fg=#9ece6a]󰧑#[fg=default]" 2>/dev/null || true
}

case "$ACTION" in
  focus)
    tmux select-pane -t "$pane_id"
    ;;

  1)
    if [[ "$state" == "permission" ]]; then
      echo "allow" > "$response_file"
      tmux display-message "✓ Allowed: ${tool_name}"
    elif [[ "$state" == "question" ]]; then
      tmux send-keys -t "$pane_id" "1" Enter
      echo "running" > "$state_file"
      set_running_icon
    fi
    ;;

  2)
    if [[ "$state" == "permission" ]]; then
      echo "allow" > "$response_file"
      tmux display-message "✓ Allowed (always): ${tool_name}"
    elif [[ "$state" == "question" ]]; then
      tmux send-keys -t "$pane_id" "2" Enter
      echo "running" > "$state_file"
      set_running_icon
    fi
    ;;

  3)
    if [[ "$state" == "permission" ]]; then
      echo "deny" > "$response_file"
      tmux display-message "✗ Denied: ${tool_name}"
      tmux select-pane -t "$pane_id"
    elif [[ "$state" == "question" ]]; then
      tmux send-keys -t "$pane_id" "3" Enter
      echo "running" > "$state_file"
      set_running_icon
    fi
    ;;
esac
