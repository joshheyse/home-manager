# shellcheck shell=bash
set -euo pipefail

PROVIDER="${1:?provider required}"
EVENT="${2:?event required}"
AGENT_STATE_COMMAND="${AGENT_STATE_COMMAND:?AGENT_STATE_COMMAND required}"

notify_attention() {
  local input message client_tty
  input=$(cat)
  message=$(printf '%s' "$input" | jq -r '.message // "Input required"')
  client_tty=$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -1)
  if [[ -n "$client_tty" ]]; then
    notify -T -t "$PROVIDER" -o unfocused "$message" > "$client_tty" 2>/dev/null || true
  fi
}

case "$EVENT" in
  start|idle|stop)
    "$AGENT_STATE_COMMAND" set "$PROVIDER" idle
    if [[ "$PROVIDER" == "codex" && "$EVENT" == "stop" ]]; then
      printf '{}\n'
    fi
    ;;
  submit|working|permission-replied)
    "$AGENT_STATE_COMMAND" set "$PROVIDER" working
    ;;
  attention|permission)
    "$AGENT_STATE_COMMAND" set "$PROVIDER" attention
    notify_attention
    ;;
  error)
    "$AGENT_STATE_COMMAND" set "$PROVIDER" error
    ;;
  end)
    "$AGENT_STATE_COMMAND" clear
    ;;
esac
