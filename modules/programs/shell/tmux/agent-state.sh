# shellcheck shell=bash
set -euo pipefail
umask 077

COMMAND="${1:-}"
PROVIDER="${2:-}"
STATE="${3:-}"
PANE_ID="${TMUX_PANE:-}"

[[ -n "$PANE_ID" ]] || exit 0

TMUX_SERVER_PID="${TMUX:-}"
TMUX_SERVER_PID="${TMUX_SERVER_PID%,*}"
TMUX_SERVER_PID="${TMUX_SERVER_PID##*,}"

if [[ ! "$TMUX_SERVER_PID" =~ ^[0-9]+$ ]]; then
  TMUX_SERVER_PID=$(tmux display-message -p '#{pid}' 2>/dev/null) || exit 0
fi

STATE_DIR="${TMUX_TMPDIR:-${XDG_RUNTIME_DIR:-/tmp}}/tmux-agent-state/$TMUX_SERVER_PID"

case "$PROVIDER" in
  claude|codex|opencode) ;;
  *) [[ "$COMMAND" == "clear" || "$COMMAND" == "refresh" ]] || exit 2 ;;
esac

state_file() {
  printf '%s/%s' "$STATE_DIR" "${1#%}"
}

priority() {
  case "$1" in
    error) printf '4' ;;
    attention) printf '3' ;;
    working) printf '2' ;;
    idle) printf '1' ;;
    *) printf '0' ;;
  esac
}

refresh_window() {
  local window_id pane file pane_provider pane_state pane_priority
  local best_priority=0 best_provider="" best_state=""

  window_id=$(tmux display-message -t "$PANE_ID" -p '#{window_id}' 2>/dev/null) || exit 0
  while IFS= read -r pane; do
    file=$(state_file "$pane")
    [[ -f "$file" ]] || continue
    IFS=$'\t' read -r pane_provider pane_state < "$file" || continue
    pane_priority=$(priority "$pane_state")
    if (( pane_priority > best_priority )); then
      best_priority=$pane_priority
      best_provider=$pane_provider
      best_state=$pane_state
    fi
  done < <(tmux list-panes -t "$window_id" -F '#{pane_id}' 2>/dev/null)

  if [[ -z "$best_state" ]]; then
    tmux set-option -wu -t "$window_id" @agent_provider 2>/dev/null || true
    tmux set-option -wu -t "$window_id" @agent_state 2>/dev/null || true
    tmux set-option -wu -t "$window_id" @agent_icon 2>/dev/null || true
    tmux set-option -wu -t "$window_id" @agent_tab_icon 2>/dev/null || true
    return
  fi

  tmux set-option -w -t "$window_id" @agent_provider "$best_provider"
  tmux set-option -w -t "$window_id" @agent_state "$best_state"
  case "$best_state" in
    error)
      tmux set-option -w -t "$window_id" @agent_icon " #[fg=#f7768e]󰧑 #[fg=default]"
      tmux set-option -w -t "$window_id" @agent_tab_icon " #[fg=#f7768e]󰧑 #[fg=default]"
      ;;
    attention)
      tmux set-option -w -t "$window_id" @agent_icon " #[fg=#e0af68]󰧑 #[fg=default]"
      tmux set-option -w -t "$window_id" @agent_tab_icon "#[fg=#e0af68,blink] 󰧑 #[noblink,fg=default]"
      ;;
    working)
      tmux set-option -w -t "$window_id" @agent_icon " #[fg=${AGENT_CYAN:-#7dcfff}]󰧑 #[fg=default]"
      tmux set-option -w -t "$window_id" @agent_tab_icon " #[fg=${AGENT_CYAN:-#7dcfff}]󰧑 #[fg=default]"
      ;;
    idle)
      tmux set-option -w -t "$window_id" @agent_icon " #[fg=#565f89]󰧑 #[fg=default]"
      tmux set-option -w -t "$window_id" @agent_tab_icon " #[fg=#565f89]󰧑 #[fg=default]"
      ;;
  esac
}

case "$COMMAND" in
  set)
    case "$STATE" in
      working|attention|idle|error) ;;
      *) exit 2 ;;
    esac
    mkdir -p "$STATE_DIR"
    printf '%s\t%s\n' "$PROVIDER" "$STATE" > "$(state_file "$PANE_ID")"
    refresh_window
    ;;
  clear)
    rm -f "$(state_file "$PANE_ID")"
    refresh_window
    ;;
  refresh)
    refresh_window
    ;;
  *)
    exit 2
    ;;
esac
