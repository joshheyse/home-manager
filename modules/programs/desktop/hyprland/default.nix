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
  isAarch64Linux = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
in {
  options.programs.hyprland-desktop = {
    enable = lib.mkEnableOption "Hyprland desktop configuration";
  };

  imports = [
    ./gtk.nix
    ./auto-brightness.nix
    ./dynamic-cursors.nix
    ./hyprland.nix
    ./waybar.nix
    ./rofi.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
    ./hyprspace.nix
    ./swayosd.nix
    ./wlogout.nix
    ./wallpaper.nix
    ./notifications.nix
  ];

  # Only install packages on Linux when enabled
  config = lib.mkIf (cfg.enable && isLinux) {
    home.packages = with pkgs;
      [
        cliphist
        firefox
        grim
        hyprpicker
        hyprpwcenter
        slurp
        wl-clipboard
      ]
      ++ lib.optionals (!isAarch64Linux) [
        discord
      ];
  };
}
