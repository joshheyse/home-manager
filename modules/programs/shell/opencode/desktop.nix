# Desktop opencode wiring.
#
# Imports the upstream `programs.opencode` module (home-manager 25.11)
# via ./common.nix for the default agent set + AGENTS.md, then layers
# desktop-specific config on top: LiteLLM provider and a wrapper that
# injects the LiteLLM virtual key from sops.
#
# To override or append agents on this host:
#   programs.opencode.agents.<name> = lib.mkForce ./your.md;  # override
#   programs.opencode.agents.<new>  = ./your.md;              # append
#
# This file is NOT imported anywhere by default. To activate opencode
# on the desktop home configuration, add it to hostModules.desktop in
# home-manager/flake.nix:
#
#     hostModules.desktop = [
#       ...
#       ./modules/programs/shell/opencode/desktop.nix
#     ];
#
# Prerequisites before enabling:
#   - LiteLLM is running on this host at 127.0.0.1:4000 (services.litellm
#     configured per-host on the NixOS side, with EnvironmentFile pointing
#     at a sops secret holding ANTHROPIC_API_KEY etc.).
#   - sops secret `opencode_litellm_key` is decrypted at /run/secrets/
#     and readable by your user (NixOS sops.secrets entry with mode 0400).
#
# Note: the /run/secrets path is Linux-only. macOS hosts that want
# opencode should write their own wiring (different sops path or use
# `opencode auth login` once).
{pkgs, ...}: {
  imports = [./common.nix];

  programs.opencode = {
    enable = true;

    # Upstream's package install is skipped; we install our own wrapper
    # (see home.packages below) so the LiteLLM key is sourced from a
    # sops secret at exec time instead of being baked into the env.
    package = null;

    settings = {
      default_agent = "general";
      provider.litellm = {
        name = "LiteLLM";
        npm = "@ai-sdk/openai-compatible";
        options = {
          baseURL = "http://127.0.0.1:4000/v1";
          apiKey = "{env:LITELLM_API_KEY}";
        };
        # Each model name becomes a "litellm/<name>" id usable in agents.
        models = {
          sonnet = {};
          opus = {};
          kimi = {};
          glm = {};
          deepseek = {};
          qwen-coder-hosted = {};
          # uncomment once homelab is online with services.llama-server
          # behind a litellm route named "qwen-coder-local":
          # qwen-coder-local = {};
        };
      };
    };
  };

  # Wrapper that sources the LiteLLM key from a sops secret before
  # exec'ing the real opencode binary. Placed in home.packages so it
  # appears on PATH as `opencode` (upstream's package install is
  # disabled above).
  home.packages = [
    (pkgs.writeShellScriptBin "opencode" ''
      set -eu
      export LITELLM_API_KEY="$(cat /run/secrets/opencode_litellm_key)"
      exec ${pkgs.opencode}/bin/opencode "$@"
    '')
  ];
}
