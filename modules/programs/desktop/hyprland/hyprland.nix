# Hyprland window manager configuration
# Includes keybindings, animations, decorations, and autostart
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
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        "$mod" = "SUPER";

        # Monitor config - dual Dell U3824DW ultrawides (stacked)
        # DP-2 on top, DP-1 on bottom
        monitor = [
          "DP-2,3840x1600@60,0x0,1"
          "DP-1,3840x1600@60,0x1600,1"
        ];

        # General settings
        general = {
          gaps_in = 2;
          gaps_out = 4;
          border_size = 2;
          "col.active_border" = "rgb(${lib.removePrefix "#" theme.borderActive})";
          "col.inactive_border" = "rgb(${lib.removePrefix "#" theme.border})";
          layout = "dwindle";
        };

        # Decorations (blur, rounding)
        decoration = {
          rounding = 8;
          blur = {
            enabled = true;
            size = 8;
            passes = 2;
            new_optimizations = true;
          };
          shadow = {
            enabled = true;
            range = 8;
            render_power = 2;
          };
        };

        # Subtle animations
        animations = {
          enabled = true;
          bezier = "ease, 0.25, 0.1, 0.25, 1";
          animation = [
            "windows, 1, 3, ease, slide"
            "windowsOut, 1, 3, ease, slide"
            "fade, 1, 3, ease"
            "workspaces, 1, 3, ease, slide"
          ];
        };

        # Input
        input = {
          kb_layout = "us";
          kb_options = "caps:escape";
          numlock_by_default = true;
          repeat_rate = 50;
          repeat_delay = 300;
          follow_mouse = 1;
          sensitivity = 0;
        };

        # Dwindle layout
        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        # Keybindings
        bind = [
          # Apps
          "$mod, Return, exec, kitty"
          "$mod, grave, exec, kitty"
          "$mod, D, exec, discord"
          "$mod, R, exec, rofi -show drun"
          "$mod, S, exec, spotify"
          "$mod, W, exec, firefox"
          "$mod, Q, killactive"
          "$mod, M, exit"
          "$mod, V, togglefloating"
          "$mod, F, fullscreen"
          "$mod, Escape, exec, hyprlock"

          # Focus (arrow keys)
          "$mod, left, movefocus, l"
          "$mod, right, movefocus, r"
          "$mod, up, movefocus, u"
          "$mod, down, movefocus, d"

          # Focus (vim keys)
          "$mod, h, movefocus, l"
          "$mod, j, movefocus, d"
          "$mod, k, movefocus, u"
          "$mod, l, movefocus, r"

          # Workspaces 1-10
          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          "$mod, 9, workspace, 9"
          "$mod, 0, workspace, 10"

          # Move to workspace
          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"
          "$mod SHIFT, 6, movetoworkspace, 6"
          "$mod SHIFT, 7, movetoworkspace, 7"
          "$mod SHIFT, 8, movetoworkspace, 8"
          "$mod SHIFT, 9, movetoworkspace, 9"
          "$mod SHIFT, 0, movetoworkspace, 10"

          # Screenshots
          ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
          "SHIFT, Print, exec, grim - | wl-copy"
        ];

        # Mouse bindings
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        # Window rules
        windowrulev2 = [
          "float, class:^(pavucontrol)$"
          "size 600 400, class:^(pavucontrol)$"
          "move 100%-620 50, class:^(pavucontrol)$"
          "float, class:^(kicad|eeschema|pcbnew|gerbview|pl_editor|bitmap2component|pcb_calculator)$"
        ];

        # Autostart
        exec-once = [
          "waybar"
          "hyprpaper"
          "mako"
          "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
        ];
      };
    };
  };
}
