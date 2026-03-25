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
      bind  = , XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle

      # Brightness keys (SwayOSD)
      binde = , XF86MonBrightnessUp, exec, swayosd-client --brightness raise
      binde = , XF86MonBrightnessDown, exec, swayosd-client --brightness lower
    '';
  };
}
