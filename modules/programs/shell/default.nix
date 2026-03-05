{
  pkgs,
  config,
  ...
}: let
  theme = config.theme.tokyoNight;

  # Convert "#rrggbb" hex to "r;g;b" decimal for ANSI escape sequences
  hexToRgb = hex: let
    hexStr = builtins.substring 1 6 hex;
    r = builtins.fromTOML "v = 0x${builtins.substring 0 2 hexStr}";
    g = builtins.fromTOML "v = 0x${builtins.substring 2 2 hexStr}";
    b = builtins.fromTOML "v = 0x${builtins.substring 4 2 hexStr}";
  in "${toString r.v};${toString g.v};${toString b.v}";
in {
  home.sessionVariables = {
    PAGER = "moar";
    MANPAGER = "moar";
    MOAR = "--style=tokyonight-night --statusbar=bold --terminal-fg";
    # Tokyo Night statusbar: blue bg with dark fg
    LESS_TERMCAP_so = "\\e[38;2;${hexToRgb theme.bg};48;2;${hexToRgb theme.blue}m";
    LESS_TERMCAP_se = "\\e[0m";
    CPM_SOURCE_CACHE = "${config.home.homeDirectory}/.cache/CPM";
  };

  imports = [
    ../../theme.nix
    ./bat.nix
    ./bottom.nix
    ./btop.nix
    ./claude-code
    ./direnv.nix
    ./eza.nix
    ./fd.nix
    ./fzf.nix
    ./git.nix
    ./gpg
    ./lazygit.nix
    ./neovim
    ./ripgrep.nix
    ./starship.nix
    ./tmux
    ./zsh.nix
  ];

  home.packages = with pkgs; [
    # Fonts for terminal and neovim icons
    noto-fonts
    nerd-fonts.meslo-lg
    nerd-fonts.noto

    moar

    (pkgs.callPackage ../../../pkgs/ssh-fzf {})
    (pkgs.callPackage ../../../pkgs/notify {})

    (pkgs.callPackage ../../../pkgs/kicad-parts-manager {})

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

    claude-code
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
    tealdeer
    tokei
    sd
    procs
    hyperfine
    grex

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
  ];
}
