# Notification history and controls for the Hyprland session.
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
    services.swaync = {
      enable = true;
      settings = {
        positionX = "right";
        positionY = "top";
        layer = "overlay";
        control-center-layer = "top";
        control-center-width = 500;
        control-center-margin-top = 10;
        control-center-margin-right = 10;
        notification-window-width = 500;
        notification-icon-size = 48;
        notification-body-image-height = 200;
        notification-body-image-width = 200;
        timeout = 5;
        timeout-low = 3;
        timeout-critical = 0;
        fit-to-screen = true;
        control-center-close-on-click = false;
        widgets = ["title" "dnd" "notifications"];
        widget-config = {
          title = {
            text = "Notifications";
            clear-all-button = true;
            button-text = "Clear";
          };
          dnd.text = "Do not disturb";
        };
      };

      style = ''
        * {
          font-family: "MesloLGS Nerd Font";
          font-size: 14px;
        }

        .control-center {
          background: ${theme.bgDark};
          color: ${theme.fg};
          border: 2px solid ${theme.blue};
          border-radius: 12px;
          padding: 8px;
        }

        .notification-row .notification-background {
          background: ${theme.bg};
          border: 1px solid ${theme.bgHighlight};
          border-radius: 10px;
          margin: 6px;
          padding: 4px;
        }

        .notification-row .notification-background:hover {
          background: ${theme.bgHighlight};
        }

        .notification.critical {
          border: 2px solid ${theme.red};
          border-radius: 10px;
        }

        .summary { color: ${theme.fg}; }
        .body { color: ${theme.fgDark}; }
        .time { color: ${theme.comment}; }

        .widget-title,
        .widget-dnd {
          background: ${theme.bg};
          border-radius: 8px;
          margin: 6px;
          padding: 8px 12px;
        }

        button {
          background: ${theme.bgHighlight};
          color: ${theme.fg};
          border-radius: 6px;
        }

        button:hover { background: ${theme.blue}; }
        switch:checked { background: ${theme.blue}; }
      '';
    };
  };
}
