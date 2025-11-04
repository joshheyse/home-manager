{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;

  sketchybarConfig = ''
    # bash

    #!/bin/bash

    # Use full path to sketchybar CLI
    SKETCHYBAR="${pkgs.sketchybar}/bin/sketchybar"

    # Tokyo Night Storm color scheme
    export BG_TRANSPARENT=0x00000000
    export FG=0xffa9b1d6
    export ACCENT=0xff7aa2f7
    export RED=0xfff7768e
    export ORANGE=0xffff9e64
    export YELLOW=0xffe0af68
    export GREEN=0xff9ece6a
    export CYAN=0xff73daca
    export PURPLE=0xffbb9af7
    export GREY=0xff565f89

    # Bar appearance
    $SKETCHYBAR --bar \
      height=32 \
      blur_radius=0 \
      position=top \
      padding_left=10 \
      padding_right=10 \
      color=$BG_TRANSPARENT

    # Default item settings
    $SKETCHYBAR --default \
      updates=when_shown \
      icon.font="MesloLGS Nerd Font:Bold:14.0" \
      icon.color=$FG \
      icon.padding_left=4 \
      icon.padding_right=4 \
      label.font="MesloLGS Nerd Font:Regular:13.0" \
      label.color=$FG \
      label.padding_left=4 \
      label.padding_right=4 \
      background.color=$BG_TRANSPARENT \
      background.corner_radius=5 \
      background.height=24

    # Left side items
    # Spaces/Workspaces
    SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10")
    for i in "''${!SPACE_ICONS[@]}"; do
      sid=$(($i+1))
      $SKETCHYBAR --add space space.$sid left \
        --set space.$sid \
          associated_space=$sid \
          icon="''${SPACE_ICONS[i]}" \
          icon.padding_left=8 \
          icon.padding_right=8 \
          label.padding_right=0 \
          background.color=$GREY \
          background.corner_radius=5 \
          background.height=24 \
          script="$SKETCHYBAR --set \$NAME background.color=\$([ \$SELECTED = true ] && echo $ACCENT || echo $GREY)" \
          click_script="yabai -m space --focus $sid"
    done

    # Media (Spotify/Music)
    $SKETCHYBAR --add item media left \
      --set media \
        icon= \
        icon.color=$GREEN \
        label.max_chars=30 \
        scroll_texts=on \
        background.drawing=on \
        script="~/.config/sketchybar/plugins/media.sh" \
      --subscribe media media_change

    # Center items
    # Clock
    $SKETCHYBAR --add item clock center \
      --set clock \
        update_freq=10 \
        icon= \
        icon.color=$CYAN \
        script="$SKETCHYBAR --set clock label=\"\$(date '+%a %d %b %H:%M')\"" \
        click_script="open -a Calendar"

    # Right side items
    # Volume
    $SKETCHYBAR --add item volume right \
      --set volume \
        icon= \
        icon.color=$PURPLE \
        script="~/.config/sketchybar/plugins/volume.sh" \
      --subscribe volume volume_change

    # WiFi
    $SKETCHYBAR --add item wifi right \
      --set wifi \
        icon=󰖩 \
        icon.color=$CYAN \
        script="~/.config/sketchybar/plugins/wifi.sh" \
        update_freq=30 \
        click_script="open 'x-apple.systempreferences:com.apple.Network-Settings.extension'"

    # Disk
    $SKETCHYBAR --add item disk right \
      --set disk \
        icon=󰋊 \
        icon.color=$YELLOW \
        update_freq=60 \
        script="$SKETCHYBAR --set disk label=\"\$(df -h / | awk 'NR==2 {print \$5}')\""

    # Memory
    $SKETCHYBAR --add item memory right \
      --set memory \
        icon= \
        icon.color=$ORANGE \
        update_freq=5 \
        script="$SKETCHYBAR --set memory label=\"\$(memory_pressure | grep 'System-wide memory free percentage:' | awk '{printf \"%.0f%%\", 100-\$5}')\""

    # CPU
    $SKETCHYBAR --add item cpu right \
      --set cpu \
        icon= \
        icon.color=$RED \
        update_freq=5 \
        script="$SKETCHYBAR --set cpu label=\"\$(ps -A -o %cpu | awk '{s+=\$1} END {printf \"%.0f%%\", s}')\""

    # Battery
    $SKETCHYBAR --add item battery right \
      --set battery \
        update_freq=30 \
        script="~/.config/sketchybar/plugins/battery.sh" \
      --subscribe battery system_woke power_source_change

    # Finalize
    $SKETCHYBAR --update
  '';
in {
  config = lib.mkIf isDarwin {
    # Install sketchybar package
    home.packages = [pkgs.sketchybar];

    # Auto-start sketchybar via launchd
    launchd.agents.sketchybar = {
      enable = true;
      config = {
        ProgramArguments = ["${pkgs.sketchybar}/bin/sketchybar"];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sketchybar.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sketchybar.log";
      };
    };

    # Create sketchybar config file and plugin scripts
    home.file = {
      ".config/sketchybar/sketchybarrc" = {
        text = sketchybarConfig;
        executable = true;
      };
      ".config/sketchybar/plugins/media.sh" = {
        text = ''
          #!/bin/bash
          SKETCHYBAR="${pkgs.sketchybar}/bin/sketchybar"

          # Get current media info
          STATE=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null)

          if [ "$STATE" = "playing" ]; then
            TRACK=$(osascript -e 'tell application "Spotify" to name of current track as string')
            ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track as string')
            $SKETCHYBAR --set media label="$TRACK - $ARTIST" drawing=on
          else
            $SKETCHYBAR --set media drawing=off
          fi
        '';
        executable = true;
      };

      ".config/sketchybar/plugins/volume.sh" = {
        text = ''
          #!/bin/bash
          SKETCHYBAR="${pkgs.sketchybar}/bin/sketchybar"

          VOLUME=$(osascript -e 'output volume of (get volume settings)')
          MUTED=$(osascript -e 'output muted of (get volume settings)')

          if [ "$MUTED" = "true" ]; then
            ICON=""
          else
            ICON=""
          fi

          $SKETCHYBAR --set volume icon="$ICON" label="$VOLUME%"
        '';
        executable = true;
      };

      ".config/sketchybar/plugins/wifi.sh" = {
        text = ''
          #!/bin/bash
          SKETCHYBAR="${pkgs.sketchybar}/bin/sketchybar"

          # Check if we have an active network connection (excluding loopback)
          if ifconfig | grep -q "inet.*broadcast"; then
            $SKETCHYBAR --set wifi label="Connected" icon.color=0xff73daca
          else
            $SKETCHYBAR --set wifi label="Disconnected" icon.color=0xfff7768e
          fi
        '';
        executable = true;
      };

      ".config/sketchybar/plugins/battery.sh" = {
        text = ''
          #!/bin/bash
          SKETCHYBAR="${pkgs.sketchybar}/bin/sketchybar"

          PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
          CHARGING=$(pmset -g batt | grep 'AC Power')

          if [ -n "$CHARGING" ]; then
            ICON="󰂄"
            COLOR=0xff9ece6a
          else
            if [ "$PERCENTAGE" -lt 20 ]; then
              ICON="󰂎"
              COLOR=0xfff7768e
            elif [ "$PERCENTAGE" -lt 50 ]; then
              ICON="󰁾"
              COLOR=0xffff9e64
            elif [ "$PERCENTAGE" -lt 80 ]; then
              ICON="󰂀"
              COLOR=0xffe0af68
            else
              ICON="󰁹"
              COLOR=0xff9ece6a
            fi
          fi

          $SKETCHYBAR --set battery icon="$ICON" icon.color=$COLOR label="$PERCENTAGE%"
        '';
        executable = true;
      };
    };
  };
}
