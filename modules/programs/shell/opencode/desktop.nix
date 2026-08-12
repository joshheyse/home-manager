# Desktop opencode wiring.
#
# Imports the upstream `programs.opencode` module (home-manager 25.11)
# via ./common.nix for the default agent set + AGENTS.md, then layers
# desktop-specific config on top: OpenRouter and a wrapper that injects its
# API key from sops only into the OpenCode process.
#
# To override or append agents on this host:
#   programs.opencode.agents.<name> = lib.mkForce ./your.md;  # override
#   programs.opencode.agents.<new>  = ./your.md;              # append
#
# The OpenRouter model catalog is built into OpenCode. Use `/models` to select
# among it rather than maintaining a stale model list here.
{
  config,
  pkgs,
  ...
}: let
  opencodeWrapped = pkgs.writeShellScriptBin "opencode" ''
    set -eu
    export OPENROUTER_API_KEY="$(cat ${config.sops.secrets."openrouter/api_key".path})"
    exec ${pkgs.opencode}/bin/opencode "$@"
  '';
in {
  imports = [./common.nix];

  programs.opencode = {
    enable = true;

    # Retain Home Manager's package integration while substituting a wrapper
    # that injects the key only into the OpenCode process.
    package = opencodeWrapped;

    settings = {
      default_agent = "general";
      provider.openrouter.options = {
        apiKey = "{env:OPENROUTER_API_KEY}";
      };
    };
  };

  # NixOS hosts use home-manager.useUserPackages, so `home.packages` is linked
  # into the system-managed per-user profile and only changes after `nrbs`.
  # Keep the CLI available after a plain `hms` by linking the same wrapper
  # through Home Manager's own file activation as well.
  home.file.".local/bin/opencode".source = "${opencodeWrapped}/bin/opencode";
}
