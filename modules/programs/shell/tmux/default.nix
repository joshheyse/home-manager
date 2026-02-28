{
  pkgs,
  lib,
  ...
}: let
  claudeToggleScript = pkgs.writeShellScript "tmux-claude-toggle" (builtins.readFile ./claude-toggle.sh);
  smartSplitScript = pkgs.writeShellScript "tmux-smart-split" (builtins.readFile ./smart-split.sh);
  sshFzfScript = pkgs.writeShellScript "tmux-ssh-fzf" (builtins.readFile ./ssh-fzf.sh);
  devWorkspaceScript = pkgs.writeShellScript "tmux-dev-workspace" (builtins.readFile ./dev-workspace.sh);

  # Claude Code tmux integration scripts
  notifyPkg = pkgs.callPackage ../../../../pkgs/notify {};
  claudeHookScript = pkgs.writeShellScript "tmux-claude-hook" ''
    export PATH="${lib.makeBinPath [pkgs.jq pkgs.tmux notifyPkg]}:$PATH"
    ${builtins.readFile ./claude-hook.sh}
  '';
  claudeRespondScript = pkgs.writeShellScript "tmux-claude-respond" ''
    export PATH="${lib.makeBinPath [pkgs.jq pkgs.tmux]}:$PATH"
    ${builtins.readFile ./claude-respond.sh}
  '';
  claudeHasPromptScript = pkgs.writeShellScript "tmux-claude-has-prompt" ''
    export PATH="${lib.makeBinPath [pkgs.tmux]}:$PATH"
    ${builtins.readFile ./claude-has-prompt.sh}
  '';
  claudeSetupScript = pkgs.writeShellScript "tmux-claude-setup" ''
    # Inject #{@claude_icon} into window-status-format (after #W) if not already present
    for fmt_opt in window-status-format window-status-current-format; do
      current=$(${pkgs.tmux}/bin/tmux show -gv "$fmt_opt" 2>/dev/null)
      if [[ "$current" != *"@claude_icon"* ]]; then
        updated=$(printf '%s' "$current" | ${pkgs.gnused}/bin/sed 's/#W/#W#{@claude_icon}/g')
        ${pkgs.tmux}/bin/tmux set -g "$fmt_opt" "$updated"
      fi
    done
  '';

  # Claude settings with hooks configuration
  claudeSettings = builtins.toJSON {
    enabledPlugins = {
      "clangd-lsp@claude-plugins-official" = true;
    };
    hooks = {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} start";
            }
          ];
        }
      ];
      UserPromptSubmit = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} submit";
            }
          ];
        }
      ];
      PermissionRequest = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} permission";
              timeout = 300;
            }
          ];
        }
      ];
      Notification = [
        {
          matcher = "elicitation_dialog";
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} question";
            }
          ];
        }
        {
          matcher = "idle_prompt";
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} idle";
            }
          ];
        }
      ];
      PostToolUse = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} tool-done";
            }
          ];
        }
      ];
      PostToolUseFailure = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} tool-done";
            }
          ];
        }
      ];
      Stop = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} stop";
            }
          ];
        }
      ];
      SessionEnd = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookScript} end";
            }
          ];
        }
      ];
    };
  };
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

        # Show directory basename as window name instead of process name
        set -g automatic-rename-format '#{b:pane_current_path}'

        # Allow passthrough for Kitty graphics protocol (required for image.nvim)
        set -g allow-passthrough on
        set -ga update-environment TERM
        set -ga update-environment TERM_PROGRAM

        # Enable extended keys (CSI u / kitty keyboard protocol) for proper F-key support
        set -g extended-keys on
        set -as terminal-features 'xterm*:extkeys'

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
        bind-key -N "Launch ssh-fzf in popup" s display-popup -d '#{pane_current_path}' -w80% -h60% -E '${sshFzfScript}'
        bind-key -N "Open dev workspace picker" d display-popup -d '#{pane_current_path}' -w80% -h80% -E '${devWorkspaceScript} --pick'
        bind-key -N "Open/focus claude-code pane" a run-shell '${claudeToggleScript}'
        bind-key -N "Show key bindings" ? display-popup -w75% -h75% -E 'sh -c "tmux list-keys -N | ''${PAGER:-less}"'

        # Claude Code integration: inject icon into window tab (runs after tokyo-night theme sets formats)
        run-shell '${claudeSetupScript}'

        # Faster status refresh for Claude icon responsiveness
        set -g status-interval 3

        # F-key bindings: active when Claude has a prompt, otherwise pass through
        bind-key -N "Claude: Allow / Option 1" -T root F1 if-shell '${claudeHasPromptScript}' \
          'run-shell "${claudeRespondScript} 1"' 'send-keys F1'
        bind-key -N "Claude: Allow always / Option 2" -T root F2 if-shell '${claudeHasPromptScript}' \
          'run-shell "${claudeRespondScript} 2"' 'send-keys F2'
        bind-key -N "Claude: Deny / Option 3" -T root F3 if-shell '${claudeHasPromptScript}' \
          'run-shell "${claudeRespondScript} 3"' 'send-keys F3'
        bind-key -N "Claude: Focus Claude pane" -T root F4 if-shell '${claudeHasPromptScript}' \
          'run-shell "${claudeRespondScript} focus"' 'send-keys F4'

      '';
  };

  home = {
    activation = {
      tmuxReload = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if ${pkgs.tmux}/bin/tmux info &>/dev/null; then
          ${pkgs.tmux}/bin/tmux source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded!" || true
        fi
      '';
    };

    packages = [
      (pkgs.writeShellScriptBin "dev" ''
        inplace_dir=$(${devWorkspaceScript} "''${1:-$(pwd)}")
        if [[ -n "''${inplace_dir:-}" ]]; then
          cd "$inplace_dir" || exit 1
          exec zsh -i -c 'eval "$(direnv export zsh 2>/dev/null)" && nvim'
        fi
      '')
    ];

    # Claude Code settings with hooks for tmux integration
    file.".claude/settings.json".text = claudeSettings;

    sessionVariables = {
      TMUX_TMPDIR = lib.mkForce "\${XDG_RUNTIME_DIR:-/tmp}";
    };

    shellAliases = {
      rc = "reset && tmux clear-history";
    };
  };
}
