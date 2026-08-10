# SwayOSD — on-screen display for volume/brightness changes
# Provides visual feedback popups when pressing media keys
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  inherit (pkgs.stdenv) isLinux;
  brightness = direction:
    lib.concatStringsSep " " (
      lib.optional cfg.autoBrightness.enable "${pkgs.coreutils}/bin/touch \"$XDG_RUNTIME_DIR/auto-brightness.pause\" &&"
      ++ ["swayosd-client --brightness ${direction}"]
    );
in {
  config = lib.mkIf (cfg.enable && isLinux) {
    services.swayosd = {
      enable = true;
    };

    # Media key bindings using binde (repeat-enabled)
    wayland.windowManager.hyprland.extraConfig = ''

      # Volume keys (SwayOSD)
      binde = , XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise
      binde = , XF86AudioLowerVolume, exec, swayosd-client --output-volume lower
      bind  = , XF86AudioMute, exec, swayosd-client --output-volume mute-toggle
      # wpctl rather than swayosd-client, and it is not a preference: swayosd
      # 0.3.1 talks to PulseAudio, and the default source on this machine is a
      # PipeWire filter-chain node (Asahi's mic DSP: `effect_output.j416-mic`,
      # not the hardware "Built-in Audio Headset Microphone"). swayosd exits 0
      # and mutes nothing. Output mute works, which is what made this look like
      # a dead key rather than a broken command.
      #
      # Costs the OSD popup for this one key. The waybar microphone module
      # covers it and covers it better -- it is on screen the whole time
      # rather than for two seconds after a keypress.
      bind  = , XF86AudioMicMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

      # Brightness keys (SwayOSD)
      binde = , XF86MonBrightnessUp, exec, ${brightness "raise"}
      binde = , XF86MonBrightnessDown, exec, ${brightness "lower"}
    '';
  };
}
