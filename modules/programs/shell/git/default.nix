{
  lib,
  pkgs,
  ...
}: let
  git-tidy = pkgs.writeShellApplication {
    name = "git-tidy";
    runtimeInputs = [pkgs.git];
    text = builtins.readFile ./git-tidy.sh;
  };
in {
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

  # Git-oriented shell functions (gpt, glm, groot, gwa, gwan). Some commands need
  # argument/runtime config logic, so those live as functions rather than
  # aliases. Written here and sourced from the shared zshrc; initContent is
  # `types.lines` so this merges with the sourcing done in zsh.nix.
  programs.zsh.initContent = lib.mkOrder 1100 ''
    source ~/.config/zsh/git-functions.zsh
  '';

  home = {
    # pre-commit is wired into the devShell + flake.nix shellHook to install
    # git hooks. The generated hook scripts embed an absolute /nix/store path
    # to pre-commit itself, so the binary must stay GC-rooted in the user's
    # profile; otherwise the next `nix-collect-garbage` orphans the hook.
    #
    # git-tidy: branch + worktree hygiene (alias gtidy).
    packages = [pkgs.pre-commit git-tidy];

    file.".config/zsh/git-functions.zsh".source = ./functions.zsh;

    shellAliases = {
      ga = "git add ";
      gaa = "git add .";
      gaA = "git add -A";
      gcm = "git commit -m";
      gca = "git commit -a -m";
      gcp = "git cherry-pick";
      gb = "git branch";
      gbc = "git checkout -b";
      gba = "git branch -a";
      gbd = "git branch -d";
      gbD = "git branch -D";
      gco = "git checkout";
      gd = "git diff";
      gdc = "git diff --cached";
      gds = "git diff --stat";
      gdt = "git difftool";
      gf = "git fetch --prune";
      gfa = "git fetch --all --prune";
      gl = "git log --oneline --decorate --date=relative";
      glg = "git log --graph --oneline --decorate --all --date=relative";
      gll = "git log --oneline --decorate --date=relative --max-count=20";
      gls = "git log --stat --oneline --decorate --date=relative";
      gm = "git merge";
      gma = "git merge --abort";
      gpd = "git pull";
      gpp = "git pull && git push";
      gpu = "git push -u origin HEAD";
      grb = "git rebase";
      grba = "git rebase --abort";
      grbc = "git rebase --continue";
      grv = "git remote -v";
      gs = "git status";
      gshow = "git show --stat";
      gsa = "git stash --all";
      gsl = "git stash list";

      # Worktrees. gwa/gwan are functions (see git-functions.zsh); the rest are
      # thin passthroughs.
      gwl = "git worktree list";
      gwm = "git worktree move";
      gwr = "git worktree remove";
      gwp = "git worktree prune";

      # Branch + worktree cleanup: delete merged/gone branches (local + remote)
      # and prune stale worktrees, with a confirmation prompt.
      gtidy = "git-tidy";
    };
  };
}
