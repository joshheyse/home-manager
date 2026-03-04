{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  cfg = config.programs.tiling-wm;
in {
  config = lib.mkIf (cfg.enable && isDarwin) {
    # Note: yabai is configured at the system level via nix-darwin
    # This file provides user-level yabai scripting support if needed

    home.packages = [pkgs.yabai];
  };
}
