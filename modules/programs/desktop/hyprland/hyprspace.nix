# macOS-style workspace overview. Its package is supplied by the host flake so
# it can be compiled against that host's exact Hyprland revision.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  inherit (cfg) hyprspace;
  theme = config.theme.tokyoNight;
  inherit (pkgs.stdenv) isLinux;
in {
  options.programs.hyprland-desktop.hyprspace = {
    enable = lib.mkEnableOption "Hyprspace workspace overview";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hyprspace;
      description = "Hyprspace package built against the active Hyprland package";
    };
  };

  config = lib.mkIf (cfg.enable && hyprspace.enable && isLinux) {
    wayland.windowManager.hyprland = {
      plugins = [hyprspace.package];
      settings.plugin.overview = {
        panelColor = "rgb(${lib.removePrefix "#" theme.bgDark})";
        panelBorderColor = "rgb(${lib.removePrefix "#" theme.blue})";
        workspaceActiveBackground = "rgb(${lib.removePrefix "#" theme.bgHighlight})";
        workspaceInactiveBackground = "rgb(${lib.removePrefix "#" theme.bg})";
        workspaceActiveBorder = "rgb(${lib.removePrefix "#" theme.blue})";
        workspaceInactiveBorder = "rgb(${lib.removePrefix "#" theme.comment})";
        centerAligned = true;
        showNewWorkspace = true;
        showEmptyWorkspace = true;
        exitOnClick = true;
        exitOnSwitch = true;
        switchOnDrop = true;
        autoDrag = true;
      };
    };
  };
}
