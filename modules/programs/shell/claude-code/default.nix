{
  pkgs,
  lib,
  ...
}: {
  programs.claude-code = {
    enable = true;

    settings = {
      sandbox = {
        enabled = true;
        autoAllowBashIfSandboxed = true;
        allowUnsandboxedCommands = true;
        excludedCommands = ["ssh"];
        network = {
          allowedDomains = [
            "*"
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

    memory.text = ''
      # Global Claude Code Instructions

      ## Git Commits
      - Never add a `Co-Authored-By` line to commit messages
    '';
  };

  home.packages =
    lib.optionals pkgs.stdenv.isLinux [pkgs.bubblewrap pkgs.socat];
}
