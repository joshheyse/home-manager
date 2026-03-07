{pkgs, ...}: {
  programs.eza = {
    enable = true;
    package = pkgs.eza;
    enableZshIntegration = true;
    extraOptions = ["--icons" "--git"];
  };

  home.shellAliases = {
    l = "eza -l";
    la = "eza -la";
    lt = "eza --tree";
  };
}
