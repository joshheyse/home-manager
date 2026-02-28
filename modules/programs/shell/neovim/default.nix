{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withPython3 = true;
    withRuby = true;
    extraPackages = with pkgs; [
      cargo
      fd
      gcc
      gnumake
      ghostscript
      (imagemagick.override {ghostscriptSupport = true;})
      luajitPackages.luarocks
      poppler_utils
      python3
      python3Packages.pip
      ripgrep
      rustc
      tree-sitter
    ];
  };

  # Link neovim config files to ~/.config/nvim/
  xdg.configFile = {
    # Link the entire config directory
    "nvim" = {
      source = ./config;
      recursive = true;
    };

    # Link root-level config files into nvim/ for tooling consistency
    "nvim/selene.toml" = {
      source = ../../../../selene.toml;
    };
    "nvim/.stylua.toml" = {
      source = ../../../../.stylua.toml;
    };
    "nvim/neovim.yml" = {
      source = ../../../../neovim.yml;
    };
  };
}
