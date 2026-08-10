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
  inherit (pkgs) kvantum-tokyo-night;
  bibataModernIceHyprcursor =
    pkgs.runCommand "bibata-modern-ice-hyprcursor-1.1" {
      nativeBuildInputs = [pkgs.gnutar pkgs.gzip];
    } ''
      mkdir -p "$out/share/icons/Bibata-Modern-Ice"
      tar -xzf ${pkgs.fetchurl {
        url = "https://github.com/LOSEARDES77/Bibata-Cursor-hyprcursor/releases/download/v1.1/hypr_Bibata-Modern-Ice.tar.gz";
        hash = "sha256-1fgSRHnNOrZ6toVHqiMTpnzY2laoZgSV9fVHu6PS0QI=";
      }} -C "$out/share/icons/Bibata-Modern-Ice"
    '';
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
        name = "Bibata-Modern-Ice";
        package = pkgs.bibata-cursors;
        size = 24;
      };
      gtk4.theme = config.gtk.theme;
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
      bibataModernIceHyprcursor
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
