# shellcheck shell=bash
set -euo pipefail

AGENT="${TMUX_DEV_AGENT:-claude}"
case "$AGENT" in
  claude|codex|opencode) ;;
  *)
    tmux display-message "Unsupported TMUX_DEV_AGENT: $AGENT"
    exit 2
    ;;
esac

pane_id=$(tmux list-panes -F '#{pane_id}\t#{@pane_role}' \
  | awk -F '\t' '$2 == "agent" { print $1; exit }')

if [[ -n "$pane_id" ]]; then
  tmux select-pane -t "$pane_id"
else
  tmux split-window -fh -c '#{pane_current_path}' \
    "zsh -i -c 'eval \"\$(direnv export zsh 2>/dev/null)\" && $AGENT'"
  tmux set-option -p @pane_role agent
  tmux set-option -p @agent_provider "$AGENT"
  tmux select-pane -T "$AGENT"
fi
