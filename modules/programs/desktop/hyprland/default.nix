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
    ./hyprland.nix
    ./waybar.nix
    ./rofi.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
    # hyprexpo removed from nixpkgs in 26.05 (retired upstream from
    # hyprland-plugins), which also removed pkgs.hyprlandPlugins.hyprexpo.
    #
    # TRIED 2026-08-08: github:sandwichfarm/hyprexpo, the maintained fork. It
    # exposes packages.aarch64-linux and pins hyprwm/Hyprland at a0136d8c (the
    # same commit our 0.55.4 is built from), but does not compile even against
    # its own pin:
    #   fatal error: hyprland/src/desktop/state/GlobalWindowController.hpp
    #   fatal error: hyprland/src/animation/AnimationManager.hpp
    #   fatal error: hyprland/src/output/Monitor.hpp
    #   error: 'CMonitor' is not a member of 'Monitor'
    # Those headers belong to a NEWER Hyprland source layout than 0.55.4, so the
    # fork's code is ahead of the Hyprland it builds against. Nothing on our
    # side fixes that — it needs an upstream fix or a Hyprland bump.
    #
    # Until then the overview gesture is unavailable. Workspace switching by
    # swipe does work; see the `gesture` setting in hyprland.nix.
    # ./hyprexpo.nix
    ./swayosd.nix
    ./wlogout.nix
    ./wallpaper.nix
    ./mako.nix
  ];

  # Only install packages on Linux when enabled
  config = lib.mkIf (cfg.enable && isLinux) {
    home.packages = with pkgs;
      [
        cliphist
        firefox
        grim
        hyprpicker
        pavucontrol
        slurp
        wl-clipboard
      ]
      ++ lib.optionals (!isAarch64Linux) [
        discord
        spotify
      ];
  };
}
