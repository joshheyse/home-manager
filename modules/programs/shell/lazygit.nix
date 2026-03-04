{
  pkgs,
  config,
  ...
}: let
  theme = config.theme.tokyoNight;
in {
  programs.lazygit = {
    enable = true;
    package = pkgs.lazygit;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        theme = {
          activeBorderColor = [theme.blue "bold"];
          inactiveBorderColor = [theme.fgGutter];
          searchingActiveBorderColor = [theme.cyan "bold"];
          optionsTextColor = [theme.blue];
          selectedLineBgColor = [theme.bgHighlight];
          cherryPickedCommitFgColor = [theme.cyan];
          cherryPickedCommitBgColor = [theme.blue0];
          markedBaseCommitFgColor = [theme.cyan];
          markedBaseCommitBgColor = [theme.blue0];
          unstagedChangesColor = [theme.red];
          defaultFgColor = [theme.fg];
        };
      };
    };
  };
}
