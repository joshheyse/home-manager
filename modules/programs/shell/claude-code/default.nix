{
  pkgs,
  lib,
  ...
}: let
  landrun = pkgs.callPackage ../../../../pkgs/landrun {};
  claude-sandbox = pkgs.writeShellApplication {
    name = "claude-sandbox";
    runtimeInputs = [landrun pkgs.claude-code];
    text = builtins.readFile ./claude-sandbox.sh;
  };
in {
  home.packages =
    lib.optionals pkgs.stdenv.isLinux
    [claude-sandbox];

  home.file = {
    ".claude/CLAUDE.md".text = ''
      # Global Claude Code Instructions

      ## Git Commits
      - Never add a `Co-Authored-By` line to commit messages

      ## Sandbox Mode (`claude-sandbox`)

      You may be launched via `claude-sandbox`, which runs you with `--dangerously-skip-permissions` inside a **Linux Landlock kernel sandbox**. Landlock restrictions are enforced by the kernel and cannot be bypassed — failed operations return EACCES errors. Do not retry or attempt workarounds for blocked operations.

      ### Filesystem Access
      - **Read-write:** `$PWD` (working directory), `~/.claude`, `/tmp`
      - **Read + execute:** `/nix/store` (all binaries and packages)
      - **Read-only:** `$HOME`, `/proc`, `/dev`, `/sys`, `/etc`, `/run`, `/usr`, `/lib`, `/lib64`, `/bin`
      - **No access:** Everything else. You **cannot** write to `~/Documents`, `~/Downloads`, `/opt`, or any path outside the above list.
      - More-specific rules win: `~/.claude` is writable even though `$HOME` is read-only.

      ### Network Access
      - **Allowed outbound TCP ports:** 443 (HTTPS), 80 (HTTP), 22 (SSH)
      - **All other ports are blocked.** You cannot connect to localhost services (databases, Redis, dev servers, etc.).
      - DNS resolution works (UDP is unrestricted by Landlock).

      ### What This Means in Practice
      - Git clone/fetch/push over SSH or HTTPS: **works**
      - API calls to anthropic.com or other HTTPS services: **works**
      - `curl http://localhost:5432` or connecting to local databases: **blocked**
      - Writing files outside `$PWD`, `~/.claude`, or `/tmp`: **blocked**
      - Running binaries from `/nix/store`: **works**
      - Installing packages via nix: **works** (writes go to `/nix/store` which is mounted ROX, but nix-daemon handles writes)
    '';
  };
}
