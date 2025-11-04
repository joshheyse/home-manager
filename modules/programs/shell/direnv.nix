_: {
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;

    config = {
      global = {
        # Silence direnv output (already set in zsh, but good to be explicit)
        hide_env_diff = true;
      };
    };
  };
}
