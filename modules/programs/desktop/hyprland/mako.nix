# Mako notification daemon configuration
# Tokyo Night themed with rounded corners
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  theme = config.theme.tokyoNight;
  inherit (pkgs.stdenv) isLinux;
in {
  config = lib.mkIf (cfg.enable && isLinux) {
    services.mako = {
      enable = true;
      settings = {
        background-color = theme.bg;
        text-color = theme.fg;
        border-color = theme.blue;
        border-radius = 8;
        border-size = 2;
        padding = "10";
        default-timeout = 5000;
        font = "MesloLGS Nerd Font 11";
      };
    };
  };
}
