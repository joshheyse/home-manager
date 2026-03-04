{pkgs, ...}: {
  programs.bat = {
    enable = true;
    package = pkgs.bat;
    config = {
      theme = "tokyonight_night";
    };
  };
}
