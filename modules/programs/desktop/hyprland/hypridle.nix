# Hypridle idle daemon configuration
# Locks screen after 5 minutes, turns off display after 10 minutes
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
in {
  config = lib.mkIf cfg.enable {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };

        listener = [
          {
            timeout = 300; # 5 minutes
            on-timeout = "hyprlock";
          }
          {
            timeout = 600; # 10 minutes
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          }
        ];
      };
    };
  };
}
