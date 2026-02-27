# shellcheck shell=bash
if tmux list-panes -F "#{pane_current_command}" | grep -q "claude"; then
  pane_id=$(tmux list-panes -F "#{pane_id}:#{pane_current_command}" | grep claude | head -1 | cut -d: -f1)
  tmux select-pane -t "$pane_id"
else
  # Use zsh -i -c with eval to ensure direnv loads properly
  # The eval ensures the shell processes direnv hooks before running claude
  tmux split-window -fh -c "#{pane_current_path}" "zsh -i -c 'eval \"\$(direnv export zsh)\" && claude'"
  tmux select-pane -T "claude-code"
fi
