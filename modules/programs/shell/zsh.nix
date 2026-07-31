{pkgs, ...}: let
  commandPreview = pkgs.writeShellApplication {
    name = "zsh-command-preview";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.man-db
      pkgs.tealdeer
    ];
    text = ''
      command_name="''${1:-}"

      describe() {
        printf 'Command: %s\nTL;DR: %s\n' "$1" "$2"
      }

      cache_general_preview() {
        cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh-command-preview"
        cache_index=$(printf '%s' "$command_name" | cut -c1 | tr -c '[:alnum:]' '_')
        safe_name=$(printf '%s' "$command_name" | tr -c '[:alnum:]_.-' '_')

        if [ -z "$cache_index" ]; then
          cache_index="_"
        fi

        if [ -z "$safe_name" ]; then
          safe_name="_"
        fi

        cache_dir="$cache_root/$cache_index"
        cache_file="$cache_dir/$safe_name"

        if [ -s "$cache_file" ]; then
          cat "$cache_file"
          return
        fi

        mkdir -p "$cache_dir"
        tmp_file=$(mktemp "$cache_file.tmp.XXXXXX")

        if tldr --color always "$command_name" >"$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
          mv "$tmp_file" "$cache_file"
          cat "$cache_file"
          return
        fi

        if whatis "$command_name" >"$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
          {
            printf 'Command: %s\n' "$command_name"
            printf 'TL;DR: %s\n' "$(cat "$tmp_file")"
          } >"$cache_file"
          rm -f "$tmp_file"
          cat "$cache_file"
          return
        fi

        if type -a -- "$command_name" >"$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
          mv "$tmp_file" "$cache_file"
          cat "$cache_file"
          return
        fi

        rm -f "$tmp_file"
        describe "$command_name" "No preview metadata configured."
      }

      case "$command_name" in
        ga)
          describe "git add" "Stage paths for the next commit."
          ;;
        gaa)
          describe "git add ." "Stage changes under the current directory."
          ;;
        gaA)
          describe "git add -A" "Stage all changes, including deletions."
          ;;
        gb)
          describe "git branch" "List local branches."
          ;;
        gba)
          describe "git branch -a" "List local and remote-tracking branches."
          ;;
        gbc)
          describe "git checkout -b" "Create and switch to a new branch."
          ;;
        gbd)
          describe "git branch -d" "Delete a merged local branch."
          ;;
        gbD)
          describe "git branch -D" "Force-delete a local branch."
          ;;
        gca)
          describe "git commit -a -m" "Commit tracked changes with a message."
          ;;
        gcm)
          describe "git commit -m" "Commit staged changes with a message."
          ;;
        gco)
          describe "git checkout" "Switch branches or restore paths."
          ;;
        gcp)
          describe "git cherry-pick" "Apply an existing commit onto the current branch."
          ;;
        gd)
          describe "git diff" "Show unstaged changes."
          ;;
        gdc)
          describe "git diff --cached" "Show staged changes."
          ;;
        gds)
          describe "git diff --stat" "Summarize changed files and line counts."
          ;;
        gdt)
          describe "git difftool" "Open the configured git difftool."
          ;;
        gf)
          describe "git fetch --prune" "Fetch from the default remote and remove stale refs."
          ;;
        gfa)
          describe "git fetch --all --prune" "Fetch all remotes and remove stale refs."
          ;;
        gl)
          describe "git log --oneline --decorate --date=relative" "Compact history with branch/tag decorations."
          ;;
        glg)
          describe "git log --graph --oneline --decorate --all --date=relative" "Branch and merge graph across all refs."
          ;;
        gll)
          describe "git log --oneline --decorate --date=relative --max-count=20" "Last 20 commits in compact form."
          ;;
        glm)
          describe "git log --oneline --decorate --date=relative --author=<configured identity>" "Compact history for commits authored by you."
          ;;
        gls)
          describe "git log --stat --oneline --decorate --date=relative" "Compact history with per-commit file stats."
          ;;
        gm)
          describe "git merge" "Merge another branch into the current branch."
          ;;
        gma)
          describe "git merge --abort" "Abort an in-progress merge."
          ;;
        gpd)
          describe "git pull" "Fetch and integrate upstream changes."
          ;;
        gpp)
          describe "git pull && git push" "Update from upstream, then push."
          ;;
        gpt)
          describe "git tag -a <tag> -m <message> && git push origin <tag>" "Create an annotated tag if needed, then push it."
          ;;
        gpu)
          describe "git push -u origin HEAD" "Push current branch and set origin tracking."
          ;;
        grb)
          describe "git rebase" "Replay commits onto another base."
          ;;
        grba)
          describe "git rebase --abort" "Abort an in-progress rebase."
          ;;
        grbc)
          describe "git rebase --continue" "Continue an in-progress rebase after resolving conflicts."
          ;;
        groot)
          describe "cd \"\$(git rev-parse --show-toplevel)\"" "Jump to the current repository root."
          ;;
        grv)
          describe "git remote -v" "List remotes and fetch/push URLs."
          ;;
        gs)
          describe "git status" "Show working tree status."
          ;;
        gsa)
          describe "git stash --all" "Stash tracked, untracked, and ignored changes."
          ;;
        gshow)
          describe "git show --stat" "Show an object or commit with file stats."
          ;;
        gsl)
          describe "git stash list" "List stash entries."
          ;;
        gtidy)
          describe "git-tidy" "Clean up merged/gone branches and stale worktrees."
          ;;
        gwa)
          describe "git worktree add <path> <branch>" "Add a worktree for an existing branch."
          ;;
        gwan)
          describe "git worktree add -b <branch> <path>" "Add a worktree while creating a new branch."
          ;;
        gwl)
          describe "git worktree list" "List worktrees."
          ;;
        gwm)
          describe "git worktree move" "Move a worktree."
          ;;
        gwp)
          describe "git worktree prune" "Prune stale worktree metadata."
          ;;
        gwr)
          describe "git worktree remove" "Remove a worktree."
          ;;
        *)
          cache_general_preview
          ;;
      esac
    '';
  };
in {
  home.sessionVariables = {
    SHELL = "${pkgs.zsh}/bin/zsh";
  };

  home.file.".config/zsh/functions.zsh".text =
    # bash
    ''
      function ciStatus() {
        tag=$1
        glab ci status --branch "$tag" | grep "Pipeline state:" | sed "s/Pipeline state: \(.*\)/\1/"
      }

      function pbcopy() {
        local input
        input=$(cat)
        if command -v kitten &>/dev/null; then
          printf '%s' "$input" | kitten clipboard
        else
          printf '\e]52;c;%s\a' "$(printf '%s' "$input" | base64)"
        fi
      }

      function pbpaste() {
        if command -v kitten &>/dev/null; then
          kitten clipboard --get-clipboard
        else
          echo "pbpaste: OSC 52 does not support reading clipboard" >&2
          return 1
        fi
      }

      function waitForCi() {
        local ci_status
        tag=$1
        if ! command -v 'glab' &>/dev/null; then
          exit_with_error "glab command not found"
        fi

        >&2 echo "waiting for build to complete"
        ci_status="pending"
        while [[ $ci_status != "success" && $ci_status != "failed" ]]; do
          ci_status=$(ciStatus "$tag")
          >&2 echo "status: $ci_status"
          sleep 15
        done

        if [[ $ci_status != "success" ]]; then
          return 0
        else
          return 1
        fi
      }

    '';

  programs.zsh = {
    enable = true;
    package = pkgs.zsh;

    completionInit = ''
      fpath=("$HOME/.config/zsh/completions" $fpath)
      autoload -U compinit
      mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
      compinit -d "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
    '';

    history = {
      size = 10000;
      share = false;
      append = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      ignorePatterns = [
        "ls *"
        "cd *"
        "pwd *"
        "exit *"
        "clear *"
        "history *"
        "eza *"
        "eza -l -a *"
        "eza -la *"
        "eza --tree *"
        "procs *"
        "nvim *"
      ];
    };

    antidote = {
      enable = true;
      plugins = [
        "Aloxaf/fzf-tab"
        "cedi/meaningful-error-codes"
        "jeffreytse/zsh-vi-mode"
        "zdharma-continuum/fast-syntax-highlighting"
        "zsh-users/zsh-autosuggestions"
        "Freed-Wu/fzf-tab-source"
      ];
    };

    initContent =
      # bash
      ''
        source ~/.config/zsh/functions.zsh

        # Initialize atuin after zsh-vi-mode to prevent keybinding conflicts
        zvm_after_init_commands+=('eval "$(atuin init zsh)"')

        # Disable execute-named-cmd (Alt+x / Esc+x)
        zvm_after_init_commands+=('bindkey -r "\\ex"')

        # portable-ssh wraps ssh: bootstraps a nix-portable home-manager
        # environment on the remote (per ~/.config/portable-ssh/hosts.toml),
        # then execs `kitten ssh` if in kitty or plain ssh otherwise.
        # Falls through to a direct kitten ssh alias on hosts where
        # portable-ssh isn't installed (mac, remote shells reached via
        # kitten ssh) — kitten itself only exists in a desktop kitty
        # install, so the binary check is the right gate.
        if command -v portable-ssh &>/dev/null; then
          alias ssh="portable-ssh"
        elif [[ "$TERM_PROGRAM" == "kitty" ]] && command -v kitten &>/dev/null; then
          alias ssh="kitten ssh"
        fi
      ''
      + ''
        export DIRENV_LOG_FORMAT=""

        setopt nolistbeep
        zstyle ':completion:*' menu select

        # disable sort when completing `git checkout`
        zstyle ':completion:*:git-checkout:*' sort false
        # set descriptions format to enable group support
        # NOTE: don't use escape sequences (like '%F{red}%d%f') here, fzf-tab will ignore them
        zstyle ':completion:*:descriptions' format '[%d]'
        # force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
        zstyle ':completion:*' menu no
        # preview directory's content with eza when completing cd
        zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
        # preview command aliases/functions when completing command names
        zstyle ':fzf-tab:complete:(-command-:|command:option-(v|V)-rest)' fzf-preview '${commandPreview}/bin/zsh-command-preview $word'
        # custom fzf flags
        # NOTE: fzf-tab does not follow FZF_DEFAULT_OPTS by default
        zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
        # To make fzf-tab follow FZF_DEFAULT_OPTS.
        # NOTE: This may lead to unexpected behavior since some flags break this plugin. See Aloxaf/fzf-tab
        zstyle ':fzf-tab:*' use-fzf-default-opts yes
        # switch group using `<` and `>`
        zstyle ':fzf-tab:*' switch-group '<' '>'


        zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
        zstyle ':fzf-tab:*' popup-min-size 80 16
        #
        # zstyle ':completion:*' extra-verbose yes
        # zstyle ':completion:*:descriptions' format "%F{yellow}--- %d%f"
        # zstyle ':completion:*:messages' format '%d'
        # zstyle ':completion:*:warnings' format "%F{red}No matches for:%f %d"
        # zstyle ':completion:*:corrections' format '%B%d (errors: %e)%b'
        # zstyle ':completion:*' group-name \'\'
        # zstyle ':completion:*' auto-description 'specify: %d'
        # zstyle ':completion::complete:*' use-cache 1
        # zstyle ':completion:*:git-checkout:*' sort false
        # zstyle ':completion:*:descriptions' format '[%d]'
        # zstyle ':completion:*:git-checkout:*' sort false
        #
        # zstyle ':fzf-tab:complete:cd:*' fzf-preview 'exa -l --color=always --no-user --no-time --no-filesize --no-permissions --icons $realpath'
        # zstyle ':fzf-tab:complete:ls:*' fzf-preview '[ -f "$realpath" ] && bat --style=changes,rule,snip --color=always $realpath || exa -l --color=always --no-user --no-time --no-filesize --no-permissions --icons $realpath'
        # zstyle ':fzf-tab:complete:export:*' fzf-preview 'printenv $word'
        # zstyle ':fzf-tab:complete:ssh:*' fzf-preview 'ping -c1 $word'
        # zstyle ':fzf-tab:*' switch-group ',' '.'

      '';
  };
}
