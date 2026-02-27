# shellcheck shell=bash
host=$(ssh-fzf --print) || exit 0
[[ -z "$host" ]] && exit 0
tmux new-window -n "ssh: $host" "ssh $host"
