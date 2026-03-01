{pkgs, ...}: {
  home.file.".config/zsh/functions.zsh".text =
    # bash
    ''
      function gpt() {
        tag=$1
        if [ -z "$tag" ]; then
          echo "Tag name is required"
          return 1
        fi
        message=$2
        ((git tag | grep $1) || git tag -a $1 -m "''${message:-"tagging $1"}") && git push origin $1
      }

      function ciStatus() {
        tag=$1
        glab ci status --branch "$tag" | grep "Pipeline state:" | sed "s/Pipeline state: \(.*\)/\1/"
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

    history = {
      size = 10000;
      share = true;
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
          source <(fzf --zsh)
        source ~/.config/zsh/functions.zsh

        # Use kitten ssh for proper terminal/keyboard protocol propagation
        if [[ "$TERM_PROGRAM" == "kitty" ]]; then
          alias ssh="kitten ssh"
        fi

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
        # custom fzf flags
        # NOTE: fzf-tab does not follow FZF_DEFAULT_OPTS by default
        zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
        # To make fzf-tab follow FZF_DEFAULT_OPTS.
        # NOTE: This may lead to unexpected behavior since some flags break this plugin. See Aloxaf/fzf-tab
        zstyle ':fzf-tab:*' use-fzf-default-opts yes
        # switch group using `<` and `>`
        zstyle ':fzf-tab:*' switch-group '<' '>'


        zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
        zstyle ':fzf-tab:*' popup-min-size 1200 16
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
