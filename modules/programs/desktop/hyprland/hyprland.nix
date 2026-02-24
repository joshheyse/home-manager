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

  # --- Keybinding data (single source of truth) ---

  keybinds = [
    {
      mods = "$mod";
      key = "Return";
      action = "exec, kitty";
      desc = "Terminal (kitty)";
    }
    {
      mods = "$mod";
      key = "grave";
      action = "exec, kitty";
      desc = "Terminal (kitty)";
    }
    {
      mods = "$mod";
      key = "R";
      action = "exec, rofi -show drun";
      desc = "App launcher (rofi)";
    }
    {
      mods = "$mod";
      key = "W";
      action = "exec, firefox";
      desc = "Firefox";
    }
    {
      mods = "$mod";
      key = "D";
      action = "exec, discord";
      desc = "Discord";
    }
    {
      mods = "$mod";
      key = "S";
      action = "exec, spotify";
      desc = "Spotify";
    }
    {
      mods = "$mod";
      key = "Q";
      action = "killactive";
      desc = "Kill window";
    }
    {
      mods = "$mod";
      key = "M";
      action = "exit";
      desc = "Exit Hyprland";
    }
    {
      mods = "$mod";
      key = "V";
      action = "togglefloating";
      desc = "Toggle floating";
    }
    {
      mods = "$mod";
      key = "F";
      action = "fullscreen";
      desc = "Fullscreen";
    }
    {
      mods = "$mod";
      key = "Escape";
      action = "exec, hyprlock";
      desc = "Lock screen";
    }
    # Focus (vim + arrow)
    {
      mods = "$mod";
      key = "h";
      altKey = "left";
      action = "movefocus, l";
      desc = "Focus left";
    }
    {
      mods = "$mod";
      key = "j";
      altKey = "down";
      action = "movefocus, d";
      desc = "Focus down";
    }
    {
      mods = "$mod";
      key = "k";
      altKey = "up";
      action = "movefocus, u";
      desc = "Focus up";
    }
    {
      mods = "$mod";
      key = "l";
      altKey = "right";
      action = "movefocus, r";
      desc = "Focus right";
    }
    # Move window between monitors
    {
      mods = "$mod SHIFT";
      key = "k";
      altKey = "up";
      action = "movewindow, mon:u";
      desc = "Move window to top monitor";
    }
    {
      mods = "$mod SHIFT";
      key = "j";
      altKey = "down";
      action = "movewindow, mon:d";
      desc = "Move window to bottom monitor";
    }
    # Screenshots
    {
      mods = "";
      key = "Print";
      action = ''exec, grim -g "$(slurp)" - | wl-copy'';
      desc = "Screenshot region → clipboard";
    }
    {
      mods = "SHIFT";
      key = "Print";
      action = "exec, grim - | wl-copy";
      desc = "Screenshot full → clipboard";
    }
  ];

  workspaceBinds = builtins.concatMap (ws: let
    key =
      if ws == 10
      then "0"
      else toString ws;
  in [
    {
      mods = "$mod";
      inherit key;
      action = "workspace, ${toString ws}";
    }
    {
      mods = "$mod SHIFT";
      inherit key;
      action = "movetoworkspace, ${toString ws}";
    }
  ]) (lib.range 1 10);

  # --- Keybinding formatting helpers ---

  toBind = b:
    ["${b.mods}, ${b.key}, ${b.action}"]
    ++ lib.optional (b ? altKey) "${b.mods}, ${b.altKey}, ${b.action}";

  keyDisplayMap = {
    Return = "Enter";
    grave = "`";
    left = "←";
    right = "→";
    up = "↑";
    down = "↓";
  };

  displayKey = k: keyDisplayMap.${k} or k;

  formatMods = m:
    builtins.replaceStrings
    ["$mod SHIFT" "$mod" "SHIFT"]
    ["Super + Shift" "Super" "Shift"]
    m;

  padRight = width: s: let
    padding = builtins.concatStringsSep "" (builtins.genList (_: " ") width);
  in
    builtins.substring 0 width (s + padding);

  formatKeybind = b: let
    modsStr = formatMods b.mods;
    keyStr =
      if b ? altKey
      then "${displayKey b.key}/${displayKey b.altKey}"
      else displayKey b.key;
    combo =
      if modsStr == ""
      then keyStr
      else "${modsStr} + ${keyStr}";
  in "${padRight 27 combo}${b.desc}";

  formatExtra = combo: desc: "${padRight 27 combo}${desc}";

  # --- Cheatsheet ---

  cheatsheetText = lib.concatStringsSep "\n" (
    (map formatKeybind keybinds)
    ++ [
      (formatExtra "Super + 1-0" "Workspace 1-10")
      (formatExtra "Super + Shift + 1-0" "Move to workspace 1-10")
      (formatExtra "Super + ?" "This cheatsheet")
      (formatExtra "Super + LMB" "Move window (drag)")
      (formatExtra "Super + RMB" "Resize window (drag)")
    ]
  );

  cheatsheetFile = pkgs.writeText "keybind-cheatsheet" cheatsheetText;

  showKeybinds = pkgs.writeShellScript "show-keybinds" ''
    ${pkgs.rofi-wayland}/bin/rofi -dmenu -i -no-custom -p "Keybindings" \
      -theme-str 'window {width: 50%;} listview {lines: 20;}' \
      < ${cheatsheetFile}
  '';
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

        # Keybindings (generated from keybinds data)
        bind =
          (lib.concatMap toBind keybinds)
          ++ (lib.concatMap toBind workspaceBinds)
          ++ ["$mod SHIFT, slash, exec, ${showKeybinds}"];

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
