# shellcheck shell=bash
set -euo pipefail

PROVIDER="${1:?provider required}"
EVENT="${2:?event required}"
AGENT_STATE_COMMAND="${AGENT_STATE_COMMAND:?AGENT_STATE_COMMAND required}"

resolve_agent_pane() {
  local pane_id pane_role pane_path pane_command

  if [[ -n "${TMUX_PANE:-}" ]] && tmux display-message -t "$TMUX_PANE" -p '#{pane_id}' >/dev/null 2>&1; then
    return
  fi

  # Codex Remote Control launches hooks from its persistent daemon, outside the
  # originating pane environment. Recover the pane from the project directory
  # and the role assigned by the dev-workspace launcher.
  while IFS=$'\t' read -r pane_id pane_role pane_path pane_command; do
    if [[ "$pane_role" == "agent" && "$pane_path" == "$PWD" && "$pane_command" == "$PROVIDER" ]]; then
      export TMUX_PANE="$pane_id"
      return
    fi
  done < <(tmux list-panes -a -F '#{pane_id}\t#{@pane_role}\t#{pane_current_path}\t#{pane_current_command}' 2>/dev/null)
}

resolve_agent_pane

notify_attention() {
  local input message client_tty
  input=$(cat)
  message=$(printf '%s' "$input" | jq -r '.message // "Input required"')
  client_tty=$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -1)
  if [[ -n "$client_tty" ]]; then
    notify -T -t "$PROVIDER" -o unfocused "$message" > "$client_tty" 2>/dev/null || true
  fi
}

notify_pending_permission() {
  local input message
  input=$(cat)
  message=$(printf '%s' "$input" | jq -r '.message // "Permission required"')

  # Permission hooks run before the automatic approval reviewer responds. Give
  # it time to resolve the request, then notify only if attention is still
  # required. Detach completely so the hook itself can return immediately.
  (
    local client_tty pane_provider pane_state
    sleep 2
    pane_provider=$(tmux show-option -wv -t "${TMUX_PANE:-}" @agent_provider 2>/dev/null) || exit 0
    pane_state=$(tmux show-option -wv -t "${TMUX_PANE:-}" @agent_state 2>/dev/null) || exit 0
    [[ "$pane_provider" == "$PROVIDER" && "$pane_state" == "attention" ]] || exit 0

    client_tty=$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -1)
    if [[ -n "$client_tty" ]]; then
      notify -T -t "$PROVIDER" -o unfocused "$message" > "$client_tty" 2>/dev/null || true
    fi
  ) </dev/null >/dev/null 2>&1 &
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
  attention)
    "$AGENT_STATE_COMMAND" set "$PROVIDER" attention
    notify_attention
    ;;
  permission)
    "$AGENT_STATE_COMMAND" set "$PROVIDER" attention
    notify_pending_permission
    ;;
  error)
    "$AGENT_STATE_COMMAND" set "$PROVIDER" error
    ;;
  end)
    "$AGENT_STATE_COMMAND" clear
    ;;
esac
