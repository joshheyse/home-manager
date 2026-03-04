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
      then pkgs.firefox
      else (config.lib.nixGL.wrap pkgs.firefox);

    profiles.default = {
      id = 0;
      name = "default";
      isDefault = true;
      # Stable path — works on fresh machines, no random prefix.
      # One-time migration for existing installs:
      #   macOS: mv ~/Library/Application\ Support/Firefox/Profiles/<old> ~/Library/Application\ Support/Firefox/Profiles/nix-managed
      #   Linux: mv ~/.mozilla/firefox/<old> ~/.mozilla/firefox/nix-managed
      path = "nix-managed";

      search = {
        force = true;
        default = "ddg";
        order = ["ddg" "google"];
      };

      settings = {
        # --- Homepage & new tab ---
        "browser.startup.homepage" = "duckduckgo.com";
        "browser.newtabpage.enabled" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.showSearch" = false;

        # --- Privacy ---
        "privacy.donottrackheader.enabled" = true;
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;
        "network.dns.disablePrefetch" = true;
        "network.prefetch-next" = false;
        "network.http.speculative-parallel-limit" = 0;

        # --- Telemetry ---
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionEnabled" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;

        # --- Downloads ---
        "browser.download.useDownloadDir" = false;

        # --- Tabs ---
        "browser.tabs.warnOnClose" = true;
        "browser.tabs.loadInBackground" = true;

        # --- Appearance ---
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
        "browser.theme.content-theme" = 0; # Dark
        "browser.theme.toolbar-theme" = 0; # Dark

        # --- Sidebar ---
        "sidebar.revamp" = true;
        "sidebar.main.tools" = "aichat,syncedtabs,history,bookmarks";
        "sidebar.visibility" = "hide-sidebar";

        # --- AI integration ---
        "browser.ml.chat.provider" = "https://claude.ai/new";

        # --- Password / autofill (using Bitwarden) ---
        "signon.rememberSignons" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        "services.sync.engine.passwords" = false;
        "services.sync.declinedEngines" = "passwords,creditcards";

        # --- Misc ---
        "extensions.pocket.enabled" = false;
        "general.autoScroll" = false;
        "browser.aboutConfig.showWarning" = false;
        "browser.profiles.enabled" = true;
      };
    };

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisplayBookmarksToolbar = "never";
      PasswordManagerEnabled = false;
      Preferences = {};
    };
  };
}
