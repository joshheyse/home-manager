# Progressive web apps, as first-class desktop launchers.
#
# Several services this desktop depends on have no Linux client worth running
# -- and on aarch64 Linux, frequently none at all: Zoom, Slack, Discord and
# Teams all ship x86_64-only desktop packages, and Teams withdrew its Linux
# client entirely in favour of a PWA. The browser is the client, so the
# launcher should say so rather than leaving you to find a tab.
#
# `chromium --app=<url>` opens a window with no tab strip, omnibox or
# bookmarks bar, which is what makes it feel like an application instead of a
# browser window that happens to be pointed somewhere. Chromium rather than
# Firefox because Google Meet in particular is better supported there, and
# Google ships no Chrome build for Linux on aarch64.
#
# These deliberately share the default browser profile rather than each taking
# a --user-data-dir. Isolation sounds tidier but means signing in separately
# per app and losing the session on every profile change; a PWA you have to log
# into twice is worse than a bookmark.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  cfg = config.programs.pwas;
  rcfg = config.programs.pwas-router;

  # How an app is launched for a *given* URL. The chromium path keeps --app so
  # a claimed link still opens as an app window rather than a browser tab.
  launcher = pwa: url:
    if pwa.browser == "firefox"
    then "${lib.getExe pkgs.firefox} --new-window ${url}"
    else "${lib.getExe pkgs.chromium} --app=${url}";

  claimants = lib.filter (pwa: pwa.handles != []) (lib.attrValues cfg);

  # One case arm per claimed host. Anchored on the scheme so a host cannot be
  # spoofed by appearing later in the URL: without the leading https://, a
  # pattern like *meet.google.com* would also match
  # https://evil.example/meet.google.com/x and hand it to the app.
  routerArm = pwa: host: ''
    http://${host}/*|https://${host}/*|http://${host}|https://${host})
      exec ${launcher pwa "\"$url\""}
      ;;
  '';

  # Dispatcher registered as the http/https handler, because xdg associations
  # are per-scheme and cannot express "this host goes to that app".
  routerScript = pkgs.writeShellScript "pwa-router" ''
    url="$1"

    if [ -z "$url" ]; then
      exec ${rcfg.fallback}
    fi

    case "$url" in
    ${lib.concatMapStringsSep "\n" (pwa: lib.concatMapStringsSep "\n" (routerArm pwa) pwa.handles) claimants}
    esac

    exec ${rcfg.fallback} "$url"
  '';

  # Chromium's own naming for an --app window: "chrome-" then the host, then
  # the (empty) path as a pair of underscores, then the profile. Verified
  # against both entries below with `hyprctl clients`.
  #
  # Only correct for a bare-host URL. A URL with a path folds the path into the
  # class, so those need wmClass set explicitly.
  derivedClass = url: let
    host =
      lib.head (lib.splitString "/"
        (lib.removePrefix "http://" (lib.removePrefix "https://" url)));
  in "chrome-${host}__-Default";
in {
  options.programs.pwas = lib.mkOption {
    default = {};
    description = ''
      Web applications to expose as desktop launchers, keyed by a short
      identifier used for the window class.

      Linux only. macOS reads no .desktop files, and Chromium is not among the
      packages this config installs there.
    '';
    example = lib.literalExpression ''
      {
        meet = {
          name = "Google Meet";
          url = "https://meet.google.com";
        };
      }
    '';
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Name shown in the application launcher.";
        };

        url = lib.mkOption {
          type = lib.types.str;
          description = "Address the app window opens.";
        };

        categories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["Network"];
          description = "freedesktop menu categories.";
        };

        browser = lib.mkOption {
          type = lib.types.enum ["chromium" "firefox"];
          default = "chromium";
          description = ''
            Which browser hosts the app, and it is a real trade rather than a
            preference.

            chromium gets a proper app window -- no tab strip, no omnibox --
            but a cross-origin link clicked inside it is opened by Chromium
            itself rather than handed to the desktop, so it lands in Chromium
            no matter what the system default says.

            firefox has no --app equivalent (only --kiosk, which is
            fullscreen), so this is an ordinary window. In exchange links
            behave: they open in the browser you actually browse with.

            Pick per app. Something you mostly follow links out of wants
            firefox; something you sit inside, or that needs Chromium's media
            support, wants chromium.
          '';
        };

        handles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          example = ["meet.google.com"];
          description = ''
            Hosts whose links this app should claim, so a meeting link in a
            calendar or chat opens the app rather than a browser tab.

            Requires programs.pwas-router.enable. Matching is on host, and the
            clicked URL is passed through -- opening the actual meeting, not
            the app's home page.
          '';
        };

        wmClass = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Window class the app reports, used to match the window back to its
            launcher. Defaults to the value Chromium derives from a bare-host
            URL.

            Set this explicitly if the URL has a path -- Chromium folds the
            path into the class and the default will not match. Confirm the
            real value with `hyprctl clients`, since guessing it wrong fails
            silently: the app still launches, it just shows up in the taskbar
            as an anonymous second Chromium.
          '';
        };
      };
    });
  };

  options.programs.pwas-router = {
    enable = lib.mkEnableOption ''
      routing links by host, so an app can claim its own URLs.

      xdg associations are per-SCHEME, not per-host: the desktop can say
      "https goes to Firefox" but not "https://meet.google.com goes to Meet".
      This registers a small dispatcher as the http/https handler which reads
      the URL and hands it to whichever app claimed that host, falling back to
      the ordinary browser
    '';

    fallback = lib.mkOption {
      type = lib.types.str;
      default = "${lib.getExe pkgs.firefox}";
      defaultText = lib.literalExpression "lib.getExe pkgs.firefox";
      description = "Command handed every URL no app claimed.";
    };
  };

  config = lib.mkIf (!isDarwin) {
    xdg.mimeApps = lib.mkIf rcfg.enable {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/http" = ["pwa-router.desktop"];
        "x-scheme-handler/https" = ["pwa-router.desktop"];
      };
    };

    xdg.desktopEntries =
      lib.optionalAttrs rcfg.enable {
        # Registered as the http/https handler, so it must not also appear in
        # the launcher as something you could click.
        pwa-router = {
          name = "Web link router";
          type = "Application";
          terminal = false;
          noDisplay = true;
          exec = "${routerScript} %u";
          mimeType = ["x-scheme-handler/http" "x-scheme-handler/https"];
        };
      }
      // lib.mapAttrs (_key: pwa: {
        inherit (pwa) name categories;
        type = "Application";
        terminal = false;

        # No --class on the chromium path, on purpose: Chromium accepts the
        # flag and then ignores it in --app mode, deriving the class from the
        # URL instead -- observed as chrome-meet.google.com__-Default rather
        # than the requested value.
        exec =
          if pwa.browser == "firefox"
          then "${lib.getExe pkgs.firefox} --new-window ${pwa.url}"
          else "${lib.getExe pkgs.chromium} --app=${pwa.url}";

        # StartupWMClass matches the window back to this entry so the taskbar
        # shows the app rather than an anonymous second browser. It has to be
        # what the browser actually reports, not what we would prefer.
        #
        # Only meaningful for chromium: a Firefox-hosted app is an ordinary
        # Firefox window and reports the same class as every other one, so
        # there is nothing to distinguish it by.
        settings = lib.optionalAttrs (pwa.browser == "chromium") {
          StartupWMClass =
            if pwa.wmClass != null
            then pwa.wmClass
            else derivedClass pwa.url;
        };
      })
      cfg;
  };
}
