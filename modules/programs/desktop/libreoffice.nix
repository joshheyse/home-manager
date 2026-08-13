{
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isLinux;
  libreoffice = lib.getExe pkgs.libreoffice-fresh;

  launch = component:
    pkgs.writeShellScript "libreoffice-${component}" ''
      ${pkgs.hyprland}/bin/hyprctl dispatch submap reset
      exec ${libreoffice} --${component}
    '';

  components = {
    W = "writer";
    C = "calc";
    I = "impress";
    D = "draw";
    M = "math";
    B = "base";
  };

  componentBinds = lib.mapAttrsToList (key: component: "bind = , ${key}, exec, ${launch component}") components;
in {
  wayland.windowManager.hyprland.extraConfig = lib.mkIf isLinux ''
    # LibreOffice chord (Super+O, then component key)
    submap = libreoffice
    ${lib.concatStringsSep "\n" componentBinds}
    bind = , escape, submap, reset
    submap = reset
  '';
}
