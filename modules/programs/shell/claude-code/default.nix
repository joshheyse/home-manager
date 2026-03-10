{
  pkgs,
  lib,
  config,
  ...
}: {
  options.programs.claude-code.settings = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    description = "Attrset merged into ~/.claude/settings.json. Multiple modules can contribute keys.";
  };

  config = {
    programs.claude-code.settings = {
      sandbox = {
        enabled = true;
        autoAllowBashIfSandboxed = true;
        allowUnsandboxedCommands = true;
        excludedCommands = ["ssh"];
        network = {
          allowedDomains = [
            "github.com"
            "api.github.com"
            "*.nixos.org"
            "cache.nixos.org"
            "*.docker.io"
            "*.docker.com"
            "ghcr.io"
            "quay.io"
          ];
          allowLocalBinding = false;
        };
      };

      permissions = {
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

    home.packages =
      lib.optionals pkgs.stdenv.isLinux [pkgs.bubblewrap pkgs.socat];

    home.file = {
      ".claude/settings.json".text = builtins.toJSON config.programs.claude-code.settings;

      ".claude/CLAUDE.md".text = ''
        # Global Claude Code Instructions

        ## Git Commits
        - Never add a `Co-Authored-By` line to commit messages
      '';
    };
  };
}
