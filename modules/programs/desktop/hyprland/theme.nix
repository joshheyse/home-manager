# Tokyo Night color palette for Hyprland desktop
# Used by all Hyprland-related modules for consistent theming
{lib, ...}: {
  options.theme.tokyoNight = {
    bg = lib.mkOption {default = "#1a1b26";};
    bgDark = lib.mkOption {default = "#16161e";};
    bgHighlight = lib.mkOption {default = "#292e42";};
    fg = lib.mkOption {default = "#c0caf5";};
    fgDark = lib.mkOption {default = "#a9b1d6";};
    blue = lib.mkOption {default = "#7aa2f7";};
    cyan = lib.mkOption {default = "#7dcfff";};
    green = lib.mkOption {default = "#9ece6a";};
    magenta = lib.mkOption {default = "#bb9af7";};
    orange = lib.mkOption {default = "#ff9e64";};
    red = lib.mkOption {default = "#f7768e";};
    yellow = lib.mkOption {default = "#e0af68";};
    border = lib.mkOption {default = "#3b4261";};
    borderActive = lib.mkOption {default = "#7aa2f7";};
  };
}
