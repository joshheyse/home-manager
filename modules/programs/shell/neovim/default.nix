{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs) stdenv;
  # nixpkgs 26.05's neovim wrapper only wires the python3 provider into the
  # rc it manages; home-manager wraps with wrapRc = false, so withPython3 /
  # extraPython3Packages never reach nvim (Molten's remote-plugin host fails
  # with "Failed to load python3 host"). Wire the host explicitly via a
  # --cmd flag, mirroring the pre-26.05 wrapper, until HM/nixpkgs fix this.
  pythonDeps = ps:
    with ps; [
      pynvim
      jupyter-client
      cairosvg
      ipython
      nbformat
      pyperclip
    ];
  pythonEnv = pkgs.python3.withPackages pythonDeps;
in {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withPython3 = true;
    withRuby = true;
    extraPackages = with pkgs;
      [
        alejandra
        cargo
        deadnix
        fd
        gcc
        gnumake
        ghostscript
        (imagemagick.override {ghostscriptSupport = true;})
        python3Packages.debugpy
        python3Packages.jupytext
        lua-language-server
        luajitPackages.luarocks
        nil
        poppler-utils
        python3
        python3Packages.pip
        ripgrep
        rustc
        statix
        stylua
        tree-sitter
      ]
      # SystemVerilog tooling is currently broken on darwin in nixpkgs:
      # - sv-lang (veridian's dep) is marked broken
      # - verible has a hash mismatch on its bazel deps tarball
      ++ lib.optionals stdenv.hostPlatform.isLinux [
        veridian # SystemVerilog LSP (slang-based diagnostics)
        verible # verible-verilog-{format,lint}: SystemVerilog format + lint CLI
      ];
    extraPython3Packages = pythonDeps;
    extraWrapperArgs = [
      "--add-flags"
      ''--cmd "lua vim.g.python3_host_prog='${pythonEnv}/bin/python3'"''
    ];
    extraLuaPackages = ps: [ps.magick];
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
