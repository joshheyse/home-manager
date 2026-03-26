{
  pkgs,
  lib,
  config,
  ...
}: let
  jsonFormat = pkgs.formats.json {};

  # Nix-managed settings — these keys always win over runtime mutations
  managedSettings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    sandbox = {
      enabled = true;
      autoAllowBashIfSandboxed = true;
      allowUnsandboxedCommands = true;
      excludedCommands = ["ssh"];
      network = {
        allowedDomains = ["*"];
        allowLocalBinding = false;
      };
    };
    permissions = {
      allow = [
        "WebFetch"
        "WebSearch"
        "Edit"
        "Write"
        "Bash"
      ];
      deny = [
        "Bash(rm -rf /*:*)"
        "Bash(rm -rf /:*)"
        "Bash(chmod -R 777:*)"
        "Bash(curl * | bash:*)"
        "Bash(curl * | sh:*)"
        "Bash(wget * | bash:*)"
        "Bash(wget * | sh:*)"
      ];
    };
    enabledPlugins = {
      "clangd-lsp@claude-plugins-official" = true;
    };
  };

  managedSettingsFile = jsonFormat.generate "claude-code-managed-settings.json" managedSettings;

  managedMemoryFile = pkgs.writeText "claude-code-CLAUDE.md" ''
    # Global Claude Code Instructions

    ## Git Commits
    - Never add a `Co-Authored-By` line to commit messages
  '';
in {
  programs.claude-code = {
    enable = true;
    # Don't set settings or memory here — we manage them via activation
  };

  home.packages =
    lib.optionals pkgs.stdenv.isLinux [pkgs.bubblewrap pkgs.socat];

  home.activation.claude-code-mutable-config = lib.hm.dag.entryAfter ["writeBoundary"] ''
    claude_dir="${config.home.homeDirectory}/.claude"
    settings="$claude_dir/settings.json"
    memory="$claude_dir/CLAUDE.md"
    managed="${managedSettingsFile}"

    # Ensure directory exists
    mkdir -p "$claude_dir"

    # Settings: deep-merge nix-managed keys over any existing runtime settings.
    # Runtime keys (like theme) are preserved; nix-managed keys always win.
    if [ -f "$settings" ] && [ ! -L "$settings" ]; then
      # Existing mutable file — merge managed keys on top
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" "$managed" > "$settings.tmp"
      mv "$settings.tmp" "$settings"
    else
      # First run or was a symlink from previous home-manager generation — seed from managed
      rm -f "$settings"
      cp "$managed" "$settings"
      chmod 644 "$settings"
    fi

    # CLAUDE.md: overwrite with managed content (this is declarative intent,
    # not user-edited — user memory goes in ~/.claude/projects/*/memory/)
    rm -f "$memory"
    cp "${managedMemoryFile}" "$memory"
    chmod 644 "$memory"
  '';
}
