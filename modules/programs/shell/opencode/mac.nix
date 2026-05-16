# macOS opencode wiring.
#
# Imports the default agent set + AGENTS.md via ./common.nix, then enables
# upstream `programs.opencode` (home-manager 25.11).
#
# Unlike desktop.nix, this file installs the upstream package directly:
# there is no LiteLLM proxy on macOS in this repo, and no sops secret
# wrapping. Configure cloud providers interactively the first time with:
#
#     opencode auth login
#
# To override or append agents on this host:
#   programs.opencode.agents.<name> = lib.mkForce ./your.md;  # override
#   programs.opencode.agents.<new>  = ./your.md;              # append
{
  imports = [./common.nix];

  programs.opencode = {
    enable = true;
    settings.default_agent = "general";
  };
}
