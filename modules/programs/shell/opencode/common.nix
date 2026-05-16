# Common opencode wiring - the default agent set and AGENTS.md.
#
# Import this from any per-host opencode wiring file (e.g. desktop.nix).
# It contributes to upstream `programs.opencode` (from home-manager 25.11)
# without enabling it - hosts that import it AND set `enable = true` get
# the bundled content; the contributions are inert otherwise.
#
# Every regular .md file in ./agents/ is enumerated at eval time and
# becomes a `programs.opencode.agents.<stem>` entry. To add a new agent
# to the default set, drop the file in. To override one on a specific
# host, set `programs.opencode.agents.<name> = lib.mkForce ./your.md;`
# in the host wiring. To append a host-only agent, set
# `programs.opencode.agents.<name> = ./your.md;` (no force needed).
{lib, ...}: let
  agentDir = ./agents;
  agentFiles = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir agentDir);
  agents =
    lib.mapAttrs' (
      n: _:
        lib.nameValuePair (lib.removeSuffix ".md" n) (agentDir + "/${n}")
    )
    agentFiles;
in {
  programs.opencode = {
    rules = ./AGENTS.md;
    inherit agents;
    # Bundled tokyonight matches the rest of the repo (kitty, tmux, bat,
    # lazygit, ...). bg = #1a1b26 == home-manager/modules/theme.nix bg.
    settings.theme = "tokyonight";
  };
}
