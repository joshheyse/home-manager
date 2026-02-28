# shellcheck shell=bash
# PANE_ICON is injected by the Nix wrapper (default.nix)
# shellcheck disable=SC2154
host=$(ssh-fzf --print) || exit 0
[[ -z "$host" ]] && exit 0
tmux new-window -n "$host" "ssh $host"
tmux set-window-option @window_type ssh
tmux set-window-option @ssh_host "$host"
"$PANE_ICON" set ssh
