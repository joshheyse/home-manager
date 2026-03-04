# Tokyo Night color palette — shared across all modules
# Sourced from folke/tokyonight.nvim (night variant)
# Apps with native Tokyo Night themes (kitty, nvim, tmux, ghostty, gtk)
# use their named themes. Apps needing hex values pull from here.
{lib, ...}: {
  options.theme.tokyoNight = {
    # Backgrounds
    bg = lib.mkOption {default = "#1a1b26";};
    bgDark = lib.mkOption {default = "#16161e";};
    bgDarkest = lib.mkOption {default = "#0C0E14";};
    bgHighlight = lib.mkOption {default = "#292e42";};
    terminalBlack = lib.mkOption {default = "#414868";};

    # Foregrounds
    fg = lib.mkOption {default = "#c0caf5";};
    fgDark = lib.mkOption {default = "#a9b1d6";};
    fgGutter = lib.mkOption {default = "#3b4261";};
    comment = lib.mkOption {default = "#565f89";};
    dark3 = lib.mkOption {default = "#545c7e";};
    dark5 = lib.mkOption {default = "#737aa2";};

    # Blues
    blue = lib.mkOption {default = "#7aa2f7";};
    blue0 = lib.mkOption {default = "#3d59a1";};
    blue1 = lib.mkOption {default = "#2ac3de";};
    blue2 = lib.mkOption {default = "#0db9d7";};
    blue5 = lib.mkOption {default = "#89ddff";};
    blue6 = lib.mkOption {default = "#b4f9f8";};
    blue7 = lib.mkOption {default = "#394b70";};

    # Accent colors
    cyan = lib.mkOption {default = "#7dcfff";};
    green = lib.mkOption {default = "#9ece6a";};
    green1 = lib.mkOption {default = "#73daca";};
    green2 = lib.mkOption {default = "#41a6b5";};
    teal = lib.mkOption {default = "#1abc9c";};
    red = lib.mkOption {default = "#f7768e";};
    red1 = lib.mkOption {default = "#db4b4b";};
    magenta = lib.mkOption {default = "#bb9af7";};
    magenta2 = lib.mkOption {default = "#ff007c";};
    purple = lib.mkOption {default = "#9d7cd8";};
    orange = lib.mkOption {default = "#ff9e64";};
    yellow = lib.mkOption {default = "#e0af68";};

    # Git diff
    gitAdd = lib.mkOption {default = "#449dab";};
    gitChange = lib.mkOption {default = "#6183bb";};
    gitDelete = lib.mkOption {default = "#914c54";};

    # UI aliases (backward compat with existing Hyprland consumers)
    border = lib.mkOption {default = "#3b4261";};
    borderActive = lib.mkOption {default = "#7aa2f7";};
  };
}
