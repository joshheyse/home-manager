{pkgs, ...}: {
  imports = [
    ./bat.nix
    ./bottom.nix
    ./btop.nix
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
    ./tmux.nix
    ./zsh.nix
  ];

  home.packages = with pkgs; [
    moar

    (pkgs.callPackage ../../../pkgs/ssh-fzf {})

    dust
    timg
    pandoc
    hexyl
    lesspipe

    claude-code
  ];
}
