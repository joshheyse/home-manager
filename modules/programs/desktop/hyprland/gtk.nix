# GTK and Qt theme configuration - Tokyo Night
# Applies to all GTK and Qt applications
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  inherit (pkgs.stdenv) isLinux;
  kvantum-tokyo-night = pkgs.callPackage ../../../../pkgs/kvantum-tokyo-night {};
in {
  config = lib.mkIf (cfg.enable && isLinux) {
    # GTK theming
    gtk = {
      enable = true;
      theme = {
        name = "Tokyonight-Dark";
        package = pkgs.tokyonight-gtk-theme;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      cursorTheme = {
        name = "Adwaita";
        size = 24;
      };
    };

    # Qt theming via Kvantum with Tokyo Night
    qt = {
      enable = true;
      platformTheme.name = "kvantum";
      style.name = "kvantum";
    };

    # Kvantum packages and theme
    home.packages = [
      pkgs.libsForQt5.qtstyleplugin-kvantum
      pkgs.kdePackages.qtstyleplugin-kvantum
      kvantum-tokyo-night
    ];

    # Configure Kvantum to use Tokyo Night
    xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
      [General]
      theme=Kvantum-Tokyo-Night
    '';

    xdg.configFile."Kvantum/Kvantum-Tokyo-Night".source = "${kvantum-tokyo-night}/share/Kvantum/Kvantum-Tokyo-Night";

    # Set dark mode preference for apps that check this
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  };
}
