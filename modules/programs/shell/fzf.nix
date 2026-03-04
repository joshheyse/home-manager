{
  pkgs,
  config,
  ...
}: let
  theme = config.theme.tokyoNight;
in {
  programs.fzf = {
    enable = true;
    package = pkgs.fzf;
    enableZshIntegration = true;

    colors = {
      "fg" = theme.fg;
      "bg" = theme.bg;
      "hl" = theme.magenta;
      "fg+" = theme.fg;
      "bg+" = theme.bgHighlight;
      "hl+" = theme.cyan;
      "info" = theme.blue;
      "prompt" = theme.green;
      "pointer" = theme.red;
      "marker" = theme.orange;
      "spinner" = theme.yellow;
      "header" = theme.comment;
    };

    defaultCommand = "fd --type f --exclude .git --hidden --follow";
    defaultOptions = [
      "--preview 'bat --color always -n {}'"
      "--bind 'ctrl-/:toggle-preview,end:preview-down,home:preview-up,ctrl-a:select-all+accept'"
      "--ansi"
      "--select-1"
      "--height 40%"
      "--reverse"
      "--tiebreak=begin"
    ];

    changeDirWidgetCommand = "fd --type d --exclude .git --hidden --follow";
    changeDirWidgetOptions = [
      "--preview 'ls -l {}'"
      "--bind 'ctrl-/:toggle-preview'"
      "--preview-window=right:20%"
    ];

    fileWidgetCommand = "fd --type f --exclude .git --hidden --follow";
    fileWidgetOptions = [
      "--preview 'bat --color always {} | head -120'"
      "--preview-window=right:33%"
    ];
  };
}
