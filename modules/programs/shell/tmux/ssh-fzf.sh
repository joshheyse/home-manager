# shellcheck shell=bash
# PANE_ICON and SSH_CMD are injected by the Nix wrapper (default.nix).
# SSH_CMD is portable-ssh on Linux (which prompts for a per-host profile
# on first use and saves to ~/.config/portable-ssh/hosts.toml) and plain
# ssh on darwin where portable-ssh is not installed.
# shellcheck disable=SC2154
host=$(ssh-fzf --print) || exit 0
[[ -z "$host" ]] && exit 0
tmux new-window -n "$host" "$SSH_CMD $host"
tmux set-window-option @window_type ssh
tmux set-window-option @ssh_host "$host"
"$PANE_ICON" set ssh
