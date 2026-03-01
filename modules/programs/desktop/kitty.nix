{
  config,
  pkgs,
  ...
}: {
  programs.kitty = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.kitty;
    themeFile = "tokyo_night_night";
    font = {
      name = "MesloLGS Nerd Font";
      package = pkgs.nerd-fonts.meslo-lg;
      size = 12;
    };
    settings = {
      shell = "${pkgs.zsh}/bin/zsh";
      enable_audio_bell = "no";
      macos_option_as_alt = "yes";
      close_on_child_death = "yes";
      confirm_os_window_close = "0";
      background_opacity = "0.9";
      text_blink_duration = "0.5";
    };
    keybindings = {
      "${
        if pkgs.stdenv.isDarwin
        then "cmd"
        else "super"
      }+enter" = "toggle_fullscreen";
      # Send CSI u for Shift+Enter so tmux can recognize it (Kitty's native protocol isn't understood by tmux)
      "shift+enter" = "send_text all \\x1b[13;2u";
    };
  };
}
