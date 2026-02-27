{
  pkgs,
  lib,
  ...
}: let
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

  sshFzfScript =
    pkgs.writeShellScript "tmux-ssh-fzf"
    # bash
    ''
      host=$(ssh-fzf --print) || exit 0
      [[ -z "$host" ]] && exit 0
      tmux new-window -n "ssh: $host" "ssh $host"
    '';

  devWorkspaceScript =
    pkgs.writeShellScript "tmux-dev-workspace"
    # bash
    ''
      set -euo pipefail

      DEV_ROOT="''${TMUX_DEV_ROOT:-$HOME/code}"
      HISTORY_DIR="$HOME/.local/state/tmux-dev-workspaces"
      HISTORY_FILE="$HISTORY_DIR/history"

      mkdir -p "$HISTORY_DIR"
      touch "$HISTORY_FILE"

      update_history() {
        local dir="$1"
        grep -vxF "$dir" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" || true
        { echo "$dir"; cat "$HISTORY_FILE.tmp"; } > "$HISTORY_FILE"
        rm -f "$HISTORY_FILE.tmp"
      }

      resolve_path() {
        local input="$1"
        if [[ "$input" = /* ]]; then
          echo "$input"
        elif [[ "$input" = */* ]]; then
          (cd "$DEV_ROOT" && cd "$input" && pwd)
        else
          echo "$DEV_ROOT/$input"
        fi
      }

      create_workspace() {
        local project_dir="$1"
        local allow_inplace="''${2:-false}"
        local project_name window_name
        project_name=$(basename "$project_dir")
        window_name="dev: $project_name"

        # Check if workspace already exists
        local existing_window
        existing_window=$(tmux list-windows -F '#{window_index}:#{window_name}' 2>/dev/null \
          | grep -F "$window_name" \
          | head -1 \
          | cut -d: -f1) || true

        if [[ -n "$existing_window" ]]; then
          tmux select-window -t "$existing_window"
          return
        fi

        local inplace=false
        if [[ "$allow_inplace" == "true" ]]; then
          local pane_count
          pane_count=$(tmux list-panes 2>/dev/null | wc -l | tr -d ' ')
          if [[ "$pane_count" -le 1 ]]; then
            inplace=true
          fi
        fi

        if [[ "$inplace" == "true" ]]; then
          tmux rename-window "$window_name"
        else
          tmux new-window -n "$window_name" -c "$project_dir" \
            "zsh -i -c 'eval \"\$(direnv export zsh 2>/dev/null)\" && nvim'"
        fi

        # Claude pane (right, 40% width, full height)
        tmux split-window -h -l 40% -c "$project_dir" \
          "zsh -i -c 'eval \"\$(direnv export zsh 2>/dev/null)\" && claude'"

        # Terminal pane (bottom-left, 30% height)
        tmux select-pane -t 0
        tmux split-window -v -l 30% -c "$project_dir"

        # Focus nvim/main pane
        tmux select-pane -t 0

        if [[ "$inplace" == "true" ]]; then
          # Signal to wrapper to exec nvim
          echo "$project_dir"
        fi
      }

      if [[ "''${1:-}" == "--pick" ]]; then
        shift

        build_list() {
          local -A seen

          while IFS= read -r dir; do
            if [[ -n "$dir" && -d "$dir" ]]; then
              local name
              name=$(basename "$dir")
              if tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qF "dev: $name"; then
                echo "* $dir"
              else
                echo "  $dir"
              fi
              seen["$dir"]=1
            fi
          done < "$HISTORY_FILE"

          if [[ -d "$DEV_ROOT" ]]; then
            for dir in "$DEV_ROOT"/*/; do
              dir="''${dir%/}"
              if [[ -d "$dir" && -z "''${seen[$dir]:-}" ]]; then
                local name
                name=$(basename "$dir")
                if tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qF "dev: $name"; then
                  echo "* $dir"
                else
                  echo "  $dir"
                fi
              fi
            done
          fi
        }

        selection=$(build_list | fzf \
          --prompt="Dev Workspace: " \
          --header="Select project (* = open) or type path" \
          --height=100% \
          --reverse \
          --border \
          --print-query \
          --bind="enter:accept-or-print-query" \
          --nth=2 \
          --with-nth=1,2 \
          --preview='dir=$(echo {} | sed "s/^[* ] //"); echo "Project: $(basename "$dir")"; echo "Path: $dir"; echo; if [[ -f "$dir/README.md" ]]; then head -20 "$dir/README.md"; elif [[ -f "$dir/README" ]]; then head -20 "$dir/README"; else ls -la "$dir" 2>/dev/null | head -20; fi' \
          --preview-window="right:50%" \
          "$@" | tail -1)

        selection=$(echo "$selection" | sed 's/^[* ] //')

        if [[ -z "$selection" ]]; then
          exit 0
        fi

        project_dir=$(resolve_path "$selection")

        if [[ ! -d "$project_dir" ]]; then
          echo "Directory does not exist: $project_dir" >&2
          exit 1
        fi

        update_history "$project_dir"
        create_workspace "$project_dir" false
      else
        input="''${1:-$(pwd)}"
        project_dir=$(resolve_path "$input")

        if [[ ! -d "$project_dir" ]]; then
          echo "Directory does not exist: $project_dir" >&2
          exit 1
        fi

        update_history "$project_dir"
        create_workspace "$project_dir" true
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

        # Show directory basename as window name instead of process name
        set -g automatic-rename-format '#{b:pane_current_path}'

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
        bind-key -N "Launch ssh-fzf in popup" s display-popup -d '#{pane_current_path}' -w80% -h60% -E '${sshFzfScript}'
        bind-key -N "Open dev workspace picker" d display-popup -d '#{pane_current_path}' -w80% -h80% -E '${devWorkspaceScript} --pick'
        bind-key -N "Open/focus claude-code pane" a run-shell '${claudeToggleScript}'
        bind-key -N "Show key bindings" ? display-popup -w80% -h80% -E "tmux list-keys -N | ''${PAGER:-less}"

      '';
  };

  home = {
    packages = [
      (pkgs.writeShellScriptBin "dev" ''
        inplace_dir=$(${devWorkspaceScript} "''${1:-$(pwd)}")
        if [[ -n "''${inplace_dir:-}" ]]; then
          cd "$inplace_dir" || exit 1
          exec zsh -i -c 'eval "$(direnv export zsh 2>/dev/null)" && nvim'
        fi
      '')
    ];

    sessionVariables = {
      TMUX_TMPDIR = lib.mkForce "\${XDG_RUNTIME_DIR:-/tmp}";
    };

    shellAliases = {
      rc = "reset && tmux clear-history";
    };
  };
}
