# Keep the cursor conventional during normal movement, but magnify it when it
# is shaken so it is easy to find on large or multiple displays.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  inherit (cfg) dynamicCursors;
  inherit (pkgs.stdenv) isLinux;
in {
  options.programs.hyprland-desktop.dynamicCursors = {
    enable = lib.mkEnableOption "cursor enlargement on shake";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hypr-dynamic-cursors;
      description = "Dynamic cursors package built against the active Hyprland package";
    };
  };

  config = lib.mkIf (cfg.enable && dynamicCursors.enable && isLinux) {
    wayland.windowManager.hyprland = {
      plugins = [dynamicCursors.package];
      settings.plugin."dynamic-cursors" = {
        enabled = true;
        mode = "none";
        shake = {
          enabled = true;
          nearest = false;
          threshold = 6.0;
          base = 3.0;
          speed = 0.0;
          influence = 0.0;
          limit = 3.0;
          timeout = 1200;
          effects = false;
        };
        hyprcursor = {
          enabled = true;
          nearest = false;
          resolution = -1;
          fallback = "clientside";
        };
      };
    };
  };
}
