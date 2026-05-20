# Single source of truth for whether this home-manager configuration is
# being activated on a "portable" remote target — i.e., reached via
# scripts/portable-ssh + nix-portable.
#
# nix-portable provides a real /nix/store on the remote, so most
# home-manager modules don't need to know they're running portably —
# antidote plugins, atuin, neovim, custom binaries all work normally.
#
# This flag is mainly useful for skipping things that would *recurse*
# back through the same machinery (e.g. installing portable-ssh on a
# host you reached via portable-ssh) or for daemons that don't make
# sense on a transient remote shell.
#
# Convention: gate per-module bits with `lib.mkIf (!config.portable.enable)`.
{lib, ...}: {
  options.portable = {
    enable = lib.mkEnableOption ''
      portable activation — this home-manager configuration is being
      activated on a remote host via nix-portable. Most modules ignore
      this flag; it exists for cases where a module would otherwise
      recurse (e.g. portable-ssh installing itself) or where a
      daemon-style integration isn't useful on a transient remote shell.
    '';
  };
}
