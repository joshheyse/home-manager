# Hyprlock lock screen configuration
# Tokyo Night themed with blurred screenshot background
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
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          hide_cursor = true;
          grace = 5;
        };

        background = [
          {
            monitor = "";
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
          }
        ];

        input-field = [
          {
            monitor = "";
            size = "300, 50";
            outline_thickness = 2;
            outer_color = "rgb(${lib.removePrefix "#" theme.blue})";
            inner_color = "rgb(${lib.removePrefix "#" theme.bg})";
            font_color = "rgb(${lib.removePrefix "#" theme.fg})";
            placeholder_text = "Password...";
          }
        ];

        label = [
          {
            monitor = "";
            text = "$TIME";
            font_size = 64;
            color = "rgb(${lib.removePrefix "#" theme.fg})";
            position = "0, 80";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };
  };
}
