{
  lib,
  pkgs,
  ...
}: {
  programs.git = {
    enable = true;
    package = pkgs.git;

    settings = {
      alias = {
        stash = "stash --all";
        blame = "blame -M -C -C";
        push = "push --force-with-lease";
      };

      blame = {
        coloring = "repeatedLines";
      };

      branch = {
        autosetuprebase = "always";
      };

      checkout = {
        defaultRemote = "origin";
      };

      commit = {
        gpgsign = lib.mkDefault true;
      };

      core = {
        untrackedcache = "true";
        fsmonitor = "true";
      };

      init = {
        defaultBranch = "main";
      };

      push = {
        autoSetupRemote = true;
      };

      rebase = {
        updateRefs = "true";
      };

      rerere = {
        enabled = true;
      };

      user = {
        email = lib.mkDefault "josh@heyse.us";
        name = lib.mkDefault "Josh Heyse";
        signingkey = lib.mkDefault "0xBC7AFA55FFD62335";
      };
    };
  };

  # pre-commit is wired into the devShell + flake.nix shellHook to install
  # git hooks. The generated hook scripts embed an absolute /nix/store path
  # to pre-commit itself, so the binary must stay GC-rooted in the user's
  # profile; otherwise the next `nix-collect-garbage` orphans the hook.
  home.packages = [pkgs.pre-commit];

  home.shellAliases = {
    ga = "git add ";
    gaa = "git add .";
    gaA = "git add -A";
    gcm = "git commit -m";
    gca = "git commit -a -m";
    gbc = "git checkout -b";
    gco = "git checkout";
    gd = "git diff";
    gdc = "git diff --cached";
    gpd = "git pull";
    gpp = "git pull && git push";
    gpu = "git push -u origin HEAD";
    gs = "git status";
    gsa = "git stash --all";
    gsl = "git stash list";
  };
}
