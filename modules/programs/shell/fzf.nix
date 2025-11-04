{pkgs, ...}: {
  programs.fzf = {
    enable = true;
    package = pkgs.fzf;
    enableZshIntegration = true;

    colors = {
      "fg" = "#f8f8f2";
      "bg" = "#282a36";
      "hl" = "#bd93f9";
      "fg+" = "#f8f8f2";
      "bg+" = "#44475a";
      "hl+" = "#bd93f9";
      "info" = "#ffb86c";
      "prompt" = "#50fa7b";
      "pointer" = "#ff79c6";
      "marker" = "#ff79c6";
      "spinner" = "#ffb86c";
      "header" = "#6272a4";
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
