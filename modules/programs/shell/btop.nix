{
  pkgs,
  config,
  ...
}: let
  theme = config.theme.tokyoNight;
in {
  programs.btop = {
    enable = true;
    package = pkgs.btop;
    settings = {
      theme = "tokyo_night";
      theme_background = false;
      vim_keys = true;
    };
    themes = {
      tokyo_night = ''
        theme[main_bg]="${theme.bg}"
        theme[main_fg]="${theme.fgDark}"
        theme[title]="${theme.fgDark}"
        theme[hi_fg]="${theme.cyan}"
        theme[selected_bg]="${theme.terminalBlack}"
        theme[selected_fg]="${theme.fgDark}"
        theme[inactive_fg]="${theme.comment}"
        theme[proc_misc]="${theme.cyan}"
        theme[cpu_box]="${theme.comment}"
        theme[mem_box]="${theme.comment}"
        theme[net_box]="${theme.comment}"
        theme[proc_box]="${theme.comment}"
        theme[div_line]="${theme.comment}"
        theme[temp_start]="${theme.green}"
        theme[temp_mid]="${theme.yellow}"
        theme[temp_end]="${theme.red}"
        theme[cpu_start]="${theme.green}"
        theme[cpu_mid]="${theme.yellow}"
        theme[cpu_end]="${theme.red}"
        theme[free_start]="${theme.green}"
        theme[free_mid]="${theme.yellow}"
        theme[free_end]="${theme.red}"
        theme[cached_start]="${theme.green}"
        theme[cached_mid]="${theme.yellow}"
        theme[cached_end]="${theme.red}"
        theme[available_start]="${theme.green}"
        theme[available_mid]="${theme.yellow}"
        theme[available_end]="${theme.red}"
        theme[used_start]="${theme.green}"
        theme[used_mid]="${theme.yellow}"
        theme[used_end]="${theme.red}"
        theme[download_start]="${theme.green}"
        theme[download_mid]="${theme.yellow}"
        theme[download_end]="${theme.red}"
        theme[upload_start]="${theme.green}"
        theme[upload_mid]="${theme.yellow}"
        theme[upload_end]="${theme.red}"
      '';
    };
  };
}
