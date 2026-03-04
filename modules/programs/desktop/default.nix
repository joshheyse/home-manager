{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;

  fontPackages = with pkgs; [
    font-awesome
    noto-fonts
    nerd-fonts.meslo-lg
    nerd-fonts.noto
  ];
in {
  imports = [
    ./firefox.nix
    ./keybindings.nix
    ./kitty.nix
    ./ghostty
    ./gpg-agent.nix
    ./kicad
    ./sketchybar.nix
    ./raycast.nix
    ./yabai.nix
    ./hyprland
  ];

  # Enable fontconfig for proper font discovery
  fonts.fontconfig.enable = true;

  # On macOS, symlink font files into ~/Library/Fonts/Nix so apps can discover them
  home.activation.installNixFonts = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      fontDir="$HOME/Library/Fonts/Nix"
      run rm -rf "$fontDir"
      run mkdir -p "$fontDir"
      for pkg in ${lib.concatMapStringsSep " " toString fontPackages}; do
        if [ -d "$pkg/share/fonts" ]; then
          find "$pkg/share/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec ln -sf {} "$fontDir/" \;
        fi
      done
    ''
  );

  home.packages = with pkgs;
    fontPackages
    ++ [
      yubikey-manager

      vscode

      aichat

      podman
      # Note: podman-desktop GUI installed via Homebrew on macOS
    ]
    ++ pkgs.lib.optionals isDarwin [
      # macOS-only packages
      # sketchybar installed and configured via sketchybar.nix module
      # raycast installed and configured via raycast.nix module
    ]
    ++ pkgs.lib.optionals (!isDarwin) [
      # Linux-only packages (not available or don't work well on macOS via Nix)
      # These are installed via Homebrew on macOS instead
      signal-desktop
      gimp
      vlc
      kicad
      freecad
      spotify
      discord
      sioyek
    ];
}
