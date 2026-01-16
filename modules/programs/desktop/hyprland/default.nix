# Hyprland desktop environment for Home Manager
# Entry point module that imports all Hyprland-related configurations
# Only applies on Linux (Hyprland doesn't support macOS)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  inherit (pkgs.stdenv) isLinux;
in {
  options.programs.hyprland-desktop = {
    enable = lib.mkEnableOption "Hyprland desktop configuration";
  };

  imports = [
    ./theme.nix
    ./hyprland.nix
    ./waybar.nix
    ./rofi.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
    ./mako.nix
  ];

  # Only install packages on Linux when enabled
  config = lib.mkIf (cfg.enable && isLinux) {
    home.packages = with pkgs; [
      cliphist
      wl-clipboard
      grim
      slurp
      hyprpicker
      pavucontrol
    ];
  };
}
