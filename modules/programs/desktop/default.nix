{pkgs, ...}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  imports = [
    ./kitty.nix
    ./ghostty
    ./gpg-agent.nix
    ./kicad
    ./sketchybar.nix
    ./raycast.nix
    ./yabai.nix
  ];

  home.packages = with pkgs;
    [
      noto-fonts
      nerd-fonts.meslo-lg
      nerd-fonts.noto

      yubikey-manager

      ghidra
      vscode

      aichat
      weechat

      podman
      # Note: podman-desktop GUI installed via Homebrew on macOS
    ]
    ++ pkgs.lib.optionals isDarwin [
      # macOS-only packages
      # sketchybar installed and configured via sketchybar.nix module
      raycast
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
