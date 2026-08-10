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
      package = pkgs.rofi;
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

    home.packages = [pkgs.networkmanager_dmenu];

    # Fast NetworkManager frontend for the Waybar Wi-Fi indicator. Rofi loads
    # the Tokyo Night theme above, including its sizing and selected-row
    # colours; networkmanager-dmenu supplies nearby networks and actions.
    xdg.configFile."networkmanager-dmenu/config.ini".text = ''
      [dmenu]
      dmenu_command = ${lib.getExe pkgs.rofi} -dmenu -i
      active_chars = ✓
      highlight = True
      compact = True
      wifi_icons = 󰤯󰤟󰤢󰤥󰤨
      format = {name}  {sec}  {signal:>3}% {icon}
      list_saved = True
      prompt = Networks

      [dmenu_passphrase]
      obscure = True

      [editor]
      gui_if_available = True
      gui = ${pkgs.networkmanagerapplet}/bin/nm-connection-editor

      [nmdm]
      rescan_delay = 3
      show_notifications = True
    '';
  };
}
