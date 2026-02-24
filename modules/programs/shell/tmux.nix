{pkgs, ...}: let
  claudeToggleScript =
    pkgs.writeShellScript "tmux-claude-toggle"
    # bash
    ''
      if tmux list-panes -F "#{pane_current_command}" | grep -q "claude"; then
        pane_id=$(tmux list-panes -F "#{pane_id}:#{pane_current_command}" | grep claude | head -1 | cut -d: -f1)
        tmux select-pane -t "$pane_id"
      else
        # Use zsh -i -c with eval to ensure direnv loads properly
        # The eval ensures the shell processes direnv hooks before running claude
        tmux split-window -fh -c "#{pane_current_path}" "zsh -i -c 'eval \"\$(direnv export zsh)\" && claude'"
        tmux select-pane -T "claude-code"
      fi
    '';

  smartSplitScript =
    pkgs.writeShellScript "tmux-smart-split"
    # bash
    ''
      # Get the current window name
      window_name=$(tmux display-message -p '#{window_name}')

      # Check if we're in an ssh: window
      if [[ "$window_name" =~ ^ssh:\ (.+)$ ]]; then
        # Extract the hostname (everything after "ssh: ")
        host="''${BASH_REMATCH[1]}"

        # Split with SSH to the same host, passing through split args
        tmux split-window "$@" -c "#{pane_current_path}" "ssh $host"
      else
        # Normal split for non-SSH windows
        tmux split-window "$@" -c "#{pane_current_path}"
      fi
    '';
in {
  programs.tmux = {
    enable = true;
    package = pkgs.tmux;
    shell = "${pkgs.zsh}/bin/zsh";
    baseIndex = 1;
    clock24 = true;
    disableConfirmationPrompt = true;
    escapeTime = 0;
    focusEvents = true;
    keyMode = "vi";
    mouse = true;
    sensibleOnTop = true;
    terminal = "xterm-kitty";
    prefix = "C-Space";

    plugins = with pkgs; [
      tmuxPlugins.sensible
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.pain-control
      tmuxPlugins.vim-tmux-navigator

      {
        plugin = tmuxPlugins.tmux-fzf;
        extraConfig =
          # tmux
          ''
            bind-key -N "Launch tmux-fzf" f run-shell -b "${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/main.sh"
            bind-key -N "Launch tmux-fzf window switcher" w run-shell -b "${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/scripts/window.sh switch"
          '';
      }

      tmuxPlugins.battery
      tmuxPlugins.copy-toolkit
      tmuxPlugins.cpu
      tmuxPlugins.jump
      tmuxPlugins.logging
      tmuxPlugins.sysstat
      {
        plugin = tmuxPlugins.tmux-which-key;
        extraConfig =
          # tmux
          ''
            set -g @tmux-which-key-xdg-enable 1;
            set -g @tmux-which-key-disable-autobuild 1
            set -g @tmux-which-key-xdg-plugin-path "tmux/plugins/tmux-which-key"
          '';
      }
      tmuxPlugins.weather
      tmuxPlugins.yank

      {
        plugin = tmuxPlugins.tokyo-night-tmux;
        extraConfig =
          # tmux
          ''
            set -g @tokyo-night-tmux_theme night
            set -g @tokyo-night-tmux_transparent 1
            set -g @tokyo-night-tmux_show_datetime 1
            set -g @tokyo-night-tmux_date_format MYD
            set -g @tokyo-night-tmux_time_format 24H
            set -g @tokyo-night-tmux_show_music 1
            set -g @tokyo-night-tmux_show_battery_widget 0
            set -g @tokyo-night-tmux_show_git 0
            set -g @tokyo-night-tmux_show_netspeed 1
            set -g @tokyo-night-tmux_netspeed_showip 1
            set -g @tokyo-night-tmux_netspeed_refresh 1
            set -g @tokyo-night-tmux_window_id_style none
          '';
      }
    ];

    extraConfig =
      # tmux
      ''
        # Set default command to use zsh (macOS fix)
        set -g default-command "${pkgs.zsh}/bin/zsh"

        # Allow passthrough for Kitty graphics protocol (required for image.nvim)
        set -g allow-passthrough on
        set -ga update-environment TERM
        set -ga update-environment TERM_PROGRAM

        # Unbind keys
        unbind-key "}"
        unbind-key "v"
        unbind-key "s"
        unbind-key "r"

        bind-key -N "Reload tmux config" r source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded!"

        bind-key -N "New pane to the right" "\\" run-shell '${smartSplitScript} -h'
        bind-key -N "New outer pane to the right" "|" run-shell '${smartSplitScript} -fh'
        bind-key -N "New pane to the bottom" "-" run-shell '${smartSplitScript} -v'
        bind-key -N "New outer pane to the bottom" "_" run-shell '${smartSplitScript} -fv'

        bind-key -N "New window" "c" new-window -c "#{pane_current_path}"

        bind-key -N "Move window left" -r "<" swap-window -d -t -1
        bind-key -N "Move window right" -r ">" swap-window -d -t +1

        pane_resize="10"
        bind-key -N "Resize Pane Left" -r H resize-pane -L $pane_resize
        bind-key -N "Resize Pane Down" -r J resize-pane -D $pane_resize
        bind-key -N "Resize Pane Up" -r K resize-pane -U $pane_resize
        bind-key -N "Resize Pane Right" -r L resize-pane -R $pane_resize

        bind-key -N "Enter copy-mode" "]" copy-mode
        bind-key -N "Enter copy-mode" "}" copy-mode

        bind-key -N "Leave copy-mode" -T copy-mode-vi "Escape" send-keys -X cancel
        bind-key -N "Begin Selection" -T copy-mode-vi "v" send-keys -X begin-selection
        bind-key -N "Copy Selection" -T copy-mode-vi "y" send-keys -X copy-selection
        bind-key -N "Begin Rect Selection" -T copy-mode-vi "r" send-keys -X rectangle-toggle

        bind-key -N "Select the pane to the left of the active pane" -T copy-mode-vi 'C-h' select-pane -L
        bind-key -N "Select the pane below the active pane" -T copy-mode-vi 'C-j' select-pane -D
        bind-key -N "Select the pane above the active pane" -T copy-mode-vi 'C-k' select-pane -U
        bind-key -N "Select the pane to the right of the active pane" -T copy-mode-vi 'C-l' select-pane -R
        bind-key -N "Move to the previously active pane" -T copy-mode-vi 'C-\' select-pane -l

        bind-key -N "Open lazygit in popup" g display-popup -d '#{pane_current_path}' -w90% -h90% -E lazygit
        bind-key -N "Launch ssh-fzf in popup" s display-popup -d '#{pane_current_path}' -w80% -h60% -E ssh-fzf
        bind-key -N "Open/focus claude-code pane" a run-shell '${claudeToggleScript}'

      '';
  };

  home.sessionVariables = {
    TMUX_TMPDIR = "\${XDG_RUNTIME_DIR:-/tmp}";
  };

  home.shellAliases = {
    rc = "reset && tmux clear-history";
  };
}
