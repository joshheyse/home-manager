# Hyprpaper wallpaper daemon configuration
# Wallpaper path to be configured by user
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
in {
  config = lib.mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;
      settings = {
        ipc = "on";
        splash = false;
        # User will add wallpaper later:
        # preload = [ "/path/to/wallpaper.jpg" ];
        # wallpaper = [ ",/path/to/wallpaper.jpg" ];
      };
    };
  };
}
