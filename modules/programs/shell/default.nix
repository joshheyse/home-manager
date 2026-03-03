{
  pkgs,
  config,
  ...
}: {
  home.sessionVariables = {
    PAGER = "moar";
    MANPAGER = "moar";
    MOAR = "--style=tokyonight-night --statusbar=bold --terminal-fg";
    # Tokyo Night statusbar: blue (#7aa2f7) bg with dark (#1a1b26) fg
    LESS_TERMCAP_so = "\\e[38;2;26;27;38;48;2;122;162;247m";
    LESS_TERMCAP_se = "\\e[0m";
    CPM_SOURCE_CACHE = "${config.home.homeDirectory}/.cache/CPM";
  };

  imports = [
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
    moar

    (pkgs.callPackage ../../../pkgs/ssh-fzf {})
    (pkgs.callPackage ../../../pkgs/notify {})

    (pkgs.callPackage ../../../pkgs/kicad-parts-manager {})

    jq
    dust
    timg
    pandoc
    hexyl
    lesspipe
    gh
    glab

    claude-code
  ];
}
