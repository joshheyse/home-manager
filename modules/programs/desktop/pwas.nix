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
# Each app gets an isolated profile by default. Apps from the same vendor can
# opt into a named profile so they share one login without sharing cookies with
# unrelated PWAs or the ordinary browser.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  cfg = config.programs.pwas;
  profileCfg = config.programs.pwa-profiles;
  rcfg = config.programs.pwas-router;

  # How an app is launched for a *given* URL. The chromium path keeps --app so
  # a claimed link still opens as an app window rather than a browser tab.
  launcher = pwa: url:
    if pwa.browser == "firefox"
    then "${lib.getExe pkgs.firefox} --new-window ${url}"
    else
      "${lib.getExe pkgs.chromium} --app=${url}"
      + (
        if usesEscape pwa
        then " --disable-extensions-except=${escapeDir pwa} --load-extension=${escapeDir pwa}"
        else " --disable-extensions"
      )
      + lib.optionalString pwa.isolate " --user-data-dir=${profileDir pwa}";

  claimants = lib.filter (pwa: pwa.handles != []) (lib.attrValues cfg);

  # Named profiles let apps from one vendor share authentication without also
  # sharing it with unrelated vendors. An unnamed isolated app still gets its
  # own URL-keyed profile, preserving the original behaviour.
  profileKey = pwa:
    if pwa.profile != null
    then "group:${pwa.profile}"
    else "app:${pwa.url}";
  profileLabel = pwa:
    if pwa.profile != null
    then pwa.profile
    else pwa.name;
  profileDir = pwa: "${config.xdg.dataHome}/pwas/${builtins.substring 0 16 (builtins.hashString "sha256" (profileKey pwa))}";

  profilePeers = pwa:
    if pwa.profile == null
    then [pwa]
    else lib.filter (peer: peer.profile == pwa.profile) (lib.attrValues cfg);

  escapePeers = pwa: lib.filter (peer: peer.externalLinksOut) (profilePeers pwa);
  usesEscape = pwa: escapePeers pwa != [];
  profileInternalOrigins = pwa:
    if pwa.profile != null && builtins.hasAttr pwa.profile profileCfg
    then profileCfg.${pwa.profile}.internalOrigins
    else [];

  # One extension is shared by every app in a named profile. This matters
  # because Chromium runs one process per user-data-dir: whichever app starts
  # first owns the process and later --load-extension flags are ignored.
  # Rules remain per source origin, so Gmail can send external links out while
  # YouTube (externalLinksOut = false) keeps its own navigation untouched.
  escapeRules = pwa:
    map (peer: {
      source = origin peer.url;
      internal =
        [(origin peer.url)]
        ++ peer.internalOrigins
        ++ profileInternalOrigins peer;
    }) (escapePeers pwa);

  # Scheme used to hand a URL back out of Chromium. Chromium refuses to give
  # web links to the desktop -- it considers itself the handler -- but it does
  # defer schemes it cannot handle, which is the only seam available.
  escapeScheme = "pwa-open";

  origin = url: let
    afterScheme = lib.removePrefix "http://" (lib.removePrefix "https://" url);
    host = lib.head (lib.splitString "/" afterScheme);
    scheme = lib.head (lib.splitString "://" url);
  in "${scheme}://${host}";

  # An unpacked extension is just a directory, so it is an ordinary
  # derivation -- no Web Store, no policy JSON, no per-machine install step.
  # Verified that Chromium 151 still honours --load-extension by loading a
  # probe extension and watching it rewrite a window title.
  escapeExtension = pwa:
    pkgs.writeTextFile {
      name = "pwa-escape-${builtins.hashString "sha256" (profileKey pwa)}";
      destination = "/manifest.json";
      text = builtins.toJSON {
        manifest_version = 3;
        name = "Open external links outside ${profileLabel pwa} profile";
        version = "1.0";
        permissions = ["webNavigation" "tabs"];
        host_permissions = ["<all_urls>"];
        background.service_worker = "background.js";
      };
    };

  # Kept separate from the manifest so the JS stays readable rather than
  # becoming a quoted blob inside toJSON.
  escapeDir = pwa:
    pkgs.runCommand "pwa-escape-${builtins.substring 0 16 (builtins.hashString "sha256" (profileKey pwa))}" {} ''
      mkdir -p $out
      cp ${escapeExtension pwa}/manifest.json $out/manifest.json
      cat > $out/background.js <<'EOF'
      // Anything that leaves this app's origin is not part of the app, so it
      // belongs in the real browser. Chromium will not hand a web URL to the
      // desktop, but it will hand over a scheme it does not recognise -- so
      // the URL is re-emitted under ${escapeScheme}: and the desktop routes it.
      const RULES = new Map(
        ${builtins.toJSON (map (rule: [rule.source rule.internal]) (escapeRules pwa))}
          .map(([source, internal]) => [source, new Set(internal)])
      );

      function isExternal(sourceUrl, targetUrl) {
        try {
          const internal = RULES.get(new URL(sourceUrl).origin);
          return internal ? !internal.has(new URL(targetUrl).origin) : false;
        } catch (e) {
          return false;
        }
      }

      // Navigate an EXISTING tab to the escape URL rather than opening one for
      // it. Chromium hands an unknown scheme to the desktop and leaves the page
      // where it was, so the app's own tab can carry the handoff and there is
      // nothing left over to clean up.
      //
      // The first attempt created a tab for the escape URL and closed it after
      // 500ms. That raced its own cleanup -- the tab was destroyed before the
      // protocol launch completed -- and since an app window cannot host tabs,
      // the tab appeared as a browser window that flashed open and shut.
      function handOff(tabId, url) {
        chrome.tabs.update(tabId, { url: "${escapeScheme}:" + url })
          .catch(() => {});
      }

      // A target=_blank link, which is how most links in a web app open.
      // sourceTabId is the app's own tab; tabId is the popup Chromium just
      // made for the link, which is closed since the desktop will handle it.
      chrome.webNavigation.onCreatedNavigationTarget.addListener((d) => {
        chrome.tabs.get(d.sourceTabId).then((source) => {
          if (!isExternal(source.url, d.url)) return;
          handOff(d.sourceTabId, d.url);
          chrome.tabs.remove(d.tabId).catch(() => {});
        }).catch(() => {});
      });

      // A plain link navigating the app window itself away from the app. The
      // escape navigation supersedes it, so the app stays where it was.
      chrome.webNavigation.onBeforeNavigate.addListener((d) => {
        if (d.frameId !== 0) return;
        chrome.tabs.get(d.tabId).then((source) => {
          if (!isExternal(source.url, d.url)) return;
          handOff(d.tabId, d.url);
        }).catch(() => {});
      });
      EOF
    '';

  # One case arm per claimed host. Anchored on the scheme so a host cannot be
  # spoofed by appearing later in the URL: without the leading https://, a
  # pattern like *meet.google.com* would also match
  # https://evil.example/meet.google.com/x and hand it to the app.
  routerArm = pwa: host: ''
    http://${host}/*|https://${host}/*|http://${host}|https://${host})
      exec ${launcher pwa "\"$url\""}
      ;;
  '';

  # Catches the escaped URLs and puts them back on the normal path. Kept
  # separate from the router so the escape hatch is visible rather than being
  # a special case buried in routing.
  escapeHandler = pkgs.writeShellScript "pwa-escape-open" ''
    url="''${1#${escapeScheme}:}"

    if [ -z "$url" ]; then
      exit 0
    fi

    ${rcfg.fallback} "$url" &

    # Hyprland's global focus_on_activate is deliberately off: honoring every
    # activation request lets an agent prompt in one terminal steal focus from
    # another. Browser-bound links are the narrow exception the user expects.
    if command -v hyprctl >/dev/null 2>&1; then
      for _ in {1..20}; do
        hyprctl dispatch focuswindow 'class:^(firefox)$' >/dev/null 2>&1 && exit 0
        sleep 0.05
      done
    fi
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

    ${rcfg.fallback} "$url" &

    if command -v hyprctl >/dev/null 2>&1; then
      for _ in {1..20}; do
        hyprctl dispatch focuswindow 'class:^(firefox)$' >/dev/null 2>&1 && exit 0
        sleep 0.05
      done
    fi
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
  options.programs = {
    pwas = lib.mkOption {
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

          isolate = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Give the app its own browser profile, so its cookies, storage and
              fingerprinting surface are its own.

              Without this every app shares the default profile: one cookie jar,
              one identity, and an ad network embedded in two of them can join
              the sessions up. Isolated, each app is a separate browser as far as
              the sites inside it can tell.

              Isolation is per app unless profile names a group. Apps from the
              same provider can therefore share a sign-in while remaining
              isolated from unrelated PWAs and the ordinary browser. Setting
              isolate to false instead uses Chromium's ordinary default profile.

              Profiles live under $XDG_DATA_HOME/pwas, which impermanence
              persists, so logins survive a reboot.

              chromium only; the Firefox path uses your normal profile.
            '';
          };

          profile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "google";
            description = ''
              Optional named isolation group. Isolated apps with the same name
              share one Chromium profile and therefore one vendor login, while
              remaining separate from every other named or per-app profile.

              Only meaningful when isolate is true.
            '';
          };

          externalLinksOut = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Send links that leave the app's own origin to the normal browser
              instead of opening them in Chromium.

              Chromium only does this if made to. It treats itself as the handler
              for web links and will not pass one to the desktop, so a sideloaded
              extension re-emits external URLs under a scheme Chromium does NOT
              handle, which it then does hand over. Chromium asks for
              confirmation the first time; tick "always allow".

              chromium only -- a Firefox-hosted app already opens links in
              Firefox, being Firefox.
            '';
          };

          internalOrigins = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            example = ["https://auth.example.com"];
            description = ''
              Additional origins that remain inside this app when
              externalLinksOut is enabled. Use this for authentication origins
              whose redirects must share the app's isolated browser profile.
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

    pwa-profiles = lib.mkOption {
      default = {};
      description = ''
        Shared settings for named PWA isolation profiles. Apps select one with
        programs.pwas.<name>.profile.
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options.internalOrigins = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          example = ["https://accounts.google.com"];
          description = ''
            Authentication and account-management origins that remain internal
            for every app in this profile when externalLinksOut is enabled.
          '';
        };
      });
    };

    pwas-router = {
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
  };

  config = lib.mkIf (!isDarwin) {
    xdg.mimeApps = lib.mkIf rcfg.enable {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/http" = ["pwa-router.desktop"];
        "x-scheme-handler/https" = ["pwa-router.desktop"];
        "x-scheme-handler/${escapeScheme}" = ["pwa-escape-open.desktop"];
      };
    };

    xdg.desktopEntries =
      lib.optionalAttrs rcfg.enable {
        # Registered as the http/https handler, so it must not also appear in
        # the launcher as something you could click.
        pwa-escape-open = {
          name = "PWA external link";
          type = "Application";
          terminal = false;
          noDisplay = true;
          exec = "${escapeHandler} %u";
          mimeType = ["x-scheme-handler/${escapeScheme}"];
        };

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

        # Same `launcher` the router uses. It was briefly built here as well
        # and the two drifted immediately -- the launcher grew --load-extension
        # and --user-data-dir while these entries silently kept launching a
        # bare, un-isolated window. One definition, both callers.
        #
        # No --class on the chromium path, on purpose: Chromium accepts the
        # flag and then ignores it in --app mode, deriving the class from the
        # URL instead -- observed as chrome-meet.google.com__-Default rather
        # than the requested value.
        exec = launcher pwa pwa.url;

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
