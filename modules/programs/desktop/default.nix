{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  isAarch64Linux = pkgs.stdenv.hostPlatform.system == "aarch64-linux";

  fontPackages = with pkgs; [
    font-awesome
    noto-fonts
    nerd-fonts.meslo-lg
    nerd-fonts.noto
  ];
in {
  imports = [
    ../../theme.nix
    ./firefox.nix
    ./evolution.nix
    ./keybindings.nix
    ./kitty.nix
    ./ghostty
    ./gpg-agent.nix
    ./kicad
    ./pwas.nix
    ./sketchybar.nix
    ./raycast.nix
    ./screenshots.nix
    ./yabai.nix
    ./hyprland
  ];

  # Firefox owns links, Chromium owns the PWAs.
  #
  # Chromium had drifted into being the system default simply by being
  # installed, so every link from mail, the terminal or a chat opened in the
  # browser kept around for two web apps. Setting this explicitly puts links
  # back in the browser actually used for browsing.
  #
  # The PWAs are unaffected: their desktop entries Exec chromium directly
  # rather than asking for "a browser", so the default can move without
  # touching them.
  #
  # CAVEAT: this governs links handed to the desktop by other applications.
  # A cross-origin link clicked INSIDE a Chromium --app window is opened by
  # Chromium itself rather than handed to xdg, so those are expected to stay
  # in Chromium. Unverified -- confirming it needs a real click.
  # http/https go to the router (below), which hands most links to Firefox and
  # the claimed hosts to their app. Everything else goes straight to Firefox.
  xdg.mimeApps = lib.mkIf (!isDarwin) {
    enable = true;
    defaultApplications = let
      browser = ["firefox.desktop"];
    in {
      "text/html" = browser;
      "x-scheme-handler/about" = browser;
      "x-scheme-handler/unknown" = browser;

      # Adopted from the hand-written mimeapps.list this file replaces.
      # Registering them here is not optional tidying: taking ownership of the
      # file without carrying these forward would silently break claude:// and
      # claude-cli:// links, which nothing would report until one failed to
      # open.
      "x-scheme-handler/claude" = ["claude.desktop"];
      "x-scheme-handler/claude-cli" = ["claude-code-url-handler.desktop"];
      "inode/directory" = ["org.gnome.Nautilus.desktop"];
    };
  };

  # The file already existed, written by whichever app last called
  # xdg-settings, so Home Manager refused to clobber it and activation failed.
  # Taking it over is the point -- link handling is declared here now -- but it
  # does mean an app that calls xdg-settings can no longer make itself the
  # default: the file is a store symlink, and the change has to come from this
  # config instead.
  xdg.configFile."mimeapps.list".force = lib.mkIf (!isDarwin) true;

  # Services with no Linux client worth running. Meet because meetings have to
  # happen somewhere and it is the one platform that works on every machine
  # here -- macOS, Windows, Linux x86_64 and, critically, Linux aarch64, where
  # Zoom, Slack, Discord and Teams all ship no native client at all.
  programs = {
    pwas-router.enable = true;

    pwa-profiles.google.internalOrigins = [
      "https://accounts.google.com"
      "https://myaccount.google.com"
    ];

    pwas = {
      apple-music = {
        name = "Apple Music";
        url = "https://music.apple.com";
        categories = ["AudioVideo" "Audio" "Player"];
      };

      # Chromium, so this is a real app window rather than another tabbed
      # browser -- the whole point being to keep a daily tool out of tab hell.
      # externalLinksOut is what makes that affordable: chat answers are mostly
      # links out, and without it they would open in Chromium.
      chatgpt = {
        name = "ChatGPT";
        url = "https://chatgpt.com";
        externalLinksOut = true;
        internalOrigins = ["https://auth.openai.com"];
      };

      gmail = {
        name = "Gmail";
        url = "https://mail.google.com";
        externalLinksOut = true;
        profile = "google";

        # Mail is the biggest source of links into other things, so claiming its
        # own host keeps a mail link from a chat opening the app rather than a
        # tab.
        handles = ["mail.google.com"];
      };

      # Chromium here, deliberately differing from ChatGPT above: Meet is
      # somewhere you sit rather than follow links out of, and Chromium is what
      # Asahi users report working for Meet -- Google ships no Chrome for Linux
      # aarch64 at all.
      meet = {
        name = "Google Meet";
        url = "https://meet.google.com";

        externalLinksOut = true;
        profile = "google";

        # A meeting link from mail or chat opens the app on that meeting rather
        # than a browser tab, which is the whole point of having the app.
        handles = ["meet.google.com"];
      };

      # Google apps share one vendor-isolated profile: one login, without making
      # those cookies available to Apple Music, ChatGPT, or ordinary Chromium.
      youtube = {
        name = "YouTube";
        url = "https://www.youtube.com";
        categories = ["AudioVideo" "Video"];
        profile = "google";
        handles = [
          "www.youtube.com"
          "youtube.com"
          "youtu.be"
        ];
      };

      youtube-tv = {
        name = "YouTube TV";
        url = "https://tv.youtube.com";
        categories = ["AudioVideo" "Video" "TV"];
        profile = "google";
        handles = ["tv.youtube.com"];
      };
    };
  };

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
    [
      yubikey-manager

      vscode

      aichat

      podman
      # Note: podman-desktop GUI installed via Homebrew on macOS
    ]
    ++ pkgs.lib.optionals (!isAarch64Linux) [
      # Apple Music desktop client via CastLabs Electron (Widevine DRM).
      # Provided by the sidra flake; aarch64-linux is unsupported upstream.
      sidra
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
      evolution
      gnome-online-accounts-gtk
      nautilus
      gimp
      vlc
      sioyek
      # Doubles as the PWA host (`chromium --app=<url>`) for services with no
      # native Linux client.
      chromium

      # kicad and freecad gained aarch64-linux support; verified they evaluate
      # on the MacBook, so they no longer belong in the exclusion list below.
      kicad
      freecad
    ]
    ++ pkgs.lib.optionals (!isDarwin && !isAarch64Linux) [
      # Still x86_64-linux only. Both are prebuilt upstream binaries with no
      # aarch64 Linux build, so nixpkgs refuses to evaluate them here:
      #   "Refusing to evaluate package ... it is not available on the
      #    requested hostPlatform"
      discord
    ];

  # Secret Service provider for apps that use org.freedesktop.secrets (e.g. Evolution)
  services.gnome-keyring = lib.mkIf (!isDarwin) {
    enable = true;
    components = ["secrets"];
  };
}
