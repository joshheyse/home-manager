{pkgs, ...}: {
  programs.atuin = {
    enable = true;
    package = pkgs.atuin;
    enableZshIntegration = true;

    settings = {
      # Up arrow: session-local history only
      filter_mode_shell_up_key_binding = "session";
      search_mode_shell_up_key_binding = "prefix";

      # Ctrl-R: search everything, ranked by frecency
      filter_mode = "global";
      search_mode = "fuzzy";

      style = "compact";
      show_preview = true;
      max_preview_height = 4;

      # Store history but don't sync to a remote server
      auto_sync = false;
    };
  };
}
