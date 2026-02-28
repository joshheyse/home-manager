# shellcheck shell=bash
set -euo pipefail

# Claude Code hook script for tmux integration
# Called by Claude Code hooks with: $1 = event type
# Stdin: JSON from Claude Code (for permission/question events)
# Stdout: JSON decision (for permission events only)

EVENT="${1:-}"
STATE_DIR="${TMPDIR:-/tmp}/claude-tmux"
PANE_ID="${TMUX_PANE:-}"

# Exit silently if not in tmux
if [[ -z "$PANE_ID" ]]; then
  exit 0
fi

STATE_FILE="${STATE_DIR}/${PANE_ID}"
DETAIL_FILE="${STATE_DIR}/${PANE_ID}.detail"
RESPONSE_FILE="${STATE_DIR}/${PANE_ID}.response"

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
      tmux set-option -w -t "$window_id" @claude_icon " #[fg=#e0af68,blink]󰧑#[noblink,fg=default]"
      ;;
    running)
      tmux set-option -w -t "$window_id" @claude_icon " #[fg=#9ece6a]󰧑#[fg=default]"
      ;;
    idle)
      tmux set-option -w -t "$window_id" @claude_icon " #[fg=#565f89]󰧑#[fg=default]"
      ;;
    *)
      tmux set-option -wu -t "$window_id" @claude_icon 2>/dev/null || true
      ;;
  esac
}

cleanup() {
  rm -f "$STATE_FILE" "$DETAIL_FILE" "$RESPONSE_FILE"
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

wait_for_response() {
  local timeout="${1:-300}" # 5 minutes default
  local elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    if [[ -f "$RESPONSE_FILE" ]]; then
      local response
      response=$(cat "$RESPONSE_FILE")
      rm -f "$RESPONSE_FILE"
      echo "$response"
      return 0
    fi
    sleep 0.5
    elapsed=$((elapsed + 1))
    # Check every 2 iterations (1 second)
    if (( elapsed % 2 == 0 )); then
      # Verify the pane still exists
      if ! tmux has-session -t "$PANE_ID" 2>/dev/null; then
        cleanup
        return 1
      fi
    fi
  done
  # Timeout - return empty to fall through to normal dialog
  return 1
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
    # Read JSON from stdin
    input=$(cat)
    tool_name=$(echo "$input" | jq -r '.tool_name // "unknown"')
    tool_input_summary=$(echo "$input" | jq -c '.tool_input // {}' | head -c 200)

    set_state "permission"
    set_window_icon "permission"
    echo "{\"tool_name\": \"$tool_name\", \"tool_input\": $tool_input_summary}" > "$DETAIL_FILE"

    send_notification "Claude Code" "${tool_name} needs permission"

    # Block and wait for response from F-key handler
    if response=$(wait_for_response 300); then
      set_state "running"
      set_window_icon "running"
      case "$response" in
        allow)
          echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
          ;;
        deny)
          echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied via tmux hotkey"}}}'
          ;;
        *)
          # Unknown response, allow by default
          echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
          ;;
      esac
    else
      # Timeout or pane gone - exit 0 so normal dialog appears
      set_state "running"
      set_window_icon "running"
      exit 0
    fi
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
    # Only skip if in permission state (permission hook is blocking and handles its own transition).
    # Question state IS updated here: if a tool ran, the question was already answered.
    current=$(cat "$STATE_FILE" 2>/dev/null || echo "")
    if [[ "$current" != "permission" ]]; then
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
