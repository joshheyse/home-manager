# Rofi application launcher configuration
# Tokyo Night themed with rounded corners
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
    programs.rofi = {
      enable = true;
      package = pkgs.rofi-wayland;
      terminal = "${pkgs.kitty}/bin/kitty";
      theme = let
        inherit (config.lib.formats.rasi) mkLiteral;
      in {
        "*" = {
          bg = mkLiteral theme.bg;
          bg-alt = mkLiteral theme.bgHighlight;
          fg = mkLiteral theme.fg;
          accent = mkLiteral theme.blue;
          background-color = mkLiteral "@bg";
          text-color = mkLiteral "@fg";
        };

        window = {
          width = mkLiteral "600px";
          border = mkLiteral "2px";
          border-color = mkLiteral "@accent";
          border-radius = mkLiteral "8px";
        };

        mainbox = {
          padding = mkLiteral "12px";
        };

        inputbar = {
          background-color = mkLiteral "@bg-alt";
          padding = mkLiteral "8px";
          border-radius = mkLiteral "4px";
        };

        listview = {
          lines = 8;
          padding = mkLiteral "8px 0 0 0";
        };

        element = {
          padding = mkLiteral "8px";
          border-radius = mkLiteral "4px";
        };

        "element selected" = {
          background-color = mkLiteral "@accent";
          text-color = mkLiteral "@bg";
        };
      };
    };
  };
}
