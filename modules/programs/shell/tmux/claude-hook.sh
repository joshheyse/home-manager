# shellcheck shell=bash
set -euo pipefail

# Claude Code hook script for tmux integration
# Called by Claude Code hooks with: $1 = event type
# Stdin: JSON from Claude Code (for permission/question events)

EVENT="${1:-}"
STATE_DIR="${TMPDIR:-/tmp}/claude-tmux"
PANE_ID="${TMUX_PANE:-}"

# Exit silently if not in tmux
if [[ -z "$PANE_ID" ]]; then
  exit 0
fi

STATE_FILE="${STATE_DIR}/${PANE_ID}"
DETAIL_FILE="${STATE_DIR}/${PANE_ID}.detail"

mkdir -p "$STATE_DIR"

set_state() {
  echo "$1" > "$STATE_FILE"
}

# Update the window tab icon/color based on Claude state
set_window_icon() {
  local state="$1"
  local window_id
  window_id=$(tmux display-message -t "$PANE_ID" -p '#{window_id}' 2>/dev/null) || return
  case "$state" in
    permission|question)
      tmux set-option -w -t "$window_id" @claude_state "attention"
      tmux set-option -w -t "$window_id" @claude_icon " #[fg=#e0af68,blink]󰧑#[noblink,fg=default]"
      ;;
    running)
      tmux set-option -w -t "$window_id" @claude_state "working"
      tmux set-option -w -t "$window_id" @claude_icon " #[fg=#9ece6a]󰧑#[fg=default]"
      ;;
    idle)
      tmux set-option -w -t "$window_id" @claude_state "idle"
      tmux set-option -w -t "$window_id" @claude_icon " #[fg=#565f89]󰧑#[fg=default]"
      ;;
    *)
      tmux set-option -wu -t "$window_id" @claude_state 2>/dev/null || true
      tmux set-option -wu -t "$window_id" @claude_icon 2>/dev/null || true
      ;;
  esac
}

cleanup() {
  rm -f "$STATE_FILE" "$DETAIL_FILE"
}

send_notification() {
  local title="$1"
  local message="$2"
  # Get the client tty attached to our tmux session
  local client_tty
  client_tty=$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -1)
  if [[ -n "$client_tty" ]]; then
    # Send raw OSC 99 directly to terminal (bypass tmux DCS)
    notify -T -t "$title" -o unfocused "$message" > "$client_tty" 2>/dev/null || true
  fi
}

case "$EVENT" in
  start)
    set_state "idle"
    set_window_icon "idle"
    ;;

  submit)
    set_state "running"
    set_window_icon "running"
    ;;

  permission)
    input=$(cat)
    message=$(echo "$input" | jq -r '.message // "Permission required"')

    set_state "permission"
    set_window_icon "permission"
    echo "$input" > "$DETAIL_FILE"
    send_notification "Claude Code" "$message"
    ;;

  question)
    # Read JSON from stdin
    input=$(cat)
    message=$(echo "$input" | jq -r '.message // "Question"')

    set_state "question"
    set_window_icon "question"
    echo "$input" > "$DETAIL_FILE"

    send_notification "Claude Code" "$message"
    ;;

  tool-done)
    # Only transition to running from active states (question/running).
    # Skip if idle (late PostToolUse after Stop) or permission (blocking handler).
    current=$(cat "$STATE_FILE" 2>/dev/null || echo "")
    if [[ "$current" == "running" || "$current" == "question" ]]; then
      set_state "running"
      set_window_icon "running"
    fi
    ;;

  idle)
    set_state "idle"
    set_window_icon "idle"
    send_notification "Claude Code" "Ready for input"
    ;;

  stop)
    set_state "idle"
    set_window_icon "idle"
    ;;

  end)
    set_window_icon "clear"
    cleanup
    ;;

  *)
    # Unknown event, ignore
    ;;
esac
