{
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isLinux;

  apps = {
    A = "apple-tv";
    Z = "prime-video";
    H = "hulu";
    N = "netflix";
    Y = "youtube";
    T = "youtube-tv";
    P = "paramount-plus";
  };

  launch = app:
    pkgs.writeShellScript "streaming-${app}" ''
      ${pkgs.hyprland}/bin/hyprctl dispatch submap reset
      exec ${lib.getExe' pkgs.gtk3 "gtk-launch"} ${app}
    '';

  appBinds = lib.mapAttrsToList (key: app: "bind = , ${key}, exec, ${launch app}") apps;
in {
  wayland.windowManager.hyprland.extraConfig = lib.mkIf isLinux ''
    # Streaming chord (Super+T, then service key)
    submap = streaming
    ${lib.concatStringsSep "\n" appBinds}
    bind = , escape, submap, reset
    submap = reset
  '';
}
