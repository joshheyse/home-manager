{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  programs.firefox = {
    enable = true;

    # Platform-specific package handling
    # On macOS: Use Nix package directly
    # On Linux: Use nixGL-wrapped Firefox for proper OpenGL support
    package =
      if isDarwin
      then pkgs.firefox # Nix-managed Firefox on macOS
      else (config.lib.nixGL.wrap pkgs.firefox); # Use nixGL on Linux for proper OpenGL support

    # Note: Profile management disabled to preserve existing Firefox profiles
    # Uncomment and customize if you want to manage profiles via Nix
    # profiles = {
    #   default = {
    #     id = 0;
    #     name = "default";
    #     isDefault = true;
    #
    #     # Search engines
    #     search = {
    #       force = true;
    #       default = "ddg"; # DuckDuckGo ID
    #       order = ["ddg" "google"]; # Search engine IDs
    #     };
    #
    #     # Firefox settings (about:config)
    #     settings = {
    #       # Privacy settings (from your existing config)
    #       "privacy.trackingprotection.enabled" = true;
    #       "privacy.trackingprotection.socialtracking.enabled" = true;
    #       "privacy.donottrackheader.enabled" = true;
    #
    #       # Enhanced privacy: disable prefetching
    #       "network.dns.disablePrefetch" = true;
    #       "network.prefetch-next" = false;
    #       "network.http.speculative-parallel-limit" = 0;
    #
    #       # Disable telemetry
    #       "datareporting.healthreport.uploadEnabled" = false;
    #       "datareporting.policy.dataSubmissionEnabled" = false;
    #       "toolkit.telemetry.archive.enabled" = false;
    #       "toolkit.telemetry.enabled" = false;
    #       "toolkit.telemetry.unified" = false;
    #
    #       # UI settings (from your existing config)
    #       "browser.startup.homepage" = "duckduckgo.com";
    #       "browser.newtabpage.enabled" = false;
    #       "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
    #       "browser.newtabpage.activity-stream.feeds.topsites" = false;
    #       "browser.newtabpage.activity-stream.showSearch" = false;
    #       "browser.toolbars.bookmarks.visibility" = "never";
    #
    #       # Performance
    #       "browser.sessionstore.interval" = 15000; # Save session every 15 seconds
    #       "browser.cache.disk.enable" = true;
    #
    #       # Download settings (from your existing config)
    #       "browser.download.useDownloadDir" = false; # Ask where to save
    #       "browser.download.folderList" = 1;
    #
    #       # Tab behavior
    #       "browser.tabs.loadInBackground" = true;
    #       "browser.tabs.warnOnClose" = true;
    #
    #       # Disable features (from your existing config)
    #       "extensions.pocket.enabled" = false;
    #       "general.autoScroll" = false;
    #       "signon.rememberSignons" = false; # Password manager disabled
    #       "extensions.formautofill.creditCards.enabled" = false;
    #
    #       # Claude AI integration
    #       "browser.ml.chat.provider" = "https://claude.ai/new";
    #
    #       # Don't show about:config warning
    #       "browser.aboutConfig.showWarning" = false;
    #     };
    #
    #     # Extensions detected from your existing Firefox profile:
    #     # - uBlock Origin (ad blocker)
    #     # - Dark Reader (dark mode for websites)
    #     # - Bitwarden (password manager)
    #     # - Vimium-FF (vim keybindings for Firefox)
    #     # - Shortkeys (custom keyboard shortcuts)
    #     # - Plasma Browser Integration (KDE integration, Linux only)
    #     #
    #     # To enable extension management via Nix, add NUR to your flake inputs:
    #     #
    #     # In flake.nix inputs:
    #     #   nur.url = "github:nix-community/NUR";
    #     #
    #     # Then in extraSpecialArgs, pass: inherit nur;
    #     #
    #     # Then uncomment and customize the extensions below:
    #     #
    #     # extensions = with pkgs.nur.repos.rycee.firefox-addons; [
    #     #   ublock-origin
    #     #   darkreader
    #     #   privacy-badger
    #     #   bitwarden
    #     #   vimium
    #     # ];
    #   };
    # };

    # Additional Firefox policies (enterprise policies)
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisplayBookmarksToolbar = "never"; # Hidden per your existing config
      PasswordManagerEnabled = false; # Disabled per your existing config (using Bitwarden)

      # Don't lock preferences, allow user modifications
      Preferences = {};
    };
  };
}
