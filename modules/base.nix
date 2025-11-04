{
  pkgs,
  lib,
  ...
}: {
  # Base settings shared across all hosts
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;
  news.display = "silent";

  # Nicely reload system units when changing configs (Linux only)
  systemd.user.startServices = lib.mkIf pkgs.stdenv.isLinux "sd-switch";

  home.sessionVariables = {
    SHELL = "${pkgs.zsh}/bin/zsh";
    # Use GPG agent for SSH (YubiKey support)
    SSH_AUTH_SOCK = "$HOME/.gnupg/S.gpg-agent.ssh";
  };
}
