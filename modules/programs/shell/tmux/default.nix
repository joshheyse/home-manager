{
  config,
  pkgs,
  lib,
  ...
}: let
  hasWaybar = config.programs.hyprland-desktop.enable or false;
  theme = config.theme.tokyoNight;

  # Window type icon system
  paneIconScript = pkgs.writeShellScript "tmux-pane-icon" (builtins.readFile ./pane-icon.sh);
  iconSetupScript = pkgs.writeShellScript "tmux-icon-setup" ''
    export PATH="${lib.makeBinPath [pkgs.tmux]}:$PATH"
    ${builtins.readFile ./icon-setup.sh}
  '';

  netspeedScript = pkgs.writeShellScript "tmux-netspeed" ''
    export PATH="${lib.makeBinPath [pkgs.tmux pkgs.bc]}:$PATH"
    ${builtins.readFile ./netspeed.sh}
  '';
  netspeedSetupScript = pkgs.writeShellScript "tmux-netspeed-setup" ''
    # Swap the theme's netspeed.sh with our fixed-width version in status-right
    current=$(${pkgs.tmux}/bin/tmux show -gv status-right 2>/dev/null) || exit 0
    updated=$(printf '%s' "$current" | ${pkgs.gnused}/bin/sed "s|#([^)]*netspeed\.sh)|#(${netspeedScript})|g")
    ${pkgs.tmux}/bin/tmux set -g status-right "$updated"
  '';
  devStatusScript = pkgs.writeShellScript "tmux-dev-status" ''
    export PATH="${lib.makeBinPath [pkgs.direnv pkgs.gnused pkgs.starship pkgs.coreutils]}:$PATH"
    export DEV_STATUS_BLUE="${theme.blue}"
    export DEV_STATUS_BLUE1="${theme.blue1}"
    export DEV_STATUS_BLUE5="${theme.blue5}"
    export DEV_STATUS_CYAN="${theme.cyan}"
    export DEV_STATUS_ORANGE="${theme.orange}"
    export DEV_STATUS_YELLOW="${theme.yellow}"
    ${builtins.readFile ./dev-status.sh}
  '';
  statusRightSetupScript = pkgs.writeShellScript "tmux-status-right-setup" ''
    # Starship supplies directory/Git/dev-shell context every status interval.
    # Provider and state reserve fixed-width fields, so lifecycle transitions
    # never shift the bar.
    dev_right='#(${devStatusScript} #{q:pane_current_path})  #[fg=${theme.blue5}]#{p-8:#{=8:#{@agent_provider}}}#{?#{@agent_icon},#{@agent_icon},   }'
    ${pkgs.tmux}/bin/tmux set -g @dev_status_right "$dev_right"

    ${
      if hasWaybar
      then ''
        # Waybar carries local system information; dev windows replace the
        # otherwise empty right side with workspace-specific information.
        ${pkgs.tmux}/bin/tmux set -g status-right '#{?#{==:#{@window_type},dev},#{E:@dev_status_right},}'
      ''
      else ''
        # Preserve the theme's widgets for ordinary remote/macOS windows, but
        # replace them while the selected window is a dev workspace.
        default_right=$(${pkgs.tmux}/bin/tmux show -gv status-right 2>/dev/null) || exit 0
        ${pkgs.tmux}/bin/tmux set -g @non_dev_status_right "$default_right"
        ${pkgs.tmux}/bin/tmux set -g status-right '#{?#{==:#{@window_type},dev},#{E:@dev_status_right},#{E:@non_dev_status_right}}'
      ''
    }
  '';

  agentToggleScript = pkgs.writeShellScript "tmux-agent-toggle" (builtins.readFile ./agent-toggle.sh);
  smartSplitScript = pkgs.writeShellScript "tmux-smart-split" (builtins.readFile ./smart-split.sh);
  sshFzfScript = pkgs.writeShellScript "tmux-ssh-fzf" ''
    export PANE_ICON="${paneIconScript}"
    ${builtins.readFile ./ssh-fzf.sh}
  '';
  devWorkspaceScript = pkgs.writeShellScript "tmux-dev-workspace" ''
    export PANE_ICON="${paneIconScript}"
    export PATH="${lib.makeBinPath [pkgs.git]}:$PATH"
    ${builtins.readFile ./dev-workspace.sh}
  '';

  # Provider-neutral agent state, with thin lifecycle-hook adapters.
  agentStateScript = pkgs.writeShellScript "tmux-agent-state" ''
    export PATH="${lib.makeBinPath [pkgs.tmux]}:$PATH"
    export AGENT_CYAN="${theme.cyan}"
    ${builtins.readFile ./agent-state.sh}
  '';
  agentHookScript = pkgs.writeShellScript "tmux-agent-hook" ''
    export PATH="${lib.makeBinPath [pkgs.jq pkgs.tmux pkgs.notify]}:$PATH"
    export AGENT_STATE_COMMAND="${agentStateScript}"
    ${builtins.readFile ./agent-hook.sh}
  '';
  agentHookCommand = "${config.home.homeDirectory}/.local/bin/tmux-agent-hook";
  agentSetupScript = pkgs.writeShellScript "tmux-agent-setup" ''
    # Inject #{@agent_tab_icon} into custom window formats that lack the slot.
    for fmt_opt in window-status-format window-status-current-format; do
      current=$(${pkgs.tmux}/bin/tmux show -gv "$fmt_opt" 2>/dev/null)
      if [[ "$current" != *"@agent_tab_icon"* ]]; then
        updated=$(printf '%s' "$current" | ${pkgs.gnused}/bin/sed 's/#W/#W#{@agent_tab_icon}/g')
        ${pkgs.tmux}/bin/tmux set -g "$fmt_opt" "$updated"
      fi
    done
  '';
  tmuxReloadScript = pkgs.writeShellScript "tmux-reload" ''
    if ${pkgs.tmux}/bin/tmux source-file ~/.config/tmux/tmux.conf >/dev/null; then
      while IFS= read -r pane_id; do
        TMUX_PANE="$pane_id" ${agentStateScript} refresh
      done < <(${pkgs.tmux}/bin/tmux list-panes -a -F '#{pane_id}')
      ${pkgs.tmux}/bin/tmux display-message "Config reloaded!"
      exit 0
    else
      status=$?
    fi

    ${pkgs.tmux}/bin/tmux display-message "Tmux config reload failed (exit $status)" || true
    exit "$status"
  '';
  codexHook = event: {
    hooks = [
      {
        type = "command";
        command = "${agentHookCommand} codex ${event}";
        timeout = 3;
      }
    ];
  };
  codexHooksFile = pkgs.writeText "codex-tmux-hooks.json" (builtins.toJSON {
    description = "Update provider-neutral tmux agent state.";
    hooks = {
      SessionStart = [
        ((codexHook "start") // {matcher = "startup|resume|clear";})
      ];
      UserPromptSubmit = [(codexHook "submit")];
      PermissionRequest = [(codexHook "permission")];
      PostToolUse = [(codexHook "working")];
      Stop = [(codexHook "stop")];
      SessionEnd = [(codexHook "end")];
    };
  });
in {
  config = {
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
      terminal = "tmux-256color";
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
          set -g visual-activity off
          set -g visual-bell off

          set -ga update-environment TERM
          set -ga update-environment TERM_PROGRAM

          # Enable extended keys (CSI u) - 'on' lets apps opt-in via XTMODKEYS.
          # Using 'always' would re-encode ALL modified keys (breaking Shift+Tab etc).
          set -g extended-keys on
          set -as terminal-features 'xterm*:extkeys'

          # Forward Shift+Enter as CSI u format to applications.
          # Kitty sends \e[13;2u via its keybinding, tmux recognizes it as S-Enter
          # and we forward it in the same CSI u format that Claude Code expects.
          bind-key -n S-Enter send-keys Escape "[13;2u"

          # Unbind keys
          unbind-key "}"
          unbind-key "v"
          unbind-key "s"
          unbind-key "r"

          # tmux-which-key's generated init file uses `display -p` while being
          # sourced. Run the reload through the shell and discard stdout only;
          # genuine source/configuration errors remain visible on stderr.
          bind-key -N "Reload tmux config" r run-shell '${tmuxReloadScript}'

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
          bind-key -N "Open/focus agent pane" a run-shell '${agentToggleScript}'
          bind-key -N "Show key bindings" ? display-popup -w75% -h75% -E 'sh -c "tmux list-keys -N | ''${PAGER:-less}"'

          # Post-theme customizations (runs after tokyo-night theme sets formats)
          run-shell '${iconSetupScript}'
          run-shell '${netspeedSetupScript}'
          run-shell '${statusRightSetupScript}'

          # Agent integration: inject the fixed icon slot if a custom format
          # replaced ours, then keep lifecycle transitions responsive.
          run-shell '${agentSetupScript}'

          set -g status-interval 5

        '';
    };

    home = {
      activation = {
        tmuxReload = lib.hm.dag.entryAfter ["writeBoundary"] ''
          if ${pkgs.tmux}/bin/tmux info &>/dev/null; then
            ${tmuxReloadScript} || true
          fi
        '';
      };

      packages = [
        (pkgs.writeShellScriptBin "dev" ''
          set -euo pipefail

          inplace_dir=$(${devWorkspaceScript} "$@")
          if [[ -n "''${inplace_dir:-}" ]]; then
            cd "$inplace_dir" || exit 1
            eval "$(direnv export zsh 2>/dev/null)"
            nvim
            exec zsh -i
          fi
        '')
      ];

      file.".codex/hooks.json".source = codexHooksFile;
      file.".local/bin/tmux-agent-hook" = {
        source = agentHookScript;
        executable = true;
      };

      sessionVariables = {
        TMUX_TMPDIR = lib.mkForce "\${XDG_RUNTIME_DIR:-/tmp}";
      };

      shellAliases = {
        rc = "reset && tmux clear-history";
      };
    };

    xdg.configFile."opencode/plugins/tmux-agent-state.js".text = ''
      const stateCommand = ${builtins.toJSON (toString agentStateScript)};

      async function setState($, state) {
        await $`''${stateCommand} set opencode ''${state}`.quiet();
      }

      export const TmuxAgentState = async ({ $ }) => ({
        event: async ({ event }) => {
          switch (event.type) {
            case "session.created":
            case "session.idle":
              await setState($, "idle");
              break;
            case "session.status": {
              const status = event.properties?.status?.type;
              if (status === "idle") await setState($, "idle");
              else if (status === "busy" || status === "retry") await setState($, "working");
              break;
            }
            case "permission.asked":
              await setState($, "attention");
              break;
            case "permission.replied":
              await setState($, "working");
              break;
            case "session.error":
              await setState($, "error");
              break;
            case "session.deleted":
              await $`''${stateCommand} clear`.quiet();
              break;
          }
        },
      });
    '';

    programs.claude-code.settings.hooks = {
      SessionStart = [
        {
          matcher = "startup|resume|clear";
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude start";
            }
          ];
        }
      ];
      UserPromptSubmit = [
        {
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude submit";
            }
          ];
        }
      ];
      Notification = [
        {
          matcher = "permission_prompt";
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude permission";
            }
          ];
        }
        {
          matcher = "elicitation_dialog";
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude attention";
            }
          ];
        }
        {
          matcher = "idle_prompt";
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude idle";
            }
          ];
        }
      ];
      Stop = [
        {
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude stop";
            }
          ];
        }
      ];
      StopFailure = [
        {
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude error";
            }
          ];
        }
      ];
      SessionEnd = [
        {
          hooks = [
            {
              type = "command";
              command = "${agentHookCommand} claude end";
            }
          ];
        }
      ];
    };
  };
}
