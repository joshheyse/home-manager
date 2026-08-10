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
        # Match the roomy Mako popup rather than SwayNC's narrower default.
        notification-window-width = 600;
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

        notificationwindow,
        blankwindow,
        .floating-notifications {
          background: transparent;
        }

        .control-center {
          background: ${theme.bgDark};
          color: ${theme.fg};
          border: 2px solid ${theme.blue};
          border-radius: 12px;
          padding: 8px;
        }

        .notification-row .notification-background {
          background: transparent;
          margin: 6px;
          padding: 0;
        }

        /* Floating notifications deliberately retain Mako's visual language:
           opaque Tokyo Night card, blue outline, compact square-ish corners. */
        .floating-notifications .notification-row .notification-background .notification {
          background: ${theme.bg};
          color: ${theme.fg};
          border: 2px solid ${theme.blue};
          border-radius: 8px;
          box-shadow: none;
          padding: 6px;
        }

        /* History cards use the same palette but a quieter divider so a list
           of old notifications does not become a wall of blue outlines. */
        .control-center .notification-row .notification-background .notification {
          background: ${theme.bg};
          color: ${theme.fg};
          border: 1px solid ${theme.bgHighlight};
          border-radius: 8px;
          box-shadow: none;
        }

        .notification-row .notification-background .notification .notification-default-action,
        .notification-row .notification-background .notification .notification-action,
        .notification-group,
        .control-center-list {
          background: transparent;
          color: ${theme.fg};
          box-shadow: none;
        }

        .notification-row .notification-background .notification .notification-default-action:hover,
        .notification-row .notification-background .notification .notification-action:hover {
          background: ${theme.bgHighlight};
        }

        .notification.critical {
          border: 2px solid ${theme.red};
          border-radius: 8px;
        }

        .summary { color: ${theme.fg}; }
        .body { color: ${theme.fgDark}; }
        .time { color: ${theme.comment}; }

        .widget-title,
        .widget-dnd {
          background: ${theme.bg};
          color: ${theme.fg};
          border: 1px solid ${theme.bgHighlight};
          border-radius: 8px;
          margin: 6px;
          padding: 8px 12px;
        }

        button,
        .close-button,
        .notification-action > button,
        .widget-title > button {
          background: ${theme.bgHighlight};
          color: ${theme.fg};
          border: 1px solid ${theme.border};
          border-radius: 6px;
          box-shadow: none;
        }

        button:hover,
        .close-button:hover,
        .notification-action > button:hover,
        .widget-title > button:hover {
          background: ${theme.blue};
          color: ${theme.bgDark};
          border-color: ${theme.blue};
        }

        .widget-dnd switch {
          background: ${theme.bgHighlight};
          border: 1px solid ${theme.border};
          border-radius: 999px;
          box-shadow: none;
        }

        .widget-dnd switch slider {
          background: ${theme.fgDark};
          border: none;
          box-shadow: none;
        }

        .widget-dnd switch:checked {
          background: ${theme.blue};
          border-color: ${theme.blue};
        }

        .widget-dnd switch:checked slider {
          background: ${theme.bgDark};
        }
      '';
    };
  };
}
