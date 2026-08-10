# Hypridle idle daemon configuration
# Locks screen after 5 minutes, turns off display after 10 minutes
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  inherit (pkgs.stdenv) isLinux;
  suspendOnBattery = pkgs.writeShellScript "suspend-on-battery" ''
    ac_found=0
    for supply in /sys/class/power_supply/*; do
      [ -r "$supply/type" ] || continue
      [ "$(cat "$supply/type")" = Mains ] || continue
      ac_found=1
      [ "$(cat "$supply/online")" = 1 ] && exit 0
    done
    [ "$ac_found" = 1 ] || exit 0
    exec ${pkgs.systemd}/bin/systemctl suspend
  '';
in {
  options.programs.hyprland-desktop.suspendOnBatteryAfter = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = null;
    example = 1800;
    description = "Idle seconds before suspending when every mains supply is offline.";
  };

  config = lib.mkIf (cfg.enable && isLinux) {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };

        listener =
          [
            {
              timeout = 300; # 5 minutes
              on-timeout = "hyprlock";
            }
            {
              timeout = 600; # 10 minutes
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ]
          ++ lib.optional (cfg.suspendOnBatteryAfter != null) {
            timeout = cfg.suspendOnBatteryAfter;
            on-timeout = "${suspendOnBattery}";
          };
      };
    };
  };
}
