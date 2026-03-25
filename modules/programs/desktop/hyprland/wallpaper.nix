# Wallpaper rotation and Digital Blasphemy sync
# - Rotates wallpapers from a local directory via hyprpaper IPC
# - Optionally syncs wallpapers from Digital Blasphemy on a timer
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  wallCfg = cfg.wallpaper;
  inherit (pkgs.stdenv) isLinux;

  dbWallpaperSync = pkgs.callPackage ../../../../pkgs/db-wallpaper {};

  wallpaperRotate = pkgs.writeShellScript "wallpaper-rotate" ''
    export PATH="${lib.makeBinPath [pkgs.hyprland pkgs.findutils pkgs.coreutils]}:$PATH"
    ${builtins.readFile ./wallpaper-rotate.sh}
  '';

  rotateCmd = "${wallpaperRotate} ${wallCfg.directory} ${lib.concatStringsSep " " wallCfg.monitors}";
in {
  options.programs.hyprland-desktop.wallpaper = {
    enable = lib.mkEnableOption "wallpaper rotation with Digital Blasphemy sync";

    directory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/wallpapers";
      description = "Directory containing wallpaper images";
    };

    monitors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["DP-1" "DP-2"];
      description = "Monitor names to apply wallpapers to";
    };

    rotateInterval = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "How often to rotate wallpapers (systemd OnUnitActiveSec format)";
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "6h";
      description = "How often to sync wallpapers from Digital Blasphemy";
    };

    resolution = lib.mkOption {
      type = lib.types.str;
      default = "3840x1600";
      description = "Wallpaper resolution to download";
    };

    usernameFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/sops-nix/secrets/digitalblasphemy/username";
      description = "Path to file containing Digital Blasphemy username";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/sops-nix/secrets/digitalblasphemy/password";
      description = "Path to file containing Digital Blasphemy password";
    };
  };

  config = lib.mkIf (cfg.enable && wallCfg.enable && isLinux) {
    # Ensure wallpaper directory exists
    home.activation.createWallpaperDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "${wallCfg.directory}"
    '';

    systemd.user = {
      services = {
        # Wallpaper rotation service
        wallpaper-rotate = {
          Unit = {
            Description = "Rotate wallpaper";
            After = ["hyprpaper.service" "graphical-session.target"];
          };
          Service = {
            Type = "oneshot";
            ExecStart = rotateCmd;
            Environment = "WAYLAND_DISPLAY=wayland-1";
          };
        };

        # Digital Blasphemy sync service
        db-wallpaper-sync = {
          Unit = {
            Description = "Sync wallpapers from Digital Blasphemy";
            Wants = ["network-online.target"];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${dbWallpaperSync}/bin/db-wallpaper-sync --username-file ${wallCfg.usernameFile} --password-file ${wallCfg.passwordFile} --output-dir ${wallCfg.directory} --resolution ${wallCfg.resolution}";
          };
        };
      };

      timers = {
        # Wallpaper rotation timer
        wallpaper-rotate = {
          Unit.Description = "Rotate wallpaper periodically";
          Timer = {
            OnStartupSec = "10s";
            OnUnitActiveSec = wallCfg.rotateInterval;
          };
          Install.WantedBy = ["timers.target"];
        };

        # Digital Blasphemy sync timer
        db-wallpaper-sync = {
          Unit.Description = "Sync Digital Blasphemy wallpapers periodically";
          Timer = {
            OnStartupSec = "30s";
            OnUnitActiveSec = wallCfg.syncInterval;
            Persistent = true;
          };
          Install.WantedBy = ["timers.target"];
        };
      };
    };

    # Apply wallpaper on Hyprland startup
    wayland.windowManager.hyprland.settings.exec-once = [
      rotateCmd
    ];
  };
}
