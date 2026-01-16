# Hyprland desktop environment for Home Manager
# Entry point module that imports all Hyprland-related configurations
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
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

  config = lib.mkIf cfg.enable {
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
