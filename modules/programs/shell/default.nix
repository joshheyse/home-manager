{
  pkgs,
  lib,
  config,
  ...
}: let
  theme = config.theme.tokyoNight;
  pagerPkg = pkgs.moor;

  # Convert "#rrggbb" hex to "r;g;b" decimal for ANSI escape sequences
  hexToRgb = hex: let
    hexStr = builtins.substring 1 6 hex;
    r = builtins.fromTOML "v = 0x${builtins.substring 0 2 hexStr}";
    g = builtins.fromTOML "v = 0x${builtins.substring 2 2 hexStr}";
    b = builtins.fromTOML "v = 0x${builtins.substring 4 2 hexStr}";
  in "${toString r.v};${toString g.v};${toString b.v}";
in {
  home.sessionVariables = {
    PAGER = "moor";
    MANPAGER = "moor";
    MOOR = "--style=tokyonight-night --statusbar=bold --terminal-fg";
    # less defaults: -i smart-case search, -M long prompt, -R raw ANSI colors
    # (so escape sequences don't render as literal characters), -F quit if
    # output fits one screen, -X don't send termcap init/deinit (no screen clear).
    LESS = "-iMRFX";
    CPM_SOURCE_CACHE = "${config.home.homeDirectory}/.cache/CPM";
    # NOTE: LESS_TERMCAP_so/se (less standout = search highlight + statusbar)
    # are set in programs.zsh.initContent below, not here. home.sessionVariables
    # emits POSIX `export VAR="..."` which leaves `\e` literal, so less would
    # print the raw escape text. zsh `$'\e'` produces a real ESC byte.
    # notcurses (lnav etc.) ignores ~/.terminfo and has a compiled-in path
    # that misses nix profiles. Point terminfo lookup at the active profile,
    # the default profile, and the system path so xterm-kitty resolves.
    TERMINFO_DIRS = "${config.home.homeDirectory}/.nix-profile/share/terminfo:/nix/var/nix/profiles/default/share/terminfo:/run/current-system/sw/share/terminfo:/usr/share/terminfo";
  };

  imports = [
    ../../theme.nix
    ./atuin.nix
    ./bat.nix
    ./bazel
    ./bottom.nix
    ./btop.nix
    ./claude-code
    ./direnv.nix
    ./eza.nix
    ./fd.nix
    ./fzf.nix
    ./git.nix
    ./gpg
    ./grc.nix
    ./lazygit.nix
    ./lnav.nix
    ./neovim
    ./ripgrep.nix
    ./ssh.nix
    ./starship.nix
    ./tmux
    ./zsh.nix
  ];

  # Tokyo Night less standout (search highlight + statusbar): blue bg, dark fg.
  # Must use zsh `$'\e'` for a real ESC byte (see note in home.sessionVariables).
  programs.zsh.initContent = ''
    export LESS_TERMCAP_so=$'\e[38;2;${hexToRgb theme.bg};48;2;${hexToRgb theme.blue}m'
    export LESS_TERMCAP_se=$'\e[0m'
  '';

  # Register Nix-installed fonts with fontconfig on Linux
  fonts.fontconfig.enable = lib.mkIf pkgs.stdenv.isLinux true;

  home.packages = with pkgs;
    [
      # Fonts for terminal and neovim icons
      font-awesome
      noto-fonts
      nerd-fonts.meslo-lg
      nerd-fonts.noto

      # xterm-kitty terminfo for hosts we SSH into from a kitty terminal
      # (notcurses-based tools like lnav need the entry even when kitty
      # itself isn't installed here).
      kitty.terminfo

      pagerPkg

      pkgs.ssh-fzf
      pkgs.notify
      pkgs.jupyter-bridge

      pkgs.kicad-parts-manager
      pkgs.dwfv # terminal (TUI) digital waveform / VCD viewer

      jq
      yq-go
      pqrs
      dust
      timg
      pandoc
      graphviz
      hexyl
      lesspipe
      rsync
      wget
      curl
      gh
      glab
      git-extras

      aichat

      # GNU core utilities
      tree
      unzip
      coreutils
      findutils
      gnugrep
      gawk
      gnused
      gnutar

      # Modern CLI tools
      watch
      fastfetch
      tealdeer
      tokei
      sd
      procs
      hyperfine
      grex
      lnav

      # Compression
      zstd
      lz4
      p7zip
      xz
      brotli

      # Security
      yubikey-personalization

      # Network
      inetutils

      # Image manipulation
      imagemagick
    ]
    ++ lib.optionals (pkgs.stdenv.isLinux && !config.portable.enable) [
      # portable-ssh wraps ssh to bootstrap a nix-portable home-manager
      # environment on remote hosts. Skipped in portable mode itself
      # (the remote shouldn't recurse) and on darwin (rsync/kitten ssh
      # path differs and we ssh out of macs much less).
      pkgs.portable-ssh
    ];
}
