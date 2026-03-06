# Shared keybinding module for Hyprland (Linux) and skhd (macOS)
# Defines keybinding data, app roles, and generates platform-specific configs
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin isLinux;

  cfg = config.programs.tiling-wm;

  # --- Smart-focus scripts (platform-specific) ---

  smartFocusDarwin = pkgs.writeShellScript "smart-focus" ''
    APP_ID="$1"
    LAUNCH_CMD="$2"

    if [[ -z "$APP_ID" || -z "$LAUNCH_CMD" ]]; then
      echo "Usage: smart-focus <app-name> <launch-command>" >&2
      exit 1
    fi

    windows=$(yabai -m query --windows | ${pkgs.jq}/bin/jq -r "[.[] | select(.app==\"''${APP_ID}\")]")
    count=$(${pkgs.jq}/bin/jq 'length' <<< "$windows")

    if [[ "$count" -eq 0 ]]; then
      eval "$LAUNCH_CMD"
    else
      focused_idx=-1
      for i in $(seq 0 $((count - 1))); do
        has_focus=$(${pkgs.jq}/bin/jq -r ".[$i][\"has-focus\"]" <<< "$windows")
        if [[ "$has_focus" == "true" ]]; then
          focused_idx=$i
          break
        fi
      done

      if [[ "$focused_idx" -ge 0 ]]; then
        next_idx=$(((focused_idx + 1) % count))
        next_id=$(${pkgs.jq}/bin/jq -r ".[$next_idx].id" <<< "$windows")
        # Fall back to open -a if yabai can't focus (no accessibility reference)
        yabai -m window --focus "$next_id" 2>/dev/null || open -a "$APP_ID"
      else
        first_id=$(${pkgs.jq}/bin/jq -r '.[0].id' <<< "$windows")
        yabai -m window --focus "$first_id" 2>/dev/null || open -a "$APP_ID"
      fi
    fi
  '';

  smartFocusLinux = pkgs.writeShellScript "smart-focus" ''
    APP_ID="$1"
    LAUNCH_CMD="$2"

    if [[ -z "$APP_ID" || -z "$LAUNCH_CMD" ]]; then
      echo "Usage: smart-focus <window-class> <launch-command>" >&2
      exit 1
    fi

    windows=$(hyprctl clients -j | ${pkgs.jq}/bin/jq -r "[.[] | select(.class==\"''${APP_ID}\")]")
    count=$(${pkgs.jq}/bin/jq 'length' <<< "$windows")

    if [[ "$count" -eq 0 ]]; then
      eval "$LAUNCH_CMD"
    else
      focused_addr=$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.address')

      focused_idx=-1
      for i in $(seq 0 $((count - 1))); do
        addr=$(${pkgs.jq}/bin/jq -r ".[$i].address" <<< "$windows")
        if [[ "$addr" == "$focused_addr" ]]; then
          focused_idx=$i
          break
        fi
      done

      if [[ "$focused_idx" -ge 0 ]]; then
        next_idx=$(((focused_idx + 1) % count))
        next_addr=$(${pkgs.jq}/bin/jq -r ".[$next_idx].address" <<< "$windows")
        hyprctl dispatch focuswindow "address:''${next_addr}"
      else
        first_addr=$(${pkgs.jq}/bin/jq -r '.[0].address' <<< "$windows")
        hyprctl dispatch focuswindow "address:''${first_addr}"
      fi
    fi
  '';

  smartFocus =
    if isDarwin
    then smartFocusDarwin
    else smartFocusLinux;

  # --- App role definitions ---

  inherit (cfg) apps;

  # Per-platform app identifier (for window matching) and launch command
  appConfig = {
    terminal = {
      id =
        if isDarwin
        then "kitty"
        else "kitty";
      launch = apps.terminal;
    };
    browser = {
      id =
        if isDarwin
        then "Firefox"
        else "firefox";
      launch = apps.browser;
    };
    discord = {
      id =
        if isDarwin
        then "Discord"
        else "discord";
      launch = apps.discord;
    };
    music = {
      id =
        if isDarwin
        then "Spotify"
        else "spotify";
      launch = apps.music;
    };
    mail = {
      id =
        if isDarwin
        then "Microsoft Outlook"
        else "evolution";
      launch = apps.mail;
    };
    messaging = {
      id =
        if isDarwin
        then "Slack"
        else "signal-desktop";
      launch = apps.messaging;
    };
    zoom = {
      id =
        if isDarwin
        then "zoom.us"
        else "zoom";
      launch = apps.zoom;
    };
    fileManager = {
      id =
        if isDarwin
        then "Finder"
        else "thunar";
      launch = apps.fileManager;
    };
    claude = {
      id =
        if isDarwin
        then "Claude"
        else "claude-desktop";
      launch = apps.claude;
    };
  };

  # --- Keybinding data (single source of truth) ---

  # Each binding has:
  #   key: the base key
  #   mods: list of modifier names (platform-agnostic: "Super", "Shift", "Ctrl")
  #   action: what happens (platform-specific rendering done later)
  #   desc: human-readable description
  #   type: "hyprland" | "skhd" | "both" (which platforms to generate for)
  #   hyprlandAction: Hyprland dispatcher string (optional, for non-exec actions)
  #   skhdAction: skhd command string (optional)

  mkFocus = key: hyprDir: yabaiDir: altKey: desc: {
    inherit key desc altKey;
    mods = ["Super"];
    hyprlandAction = "movefocus, ${hyprDir}";
    skhdAction = "yabai -m window --focus ${yabaiDir}";
  };

  mkMoveDisplay = key: hyprDir: yabaiDir: altKey: desc: {
    inherit key desc altKey;
    mods = ["Super" "Shift"];
    hyprlandAction = "movewindow, mon:${hyprDir}";
    skhdAction = "yabai -m window --display ${yabaiDir} && yabai -m display --focus ${yabaiDir}";
  };

  mkResize = key: skhdDir: hyprlandArgs: desc: {
    inherit key desc;
    mods = ["Super" "Ctrl"];
    hyprlandAction = "resizeactive, ${hyprlandArgs}";
    skhdAction = "yabai -m window --resize ${skhdDir}";
  };

  mkAppLauncher = key: role: desc: {
    inherit key desc;
    mods = ["Super"];
    skhdAction = ''${smartFocus} "${appConfig.${role}.id}" "${appConfig.${role}.launch}"'';
    hyprlandAction = ''exec, ${smartFocus} "${appConfig.${role}.id}" "${appConfig.${role}.launch}"'';
  };

  mkAppLauncherNew = key: role: desc: {
    inherit key desc;
    mods = ["Super" "Shift"];
    skhdAction = appConfig.${role}.launch;
    hyprlandAction = "exec, ${appConfig.${role}.launch}";
  };

  # Lock screen commands
  lockCmd =
    if isDarwin
    then "pmset displaysleepnow"
    else "hyprlock";

  keybinds =
    [
      # Focus (vim keys)
      (mkFocus "h" "l" "west" "left" "Focus left")
      (mkFocus "j" "d" "south" "down" "Focus down")
      (mkFocus "k" "u" "north" "up" "Focus up")
      (mkFocus "l" "r" "east" "right" "Focus right")

      # Move to display
      (mkMoveDisplay "h" "l" "west" "left" "Move window to left display")
      (mkMoveDisplay "j" "d" "south" "down" "Move window to bottom display")
      (mkMoveDisplay "k" "u" "north" "up" "Move window to top display")
      (mkMoveDisplay "l" "r" "east" "right" "Move window to right display")

      # Resize
      (mkResize "h" "left:-40:0" "-40 0" "Shrink width")
      (mkResize "j" "bottom:0:40" "0 40" "Grow height")
      (mkResize "k" "bottom:0:-40" "0 -40" "Shrink height")
      (mkResize "l" "right:40:0" "40 0" "Grow width")

      # Window actions
      {
        key = "q";
        mods = ["Super"];
        desc = "Close window";
        hyprlandAction = "killactive";
        skhdAction = "yabai -m window --close";
      }
      {
        key = "f";
        mods = ["Super"];
        desc = "Maximize";
        hyprlandAction = "fullscreen";
        skhdAction = "yabai -m window --toggle zoom-fullscreen";
      }
      {
        key = "f";
        mods = ["Super" "Shift"];
        desc = "Native fullscreen";
        skhdAction = "yabai -m window --toggle native-fullscreen";
      }
      {
        key = "v";
        mods = ["Super"];
        desc = "Toggle floating";
        hyprlandAction = "togglefloating";
        skhdAction = "yabai -m window --toggle float";
      }
      {
        key = "b";
        mods = ["Super"];
        desc = "Balance layout";
        hyprlandAction = "exec, hyprctl keyword dwindle:force_split 0";
        skhdAction = "yabai -m space --balance";
      }

      # Lock screen
      {
        key = "Escape";
        mods = ["Super"];
        desc = "Lock screen";
        hyprlandAction = "exec, ${lockCmd}";
        skhdAction = lockCmd;
      }

      # App launchers (smart focus/cycle)
      (mkAppLauncher "Return" "terminal" "Terminal")
      (mkAppLauncher "w" "browser" "Firefox")
      (mkAppLauncher "d" "discord" "Discord")
      (mkAppLauncher "s" "music" "Music")
      (mkAppLauncher "m" "mail" "Mail")
      (mkAppLauncher "t" "messaging" "Messaging")
      (mkAppLauncher "z" "zoom" "Zoom")
      (mkAppLauncher "e" "fileManager" "File manager")
      (mkAppLauncher "c" "claude" "Claude")

      # App launchers (force new instance)
      (mkAppLauncherNew "Return" "terminal" "New terminal")
      (mkAppLauncherNew "w" "browser" "New Firefox")
      (mkAppLauncherNew "d" "discord" "New Discord")
      (mkAppLauncherNew "s" "music" "New Music")
      (mkAppLauncherNew "m" "mail" "New Mail")
      (mkAppLauncherNew "t" "messaging" "New Messaging")
      (mkAppLauncherNew "z" "zoom" "New Zoom")
      (mkAppLauncherNew "e" "fileManager" "New File manager")
      (mkAppLauncherNew "c" "claude" "New Claude")
    ]
    ++ lib.optionals isLinux [
      # Linux-only: app launcher (rofi) and screenshots
      {
        key = "R";
        mods = ["Super"];
        desc = "App launcher (rofi)";
        hyprlandAction = "exec, rofi -show drun";
      }
      {
        key = "Print";
        mods = [];
        desc = "Screenshot region to clipboard";
        hyprlandAction = ''exec, grim -g "$(slurp)" - | wl-copy'';
      }
      {
        key = "Print";
        mods = ["Shift"];
        desc = "Screenshot full to clipboard";
        hyprlandAction = "exec, grim - | wl-copy";
      }
    ];

  # Workspace bindings (1-9, plus 0 for 10)
  workspaceNums = lib.range 1 10;

  # Workspace bindings — Hyprland only
  # On macOS, yabai space commands require the scripting addition (SIP disabled).
  # Use native Mission Control shortcuts (Ctrl+1-9) configured in System Settings instead.
  workspaceBinds =
    builtins.concatMap (ws: let
      key =
        if ws == 10
        then "0"
        else toString ws;
    in [
      {
        inherit key;
        mods = ["Super"];
        hyprlandAction = "workspace, ${toString ws}";
        desc = "Focus workspace ${toString ws}";
      }
      {
        inherit key;
        mods = ["Super" "Shift"];
        hyprlandAction = "movetoworkspace, ${toString ws}";
        desc = "Move to workspace ${toString ws}";
      }
    ])
    workspaceNums;

  # Previous/next space (Ctrl + arrow, no Super)
  # macOS: let native Mission Control Ctrl+Left/Right work unintercepted
  spaceNavBinds = [
    {
      key = "Left";
      mods = ["Ctrl"];
      hyprlandAction = "workspace, e-1";
      desc = "Previous workspace";
    }
    {
      key = "Right";
      mods = ["Ctrl"];
      hyprlandAction = "workspace, e+1";
      desc = "Next workspace";
    }
  ];

  allBinds = keybinds ++ workspaceBinds ++ spaceNavBinds;

  # --- Hyprland output ---

  modsToHyprland = mods:
    builtins.concatStringsSep " " (map (m:
      if m == "Super"
      then "$mod"
      else lib.toUpper m)
    mods);

  bindToHyprland = b: let
    modStr = modsToHyprland b.mods;
  in
    ["${modStr}, ${b.key}, ${b.hyprlandAction}"]
    ++ lib.optional (b ? altKey) "${modStr}, ${b.altKey}, ${b.hyprlandAction}";

  hyprlandBinds = lib.concatMap bindToHyprland (lib.filter (b: b ? hyprlandAction) allBinds);

  # --- skhd output ---

  modsToSkhd = mods:
    lib.concatStringsSep " + " (map (m:
      if m == "Super"
      then "alt"
      else lib.toLower m)
    mods);

  skhdKeyMap = {
    "Return" = "return";
    "Escape" = "escape";
    "Print" = "0x69"; # Not typically used on macOS
    "Left" = "left";
    "Right" = "right";
    "grave" = "0x32";
  };

  toSkhdKey = k: skhdKeyMap.${k} or k;

  bindToSkhd = b: let
    modStr = modsToSkhd b.mods;
    key = toSkhdKey b.key;
    prefix =
      if modStr == ""
      then key
      else "${modStr} - ${key}";
  in
    lib.optional (b ? skhdAction) "${prefix} : ${b.skhdAction}";

  skhdConfig = lib.concatStringsSep "\n" (lib.concatMap bindToSkhd (lib.filter (b: b ? skhdAction) allBinds));

  # --- Cheatsheet ---

  padRight = width: s: let
    padding = builtins.concatStringsSep "" (builtins.genList (_: " ") width);
  in
    builtins.substring 0 width (s + padding);

  modsToDisplay = mods:
    lib.concatStringsSep " + " (map (m:
      if isDarwin
      then
        (
          if m == "Super"
          then "Opt"
          else m
        )
      else m)
    mods);

  formatKeybind = b: let
    modsStr = modsToDisplay b.mods;
    keyDisplay = {
      "Return" = "Enter";
      "Escape" = "Esc";
      "Left" = "Left";
      "Right" = "Right";
      "grave" = "`";
    };
    keyStr = keyDisplay.${b.key} or b.key;
    altKeyStr =
      if b ? altKey
      then
        "/"
        + (keyDisplay.${b.altKey} or b.altKey)
      else "";
    combo =
      if modsStr == ""
      then "${keyStr}${altKeyStr}"
      else "${modsStr} + ${keyStr}${altKeyStr}";
  in "${padRight 30 combo}${b.desc}";

  cheatsheetText = lib.concatStringsSep "\n" (
    # Regular bindings (not workspace or nav)
    (map formatKeybind keybinds)
    ++ lib.optionals isLinux [
      # Workspace bindings (Hyprland only — macOS uses native Mission Control)
      (let
        prefix = modsToDisplay ["Super"];
      in "${padRight 30 "${prefix} + 1-0"}Workspace 1-10")
      (let
        prefix = modsToDisplay ["Super" "Shift"];
      in "${padRight 30 "${prefix} + 1-0"}Move to workspace 1-10")
    ]
    ++ lib.optionals isLinux (map formatKeybind spaceNavBinds)
    ++ [
      (let
        prefix = modsToDisplay ["Super"];
      in "${padRight 30 "${prefix} + ?"}This cheatsheet")
    ]
  );

  cheatsheetFile = pkgs.writeText "keybind-cheatsheet" cheatsheetText;

  # Cheatsheet viewer (platform-specific)
  showKeybindsDarwin = pkgs.writeShellScript "show-keybinds" ''
    ${pkgs.kitty}/bin/kitty --class keybind-cheatsheet \
      --override initial_window_width=80c \
      --override initial_window_height=40c \
      sh -c '${pkgs.fzf}/bin/fzf --disabled --header "Keybindings" < ${cheatsheetFile}'
  '';

  showKeybindsLinux = pkgs.writeShellScript "show-keybinds" ''
    ${pkgs.rofi}/bin/rofi -dmenu -i -no-custom -p "Keybindings" \
      -theme-str 'window {width: 50%;} listview {lines: 20;}' \
      < ${cheatsheetFile}
  '';

  showKeybinds =
    if isDarwin
    then showKeybindsDarwin
    else showKeybindsLinux;

  # Add cheatsheet binding to platform configs
  cheatsheetSkhdLine = "shift + alt - 0x2C : ${showKeybinds}"; # 0x2C is / (slash), shift+/ = ?
  cheatsheetHyprlandLine = "$mod SHIFT, slash, exec, ${showKeybinds}";
in {
  options.programs.tiling-wm = {
    enable = lib.mkEnableOption "tiling window manager (yabai/skhd on macOS, Hyprland on Linux)";

    apps = {
      terminal = lib.mkOption {
        type = lib.types.str;
        default = "kitty";
        description = "Terminal emulator launch command";
      };
      browser = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open -a Firefox"
          else "firefox";
        description = "Browser launch command";
      };
      discord = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open -a Discord"
          else "discord";
        description = "Discord launch command";
      };
      music = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open -a Spotify"
          else "spotify";
        description = "Music player launch command";
      };
      mail = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open -a 'Microsoft Outlook'"
          else "evolution";
        description = "Mail client launch command";
      };
      messaging = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open -a Slack"
          else "signal-desktop";
        description = "Messaging app launch command";
      };
      zoom = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open -a zoom.us"
          else "zoom";
        description = "Zoom launch command";
      };
      fileManager = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open ~"
          else "thunar";
        description = "File manager launch command";
      };
      claude = lib.mkOption {
        type = lib.types.str;
        default =
          if isDarwin
          then "open -a Claude"
          else "claude-desktop";
        description = "Claude desktop launch command";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Expose generated data for consumption by platform modules
    # Hyprland binds (list of strings for settings.bind)
    programs.hyprland-desktop.generatedBinds = hyprlandBinds ++ [cheatsheetHyprlandLine];

    # macOS: skhd config, package, and launchd agent
    xdg.configFile."skhd/skhdrc" = lib.mkIf isDarwin {
      text = skhdConfig + "\n" + cheatsheetSkhdLine + "\n";
    };

    home.packages = lib.mkIf isDarwin [pkgs.skhd];

    launchd.agents.skhd = lib.mkIf isDarwin {
      enable = true;
      config = {
        ProgramArguments = ["${pkgs.skhd}/bin/skhd" "-c" "${config.xdg.configHome}/skhd/skhdrc"];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };

    # macOS: Grant TCC (Accessibility/Screen Recording) permissions for current nix store paths.
    # After every `hms`, nix store paths change and macOS TCC permissions break.
    # This activation script updates the TCC database so skhd/yabai/raycast work immediately.
    home.activation.grantAccessibility = lib.mkIf isDarwin (
      let
        raycastEnabled = config.programs.raycast.enable;
        raycastBin = "${pkgs.raycast}/Applications/Raycast.app/Contents/MacOS/Raycast";
        tccDb = "/Library/Application Support/com.apple.TCC/TCC.db";

        # Build DELETE clause for all managed apps
        deleteClauses =
          "client LIKE '%/bin/skhd' OR client LIKE '%/bin/yabai'"
          + lib.optionalString raycastEnabled " OR client LIKE '%Raycast%'";

        # Build INSERT statements for Accessibility
        accessibilityInserts = lib.concatStringsSep "\n" (
          [
            "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceAccessibility', '${pkgs.skhd}/bin/skhd', 1, 2, 3, 1);"
            "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceAccessibility', '${pkgs.yabai}/bin/yabai', 1, 2, 3, 1);"
          ]
          ++ lib.optionals raycastEnabled [
            "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceAccessibility', '${raycastBin}', 1, 2, 3, 1);"
          ]
        );

        # Build INSERT statements for Screen Recording (raycast only)
        screenCaptureInserts =
          lib.optionalString raycastEnabled
          "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceScreenCapture', '${raycastBin}', 1, 2, 3, 1);";
      in
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          echo "Updating macOS TCC permissions for skhd, yabai${lib.optionalString raycastEnabled ", raycast"}..."
          /usr/bin/sudo /usr/bin/sqlite3 "${tccDb}" "DELETE FROM access WHERE ${deleteClauses};"
          /usr/bin/sudo /usr/bin/sqlite3 "${tccDb}" "${accessibilityInserts}"
          ${lib.optionalString (screenCaptureInserts != "") ''/usr/bin/sudo /usr/bin/sqlite3 "${tccDb}" "${screenCaptureInserts}"''}
          /usr/bin/sudo /usr/bin/killall tccd 2>/dev/null || true
          echo "TCC permissions updated."

          # Restart all managed services to pick up new binaries and TCC permissions.
          # This is critical because nix-darwin restarts yabai BEFORE this activation
          # script runs, so yabai will have failed (exit 78) due to stale TCC entries.
          # Restarting here ensures all services start with correct permissions.
          UID_NUM=$(/usr/bin/id -u)
          for svc in org.nixos.yabai org.nix-community.home.skhd org.nix-community.home.sketchybar; do
            /bin/launchctl bootout "gui/$UID_NUM/$svc" 2>/dev/null || true
          done
          sleep 1
          for svc in org.nixos.yabai org.nix-community.home.skhd org.nix-community.home.sketchybar; do
            plist="$HOME/Library/LaunchAgents/$svc.plist"
            if [ -f "$plist" ]; then
              /bin/launchctl bootstrap "gui/$UID_NUM" "$plist" 2>/dev/null || true
            fi
          done
          echo "Services restarted."
        ''
    );
  };
}
