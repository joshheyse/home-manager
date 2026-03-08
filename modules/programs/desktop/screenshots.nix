# Cross-platform screenshot/recording management
# - Chord: Super+P → R(egion) / F(ull) / W(indow) / V(ideo) / D(irectory)
# - Auto-copies file path to clipboard
# - Auto-converts MOV recordings to MP4 (macOS)
# - Toast notifications on completion
# - macOS: fswatch watcher also handles built-in Cmd+Shift+3/4/5 screenshots
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin isLinux;

  cfg = config.programs.screenshots;
  dir = cfg.directory;

  # --- macOS screenshot scripts ---

  darwinRegion = pkgs.writeShellScript "ss-region" ''
    mkdir -p "${dir}"
    file="${dir}/Screenshot_$(date +%Y-%m-%d_%H%M%S).png"
    /usr/sbin/screencapture -i "$file"
    if [ -f "$file" ]; then
      printf '%s' "$file" | pbcopy
      /usr/bin/osascript -e 'display notification "Path copied to clipboard" with title "Screenshot"'
    fi
  '';

  darwinFull = pkgs.writeShellScript "ss-full" ''
    mkdir -p "${dir}"
    file="${dir}/Screenshot_$(date +%Y-%m-%d_%H%M%S).png"
    /usr/sbin/screencapture "$file"
    if [ -f "$file" ]; then
      printf '%s' "$file" | pbcopy
      /usr/bin/osascript -e 'display notification "Path copied to clipboard" with title "Screenshot"'
    fi
  '';

  darwinWindow = pkgs.writeShellScript "ss-window" ''
    mkdir -p "${dir}"
    file="${dir}/Screenshot_$(date +%Y-%m-%d_%H%M%S).png"
    /usr/sbin/screencapture -iW "$file"
    if [ -f "$file" ]; then
      printf '%s' "$file" | pbcopy
      /usr/bin/osascript -e 'display notification "Path copied to clipboard" with title "Screenshot"'
    fi
  '';

  darwinVideo = pkgs.writeShellScript "ss-video" ''
    mkdir -p "${dir}"
    file="${dir}/Recording_$(date +%Y-%m-%d_%H%M%S).mov"
    /usr/sbin/screencapture -v "$file"
    # fswatch watcher handles MOV→MP4 conversion and clipboard
  '';

  # --- Linux screenshot scripts ---

  linuxRegion = pkgs.writeShellScript "ss-region" ''
    trap 'hyprctl dispatch submap reset' EXIT
    mkdir -p "${dir}"
    file="${dir}/Screenshot_$(date +%Y-%m-%d_%H%M%S).png"
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$file" || exit 0
    if [ -f "$file" ]; then
      printf '%s' "$file" | ${pkgs.wl-clipboard}/bin/wl-copy -t text/plain
      ${pkgs.libnotify}/bin/notify-send "Screenshot" "Path copied to clipboard"
    fi
  '';

  linuxFull = pkgs.writeShellScript "ss-full" ''
    trap 'hyprctl dispatch submap reset' EXIT
    mkdir -p "${dir}"
    file="${dir}/Screenshot_$(date +%Y-%m-%d_%H%M%S).png"
    ${pkgs.grim}/bin/grim "$file"
    if [ -f "$file" ]; then
      printf '%s' "$file" | ${pkgs.wl-clipboard}/bin/wl-copy -t text/plain
      ${pkgs.libnotify}/bin/notify-send "Screenshot" "Path copied to clipboard"
    fi
  '';

  linuxWindow = pkgs.writeShellScript "ss-window" ''
    trap 'hyprctl dispatch submap reset' EXIT
    mkdir -p "${dir}"
    file="${dir}/Screenshot_$(date +%Y-%m-%d_%H%M%S).png"
    geometry=$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
    ${pkgs.grim}/bin/grim -g "$geometry" "$file"
    if [ -f "$file" ]; then
      printf '%s' "$file" | ${pkgs.wl-clipboard}/bin/wl-copy -t text/plain
      ${pkgs.libnotify}/bin/notify-send "Screenshot" "Path copied to clipboard"
    fi
  '';

  linuxVideo = pkgs.writeShellScript "ss-video" ''
    trap 'hyprctl dispatch submap reset' EXIT
    PIDFILE="${dir}/.recording.pid"
    mkdir -p "${dir}"

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      # Stop recording
      kill -INT "$(cat "$PIDFILE")"
      wait "$(cat "$PIDFILE")" 2>/dev/null
      rm "$PIDFILE"
      # Find the most recent mp4
      latest=$(ls -t "${dir}"/Recording_*.mp4 2>/dev/null | head -1)
      if [ -n "$latest" ]; then
        printf '%s' "$latest" | ${pkgs.wl-clipboard}/bin/wl-copy -t text/plain
        ${pkgs.libnotify}/bin/notify-send "Recording Saved" "Path copied to clipboard"
      fi
    else
      # Start recording (records directly to MP4)
      file="${dir}/Recording_$(date +%Y-%m-%d_%H%M%S).mp4"
      ${pkgs.wf-recorder}/bin/wf-recorder -f "$file" &
      echo $! > "$PIDFILE"
      ${pkgs.libnotify}/bin/notify-send "Recording Started" "Press Opt+P → V to stop"
    fi
  '';

  # --- Platform-specific chord scripts ---

  screenshotRegion =
    if isDarwin
    then darwinRegion
    else linuxRegion;
  screenshotFull =
    if isDarwin
    then darwinFull
    else linuxFull;
  screenshotWindow =
    if isDarwin
    then darwinWindow
    else linuxWindow;
  screenshotVideo =
    if isDarwin
    then darwinVideo
    else linuxVideo;

  # --- skhd mode config (macOS) ---

  skhdScreenshotMode = ''

    # Screenshot mode (Super+P chord)
    :: screenshot
    alt - p ; screenshot
    screenshot < r : ${screenshotRegion} ; default
    screenshot < f : ${screenshotFull} ; default
    screenshot < w : ${screenshotWindow} ; default
    screenshot < v : ${screenshotVideo} ; default
    screenshot < d : open ${dir} ; default
    screenshot < escape ; default
  '';

  # --- Hyprland submap config (Linux) ---

  hyprlandScreenshotSubmap = ''

    # Screenshot submap (Super+P chord)
    bind = $mod, P, submap, screenshot
    submap = screenshot
    bind = , R, exec, ${screenshotRegion}
    bind = , F, exec, ${screenshotFull}
    bind = , W, exec, ${screenshotWindow}
    bind = , V, exec, ${screenshotVideo}
    bind = , D, exec, xdg-open ${dir}; hyprctl dispatch submap reset
    bind = , escape, submap, reset
    submap = reset
  '';

  # --- macOS fswatch watcher (handles built-in Cmd+Shift+3/4/5 screenshots) ---

  watchScreenshots = pkgs.writeShellScript "watch-screenshots" ''
    WATCH_DIR="${dir}"
    mkdir -p "$WATCH_DIR"

    ${pkgs.fswatch}/bin/fswatch -0 --event Created --exclude '\.mp4$' "$WATCH_DIR" | while IFS= read -r -d "" file; do
      case "$file" in
        *.png | *.jpg | *.jpeg)
          # Wait for file to be fully written
          sleep 0.5
          printf '%s' "$file" | pbcopy
          /usr/bin/osascript -e 'display notification "Path copied to clipboard" with title "Screenshot Saved"'
          ;;
        *.mov)
          # Run conversion in background so we don't block the watcher
          (
            # Wait for recording to finish (file no longer open by screencapture)
            while /usr/bin/lsof "$file" &>/dev/null; do
              sleep 1
            done
            sleep 0.5
            mp4="''${file%.mov}.mp4"
            if ${pkgs.ffmpeg}/bin/ffmpeg -i "$file" -c copy "$mp4" -loglevel quiet; then
              rm "$file"
              printf '%s' "$mp4" | pbcopy
              /usr/bin/osascript -e 'display notification "Converted to MP4, path copied to clipboard" with title "Recording Saved"'
            fi
          ) &
          ;;
      esac
    done
  '';
in {
  options.programs.screenshots = {
    enable = lib.mkEnableOption "screenshot management with chords, auto-clipboard, and MOV-to-MP4 conversion";

    directory = lib.mkOption {
      type = lib.types.str;
      default = "/tmp/screenshots";
      description = "Directory to save screenshots and recordings";
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Common ---

    # Ensure screenshot directory exists on activation
    home.activation.createScreenshotDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "${dir}"
    '';

    # --- macOS ---

    home.packages =
      lib.optionals isDarwin (with pkgs; [
        fswatch
        ffmpeg
      ])
      ++ lib.optionals isLinux (with pkgs; [
        grim
        slurp
        wl-clipboard
        wf-recorder
      ]);

    # Set macOS screencapture save location (for built-in shortcuts)
    targets.darwin.defaults."com.apple.screencapture" = lib.mkIf isDarwin {
      location = dir;
    };

    # skhd screenshot mode
    xdg.configFile."skhd/skhdrc".text = lib.mkIf isDarwin (lib.mkAfter skhdScreenshotMode);

    # fswatch watcher for built-in macOS screenshots and MOV→MP4 conversion
    launchd.agents.watch-screenshots = lib.mkIf isDarwin {
      enable = true;
      config = {
        ProgramArguments = ["${watchScreenshots}"];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Background";
      };
    };

    # --- Linux ---

    # Hyprland screenshot submap
    wayland.windowManager.hyprland.extraConfig = lib.mkIf isLinux hyprlandScreenshotSubmap;
  };
}
