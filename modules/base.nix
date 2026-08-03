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
}
