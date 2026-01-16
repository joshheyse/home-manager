# Waybar status bar configuration
# Tokyo Night themed with workspaces, clock, system stats
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
    programs.waybar = {
      enable = true;
      settings = [
        {
          layer = "top";
          position = "top";
          height = 30;
          modules-left = ["hyprland/workspaces" "hyprland/window"];
          modules-center = ["clock"];
          modules-right = ["pulseaudio" "network" "cpu" "memory" "tray"];

          "hyprland/workspaces" = {
            format = "{icon}";
            on-click = "activate";
          };

          clock = {
            format = "{:%H:%M}";
            format-alt = "{:%Y-%m-%d %H:%M}";
            tooltip-format = "{:%Y-%m-%d | %H:%M}";
          };

          cpu = {
            format = " {usage}%";
            interval = 2;
          };

          memory = {
            format = " {}%";
            interval = 2;
          };

          network = {
            format-wifi = " {signalStrength}%";
            format-ethernet = " {ipaddr}";
            format-disconnected = " Disconnected";
          };

          pulseaudio = {
            format = "{icon} {volume}%";
            format-muted = " Muted";
            format-icons = {default = ["" "" ""];};
            on-click = "pavucontrol";
          };

          tray = {
            spacing = 10;
          };
        }
      ];

      style = ''
        * {
          font-family: "MesloLGS Nerd Font", "Font Awesome 6 Free";
          font-size: 13px;
        }

        window#waybar {
          background-color: ${theme.bg};
          color: ${theme.fg};
          border-bottom: 2px solid ${theme.border};
        }

        #workspaces button {
          padding: 0 5px;
          color: ${theme.fgDark};
          background: transparent;
          border: none;
        }

        #workspaces button.active {
          color: ${theme.blue};
        }

        #clock, #cpu, #memory, #network, #pulseaudio, #tray {
          padding: 0 10px;
        }

        #clock {
          color: ${theme.cyan};
        }

        #cpu {
          color: ${theme.green};
        }

        #memory {
          color: ${theme.magenta};
        }

        #network {
          color: ${theme.yellow};
        }

        #pulseaudio {
          color: ${theme.orange};
        }
      '';
    };
  };
}
