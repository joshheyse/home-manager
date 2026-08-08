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

  # Colocated helper, per the repo convention for scripts only one module uses.
  # PATH is pinned so the module never depends on the login shell.
  tailscaleStatus = pkgs.writeShellScript "waybar-tailscale" ''
    export PATH="${lib.makeBinPath [pkgs.tailscale pkgs.jq pkgs.coreutils]}:$PATH"
    ${builtins.readFile ./waybar-tailscale.sh}
  '';

  notch = cfg.waybar.notchWidth;
  hasNotch = notch > 0;
in {
  options.programs.hyprland-desktop.waybar.notchWidth = lib.mkOption {
    type = lib.types.int;
    default = 0;
    example = 160;
    description = ''
      Width in LOGICAL pixels of the display notch, or 0 for a panel without
      one (the default, so ordinary monitors are unaffected).

      When non-zero the clock is split in two and separated by a blank spacer
      of this width, giving `DATE  <notch>  TIME`, and the bar is grown to the
      full height of the notch row so none of it is wasted. Content never sits
      behind the cutout.

      Apple Silicon laptops only expose the notch row when the kernel is booted
      with `appledrm.show_notch=1`; without it the panel is cropped below the
      notch and this should stay 0.
    '';
  };

  config = lib.mkIf (cfg.enable && isLinux) {
    programs.waybar = {
      enable = true;
      settings = [
        {
          layer = "top";
          position = "top";
          # 74 physical px of notch at scale 2 = 37 logical. Matching it exactly
          # means the reclaimed strip is entirely bar rather than dead space.
          height =
            if hasNotch
            then 37
            else 30;
          modules-left = ["hyprland/workspaces" "hyprland/window"];
          modules-center =
            if hasNotch
            then ["clock#date" "custom/notch" "clock#time"]
            else ["clock"];
          modules-right = ["custom/tailscale" "pulseaudio" "network" "cpu" "memory" "battery" "tray"];

          "hyprland/workspaces" = {
            format = "{icon}";
            on-click = "activate";
          };

          clock = {
            format = " {:%H:%M:%S}";
            format-alt = "{:%Y-%m-%d %H:%M:%S}";
            tooltip-format = "{:%Y-%m-%d | %H:%M:%S}";
            # Seconds are pointless without a matching tick rate; waybar
            # defaults to 60s and the display would sit stale for a minute.
            interval = 1;
          };

          # Notch layout. The centre group is centred as a unit, so a spacer of
          # the notch's width between the two halves lands the cutout between
          # them: date to its left, time to its right. Keeping the two roughly
          # equal in width keeps the spacer centred on the screen.
          "clock#date" = {
            format = "{:%a %d %b}";
            tooltip-format = "{:%Y-%m-%d}";
          };

          "clock#time" = {
            format = " {:%H:%M:%S}";
            interval = 1;
            tooltip-format = "{:%Y-%m-%d | %H:%M:%S}";
          };

          "custom/notch" = {
            format = "";
            tooltip = false;
          };

          cpu = {
            format = " {usage}%";
            interval = 2;
          };

          memory = {
            format = " {}%";
            interval = 2;
          };

          network = {
            format-wifi = " {signalStrength}%";
            format-ethernet = " {ipaddr}";
            format-disconnected = " Disconnected";
            tooltip-format-wifi = "{essid}  {signalStrength}%\n{ifname}  {ipaddr}/{cidr}\ngw {gwaddr}\nup {bandwidthUpBits} / down {bandwidthDownBits}";
            tooltip-format-ethernet = "{ifname}  {ipaddr}/{cidr}\ngw {gwaddr}\nup {bandwidthUpBits} / down {bandwidthDownBits}";
            tooltip-format-disconnected = "No network";
            # Throughput figures are deltas between polls; without an interval
            # they read zero forever.
            interval = 5;
            on-click = "${pkgs.kitty}/bin/kitty --class network-tui -e ${pkgs.networkmanager}/bin/nmtui";
            on-click-right = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
          };

          # Tailscale is invisible to the network module, which reports whatever
          # carries the default route -- that stays wifi/ethernet even with the
          # tailnet up. Separate indicator so "am I on the tailnet" is
          # answerable at a glance.
          "custom/tailscale" = {
            exec = "${tailscaleStatus}";
            return-type = "json";
            interval = 10;
            on-click = "${pkgs.kitty}/bin/kitty --class network-tui -e ${pkgs.tailscale}/bin/tailscale status";
          };

          pulseaudio = {
            format = "{icon} {volume}%";
            format-muted = " Muted";
            format-icons = {default = ["" "" ""];};
            on-click = "pavucontrol";
          };

          # Laptop only; on a desktop `battery` renders nothing and is harmless.
          # Icons are FA4-era codepoints, which this MesloLGS patch carries
          # (the FA5 nf-fa-memory/network_wired glyphs are absent from it).
          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-charging = " {capacity}%";
            format-plugged = " {capacity}%";
            format-icons = ["" "" "" "" ""];
            interval = 30;
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

        /* Blank cutout the physical notch sits in. min-width is the whole
           mechanism -- an empty label with no width would collapse. */
        #custom-notch {
          min-width: ${toString notch}px;
          background: transparent;
        }

        #custom-tailscale.connected {
          color: ${theme.green};
        }

        #custom-tailscale.exitnode {
          color: ${theme.yellow};
        }

        #custom-tailscale.offline {
          color: ${theme.fgDark};
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
