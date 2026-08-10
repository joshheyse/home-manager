{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop.autoBrightness;
  inherit (pkgs.stdenv) isLinux;
in {
  options.programs.hyprland-desktop.autoBrightness = {
    enable = lib.mkEnableOption "ambient-light-driven display and keyboard brightness";

    manualPauseSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = "How long display automation pauses after a brightness key is pressed.";
    };
  };

  config = lib.mkIf (config.programs.hyprland-desktop.enable && cfg.enable && isLinux) {
    systemd.user.services.auto-brightness = {
      Unit = {
        Description = "Adjust Apple display and keyboard brightness from ambient light";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };

      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./auto-brightness.py} --manual-pause-seconds ${toString cfg.manualPauseSeconds}";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
