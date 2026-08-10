# Waybar status bar configuration
# Tokyo Night themed with workspaces, clock, system stats
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hyprland-desktop;
  theme = config.theme.tokyoNight;
  inherit (pkgs.stdenv) isLinux;

  # Colocated helper, per the repo convention for scripts only one module uses.
  # PATH is pinned so the module never depends on the login shell.
  tailscaleStatus = pkgs.writeShellScript "waybar-tailscale" ''
    export PATH="${lib.makeBinPath [pkgs.tailscale pkgs.jq pkgs.coreutils]}:$PATH"

    # Palette for the script's Pango tooltip, injected rather than hardcoded so
    # the theme module stays the single source of truth for these colours.
    export TN_DIM=${theme.comment}
    export TN_GREEN=${theme.green}
    export TN_YELLOW=${theme.yellow}
    export TN_RED=${theme.red}

    ${builtins.readFile ./waybar-tailscale.sh}
  '';

  cpuHeat = pkgs.writeShellScript "waybar-cpu" ''
    export PATH="${lib.makeBinPath [pkgs.gawk pkgs.coreutils]}:$PATH"

    export TN_DIM=${theme.comment}
    export TN_FG=${theme.cyan}
    export TN_YELLOW=${theme.yellow}
    export TN_RED=${theme.red}

    ${builtins.readFile ./waybar-cpu.sh}
  '';

  micStatus = pkgs.writeShellScript "waybar-mic" ''
    export PATH="${lib.makeBinPath [pkgs.wireplumber pkgs.pipewire pkgs.jq pkgs.gawk pkgs.gnugrep pkgs.coreutils]}:$PATH"

    export TN_DIM=${theme.comment}
    export TN_GREEN=${theme.green}
    export TN_RED=${theme.red}

    ${builtins.readFile ./waybar-mic.sh}
  '';

  healthStatus = pkgs.writeShellScript "waybar-health" ''
    export PATH="${lib.makeBinPath [pkgs.jq pkgs.coreutils pkgs.xdg-utils]}:$PATH"
    ${builtins.readFile ./waybar-health.sh}
  '';

  weatherStatus = pkgs.writeShellScript "waybar-weather" ''
    exec ${pkgs.python3}/bin/python3 ${./waybar-weather.py} \
      --h24 \
      --color-alert ${lib.escapeShellArg theme.red} \
      --color-status ${lib.escapeShellArg theme.blue} \
      --color-temp-very-low ${lib.escapeShellArg theme.blue} \
      --color-temp-low ${lib.escapeShellArg theme.cyan} \
      --color-temp-normal ${lib.escapeShellArg theme.green} \
      --color-temp-high ${lib.escapeShellArg theme.orange} \
      --color-temp-very-high ${lib.escapeShellArg theme.red} \
      "$@"
  '';

  notch = cfg.waybar.notchWidth;
  hasNotch = notch > 0;

  # Tooltip bodies are Pango markup, NOT html: a small fixed tag set (b, i, u,
  # tt, small, big, s, sub, sup, span) with `span` taking Pango attributes such
  # as color/weight/size. There is no box model — no divs, no padding, no
  # alignment — so anything tabular has to be laid out with literal spaces and
  # lean on the monospace face the stylesheet gives tooltips.
  #
  # Pango parses the whole string, so a literal '<' or '&' arriving from a
  # substitution (an SSID, a hostname) makes the markup invalid and the tooltip
  # renders as raw text. Only apply markup where the interpolated values are
  # known-safe, or escape at the source.
  dim = s: "<span color='${theme.comment}'>${s}</span>";

  # Month grid for the clock tooltips. Waybar's own calendar formatter, so the
  # markup below is applied per-cell rather than to a pre-rendered block.
  calendar = {
    mode = "month";
    weeks-pos = "";
    on-scroll = 1;
    format = {
      months = "<span color='${theme.fg}'><b>{}</b></span>";
      days = "<span color='${theme.fgDark}'>{}</span>";
      weekdays = "<span color='${theme.yellow}'><b>{}</b></span>";
      today = "<span color='${theme.cyan}'><b><u>{}</u></b></span>";
    };
  };
in {
  options.programs.hyprland-desktop.waybar = {
    notchWidth = lib.mkOption {
      type = lib.types.int;
      default = 0;
      example = 227;
      description = ''
        Width in LOGICAL pixels of the display notch, or 0 for a panel without
        one (the default, so ordinary monitors are unaffected).

        When non-zero the clock is split in two and separated by a blank spacer
        of this width, giving `DATE  <notch>  TIME`, so content never sits
        behind the cutout.

        LOGICAL, so it depends on the monitor scale as well as the panel: the
        same cutout is 170 at scale 2 and 227 at scale 1.5. Re-measure it when
        the scale changes.

        Apple Silicon laptops only expose the notch row when the kernel is told
        to crop less than the full notch height (`appledrm.show_notch=1`, or
        `appledrm.notch_crop_rows=` with our patch). Without that the panel is
        cropped below the notch and this should stay 0.
      '';
    };

    notchHeight = lib.mkOption {
      type = lib.types.int;
      default = 0;
      example = 48;
      description = ''
        Height in LOGICAL pixels of the reclaimed notch row. The bar is grown
        to exactly this so the strip is all bar and no dead space.

        Also scale-dependent, and not derivable from notchWidth: it is the
        panel's notch height minus whatever the kernel crops, divided by the
        scale. 72 physical rows at scale 1.5 gives 48.

        Ignored unless notchWidth is set; the bar falls back to 30 otherwise.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && isLinux) {
    programs.waybar = {
      enable = true;

      # Hyprland launches Waybar itself so every bar is tied to exactly one
      # compositor instance and inherits that instance's WAYLAND_DISPLAY and
      # HYPRLAND_INSTANCE_SIGNATURE. A persistent systemd user unit can survive
      # `hyprctl dispatch exit`, restart while no display exists, and retain the
      # previous instance signature when the next session starts.
      systemd.enable = false;

      settings = [
        {
          layer = "top";
          position = "top";
          # Match the reclaimed strip exactly, so it is all bar rather than
          # part bar and part dead space.
          height =
            if hasNotch
            then cfg.waybar.notchHeight
            else 30;
          modules-left = ["hyprland/workspaces" "hyprland/window"];
          modules-center =
            if hasNotch
            then ["clock#date" "custom/notch" "clock#time"]
            else ["clock"];
          modules-right = ["custom/weather" "custom/tailscale" "pulseaudio" "custom/mic" "network" "custom/cpu" "memory" "battery" "custom/health" "custom/notification" "tray"];

          "custom/notification" = {
            tooltip = true;
            tooltip-format = "Notifications";
            format = "{icon}";
            format-icons = {
              notification = "󱅫";
              none = "󰂜";
              dnd-notification = "󰂠";
              dnd-none = "󰪓";
              inhibited-notification = "󰂛";
              inhibited-none = "󰪑";
              dnd-inhibited-notification = "󰂛";
              dnd-inhibited-none = "󰪑";
            };
            return-type = "json";
            exec = "${pkgs.swaynotificationcenter}/bin/swaync-client -swb";
            on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
            on-click-right = "${pkgs.swaynotificationcenter}/bin/swaync-client -d -sw";
            escape = true;
          };

          "custom/weather" = {
            format = "{}";
            return-type = "json";
            exec = "${weatherStatus}";
            interval = 600;
            tooltip = true;
            on-click = "${pkgs.xdg-utils}/bin/xdg-open 'https://radar.weather.gov/station/klot/standard'";
            on-click-right = "${pkgs.procps}/bin/pkill -RTMIN+9 waybar";
            signal = 9;
          };

          "hyprland/workspaces" = {
            format = "{icon}";
            on-click = "activate";
          };

          clock = {
            format = " {:%H:%M:%S}";
            format-alt = "{:%Y-%m-%d %H:%M:%S}";
            inherit calendar;
            tooltip-format = "<span color='${theme.blue}'><b>{:%A %d %B %Y}</b></span>\n<tt>{calendar}</tt>";
            # Seconds are pointless without a matching tick rate; waybar
            # defaults to 60s and the display would sit stale for a minute.
            interval = 1;
          };

          # Notch layout. The centre group is centred as a unit, so a spacer of
          # the notch's width between the two halves lands the cutout between
          # them: date to its left, time to its right. Keeping the two roughly
          # equal in width keeps the spacer centred on the screen.
          #
          # Two constraints on waybar's clock formatter, both established by
          # probing the binary rather than inferred:
          #
          #   1. Exactly one positional `{:...}` field. A second one is
          #      "invalid arg-id in format string" — the time arrives as a
          #      single argument and fmt's auto-indexing then runs off the end.
          #      Named fields ({calendar}, {tz_list}) are substituted before
          #      fmt runs, consume no index, and can be used freely.
          #   2. The spec must OPEN with a '%' code, or chrono rejects it with
          #      "no '%' at start of chrono-specs".
          #
          # Together those force the heading's <span><b> to open outside the
          # field and close inside it below, which looks unbalanced but is not:
          # Pango only ever sees the assembled string, where the tags pair up.
          # Everything after the first %-code is literal to chrono, so the week
          # line sits inside the same spec.
          "clock#date" = {
            inherit calendar;
            format = "{:%a %d %b}";
            tooltip-format = "<span color='${theme.blue}'><b>{:%A %d %B %Y</b></span>\n${dim "week   "} W%V, day %j}\n<tt>{calendar}</tt>";
          };

          "clock#time" = {
            format = " {:%H:%M:%S}";
            interval = 1;
            # Local time and nothing else, then the other zones. The date and
            # week live on the date half of the clock, next to the calendar
            # they belong with; repeating them here only made this tooltip
            # longer than the answer it exists to give.
            tooltip-format = "<span color='${theme.blue}'><b>{:%H:%M:%S %Z}</b></span>\n{tz_list}";

            # The leading "" is the local zone, and waybar always omits the
            # local zone from the list — no duplicate of the heading, and the
            # bar keeps showing local time.
            timezones = ["" "UTC" "Europe/London" "Europe/Amsterdam" "Asia/Singapore"];

            # One format for every zone, so the zones cannot be labelled
            # individually; %Z is what distinguishes them (UTC, BST, CEST,
            # +08). Same two constraints as the date tooltip above — one
            # positional field, opening with a %-code — hence the same
            # span-opened-outside shape. Abbreviation widths vary, so this column is slightly
            # ragged and there is no strftime padding to fix it with.
            timezone-tooltip-format = "<span color='${theme.comment}'>{:%Z</span>\t%H:%M  %a %d %b}";
          };

          # The label must not be empty. Waybar hides a custom module whose
          # output text is empty, and a hidden widget gets no width — the
          # min-width below silently does nothing and the two clock halves
          # close up in the middle of the bar, directly behind the cutout.
          # A single space is enough to keep the widget realised.
          "custom/notch" = {
            format = " ";
            tooltip = false;
          };

          # Replaces the built-in `cpu` module, which cannot render this: it
          # builds its tooltip internally with set_tooltip_text and honours no
          # tooltip-format, so per-core bars and markup are unreachable from
          # config. See waybar-cpu.sh.
          "custom/cpu" = {
            exec = "${cpuHeat}";
            return-type = "json";
            interval = 2;
            on-click = "${pkgs.kitty}/bin/kitty --class system-tui -e ${pkgs.btop}/bin/btop";
          };

          # Was nf-fa-database (U+F1C0): a stack of platters, which reads as
          # disk rather than RAM. nf-fa-memory (U+F538) would be the obvious
          # replacement but is genuinely absent from this MesloLGS patch
          # (`fc-list :charset=f538` finds nothing).
          #
          # U+EFC5 draws a DIMM stick. nf-md-memory (U+F035B) is also present
          # and also means RAM, but renders as a small square chip that reads
          # as a near-duplicate of the CPU microchip sitting next to it in the
          # bar -- the two are only a colour apart. The stick is unambiguous.
          # Thresholds drive the shared .warning/.critical classes; see the
          # colour policy in the stylesheet. Higher percentage is worse, so
          # these read as "at or above".
          memory = {
            states = {
              warning = 75;
              critical = 90;
            };
            format = "{:3}% ";
            # Plain text, no markup: waybar's memory module sets this with
            # set_tooltip_text (src/modules/memory/common.cpp), unlike network
            # and pulseaudio which use set_tooltip_markup. Tags here would be
            # shown literally. The column alignment still works, because the
            # monospace face comes from the stylesheet rather than from markup.
            tooltip-format = "Memory\nused   {used:.1f}G / {total:.1f}G  ({percentage}%)\nfree   {avail:.1f}G\nswap   {swapUsed:.1f}G / {swapTotal:.1f}G  ({swapState})";
            interval = 2;
          };

          # Signal strength inverts the usual sense: low is bad. waybar matches
          # "at or above" and takes the first hit scanning downwards, so the
          # bands need a 0 floor to catch weak signal at all -- without it a
          # 10% signal matches nothing and renders as if it were fine.
          network = {
            states = {
              good = 50;
              warning = 25;
              critical = 0;
            };
            format-wifi = "{signalStrength:3}% ";
            format-ethernet = "{ipaddr} ";
            format-disconnected = "Disconnected ";
            # Label column padded to a fixed width so the values line up. The
            # stylesheet gives tooltips the bar's monospace face specifically
            # so this works; in a proportional font it would come out ragged.
            #
            # {essid} is the one field here that carries arbitrary text from
            # the outside world, so it is deliberately left outside any markup
            # tag — an SSID containing '<' or '&' would otherwise make the
            # whole tooltip invalid and drop it back to raw text.
            tooltip-format-wifi = "<span color='${theme.blue}'><b>{essid}</b></span>\n${dim "signal "} {signalStrength}%  ({frequency} GHz)\n${dim "iface  "} {ifname}\n${dim "addr   "} {ipaddr}/{cidr}\n${dim "gateway"} {gwaddr}\n${dim "up     "} {bandwidthUpBits}\n${dim "down   "} {bandwidthDownBits}";
            tooltip-format-ethernet = "<span color='${theme.blue}'><b>{ifname}</b></span>\n${dim "addr   "} {ipaddr}/{cidr}\n${dim "gateway"} {gwaddr}\n${dim "up     "} {bandwidthUpBits}\n${dim "down   "} {bandwidthDownBits}";
            tooltip-format-disconnected = "<span color='${theme.red}'><b>No network</b></span>";
            # Throughput figures are deltas between polls; without an interval
            # they read zero forever.
            interval = 5;
            on-click = lib.getExe pkgs.networkmanager_dmenu;
            on-click-right = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
          };

          # Tailscale is invisible to the network module, which reports whatever
          # carries the default route -- that stays wifi/ethernet even with the
          # tailnet up. Separate indicator so "am I on the tailnet" is
          # answerable at a glance.
          "custom/tailscale" = {
            exec = "${tailscaleStatus}";
            return-type = "json";
            interval = 10;
            # Left click goes to the admin console, because the questions
            # this module raises -- who else is on the tailnet, what is
            # advertising routes, which key is about to expire -- are answered
            # there and not by the local daemon.
            on-click = "${pkgs.xdg-utils}/bin/xdg-open https://login.tailscale.com/admin/machines";

            # Right click keeps the local view. --hold, unlike the nmtui click
            # above: `tailscale status` prints and exits, so without it kitty
            # closes the instant it opens and the float rule turns that into a
            # window sliding up and dropping straight back down.
            on-click-right = "${pkgs.kitty}/bin/kitty --class network-tui --hold -e ${pkgs.tailscale}/bin/tailscale status";
          };

          # The NixOS daemon owns the checks and atomic state file. This module
          # only maps its worst status to the bar and independently rejects a
          # missing, malformed or stale snapshot.
          "custom/health" = {
            exec = "${healthStatus}";
            return-type = "json";
            interval = 15;
            on-click = "${healthStatus} --open";
          };

          # Speaker and microphone are two instances of the same module
          # rather than one, because waybar puts its state classes on the
          # WHOLE widget: with both in one module, muting the speaker applied
          # `muted` to the microphone half too and greyed out a live mic.
          # Split, each instance carries only its own state.
          pulseaudio = {
            format = "{volume:3}% {icon}";
            # Same shape as `format`, so muting cannot change the module's
            # width: "muted" is wider than "100%" and shoved the bar around.
            # The slashed glyph and the grey carry the state instead, and the
            # volume stays readable so you know what unmuting will give you.
            format-muted = "{volume:3}% 󰖁";
            format-icons = {default = ["" "" ""];};
            tooltip-format = "<span color='${theme.orange}'><b>{desc}</b></span>\n${dim "output "} {volume}%";
            on-click = "${pkgs.hyprpwcenter}/bin/hyprpwcenter";
            scroll-step = 5;
          };

          # The mic is deliberately in the bar and not only the tooltip: an
          # unnoticed hot mic is the failure that actually costs you, and a
          # glance has to answer it.
          #
          # A custom module rather than a second pulseaudio instance, because
          # pulseaudio only knows the mute state -- what you set -- and not
          # whether anything is actually capturing. PipeWire knows both, and
          # the combination is where the useful states are. See waybar-mic.sh.
          "custom/mic" = {
            exec = "${micStatus}";
            return-type = "json";
            interval = 2;
            on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
            on-click-right = "${pkgs.hyprpwcenter}/bin/hyprpwcenter";
          };

          # Laptop only; on a desktop `battery` renders nothing and is harmless.
          # Icons are FA4-era codepoints, which this MesloLGS patch carries
          # (the FA5 nf-fa-memory/network_wired glyphs are absent from it).
          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{capacity:3}% {icon}";
            format-charging = "{capacity:3}% ";
            format-plugged = "{capacity:3}% ";
            format-icons = ["" "" "" "" ""];
            interval = 30;
          };

          tray = {
            spacing = 10;
          };
        }
      ];

      style = ''
        * {
          font-family: "MesloLGS Nerd Font", "Font Awesome 6 Free";
          font-size: 13px;
        }

        window#waybar {
          background-color: ${theme.bg};
          /* The bar's resting colour, and the baseline the whole policy below
             is defined against. Cyan rather than the theme's plain foreground:
             it reads as deliberate at a glance without being loud, and every
             module inherits it, so "quiet" still looks like a choice. Tooltips
             keep the plain foreground -- they carry paragraphs, not glances. */
          color: ${theme.cyan};
          border-bottom: 2px solid ${theme.border};
        }

        /* COLOUR POLICY
           Colour is information, not decoration. Every module inherits the
           bar's foreground and stays that way while it has nothing to say;
           colour appears only when a value leaves its normal range or a state
           needs attention. A bar where everything is always coloured trains
           you to ignore all of it, and then the one readout that matters does
           not stand out.

           One scale, shared by everything that reports a magnitude, so the
           same colour means the same severity in every module:

             cyan      nothing to report
             yellow    getting close
             red       at the limit
             dim       inactive or off -- present but not participating

           `states` is waybar's own value-to-class mechanism: memory keys on
           used percentage, network on signal strength, battery on capacity
           (`lesser`, so its thresholds count down). Modules driven by our own
           scripts do not need it -- they emit colour directly, which is how
           the CPU readout gets a continuous gradient rather than steps. */
        #warning,
        .warning {
          color: ${theme.yellow};
        }

        #critical,
        .critical {
          color: ${theme.red};
        }

        /* Blank cutout the physical notch sits in. min-width is the whole
           mechanism -- an empty label with no width would collapse.

           The padding is not decoration: notchWidth is the cutout itself, so
           without it the date and time butt right up against the bezel. It is
           the same 0 10px every other module gets, which is what makes the gap
           read as deliberate spacing rather than text that ran out of room --
           and it keeps notchWidth meaning the physical cutout instead of
           quietly absorbing a margin. */
        #custom-notch {
          min-width: ${toString notch}px;
          padding: 0 10px;
          background: transparent;
        }

        #workspaces button {
          padding: 0 5px;
          color: ${theme.fgDark};
          background: transparent;
          border: none;
        }

        /* An exception to the policy, deliberately: which workspace you are on
           is not a severity, and the highlight is the only thing distinguishing
           it. */
        #workspaces button.active {
          color: ${theme.blue};
        }

        /* Every module in modules-right belongs in this list. Waybar gives a
           module no horizontal padding of its own, so one left out does not
           look under-padded -- it looks like the module beside it is
           overlapping it. */
        #clock, #custom-weather, #custom-health, #custom-tailscale, #custom-cpu, #memory, #network, #pulseaudio, #custom-mic, #battery, #custom-notification, #tray {
          padding: 0 10px;
        }

        /* The enlarged condition glyph visually fills the weather module's
           normal padding, so give the following Tailscale icon more air. */
        #custom-weather {
          margin-right: 6px;
        }

        /* Pango spans own the live weather colours. Dim the entire rendered
           label for cached data so those child colours fade together. */
        #custom-weather.stale {
          opacity: 0.55;
        }

        #custom-weather.error {
          color: ${theme.comment};
        }

        /* Ethernet has no signal strength, so it must not take a
           signal-derived severity. waybar reports signalStrength 0 on a wired
           link and still applies the `states` thresholds, so the 0 floor added
           to catch weak wifi was painting a perfectly healthy wired connection
           critical red.

           Scoped by state class rather than by dropping the floor, because the
           floor is what makes weak wifi visible at all. `#network.ethernet`
           outranks a bare `.critical` on specificity, so this holds wherever
           it sits in the file. Note the module only reports `ethernet` once it
           has an address -- a wired link without one is `linked`, which should
           still go loud. */
        #network.ethernet {
          color: ${theme.cyan};
        }

        /* Tailscale: connected is the expected state and says nothing. An exit
           node is worth flagging because it silently changes what every other
           network reading in this bar means. */
        #custom-tailscale.exitnode {
          color: ${theme.yellow};
        }

        #custom-health.warn {
          color: ${theme.yellow};
        }

        #custom-health.crit {
          color: ${theme.red};
        }

        #custom-health.unknown {
          color: ${theme.comment};
        }

        /* Deliberately stopped is "off", and dim says so. Logged out or
           tailscaled unreachable is not off -- it is a tailnet you believe you
           are on and are not, which is worth the same red as a failure
           anywhere else. The script distinguishes them; collapsing both into
           one class hid the difference that matters. */
        #custom-tailscale.stopped {
          color: ${theme.comment};
        }

        #custom-tailscale.error {
          color: ${theme.red};
        }

        /* Audio: speaker and microphone are a pair and read as one, so they
           share the default colour and diverge only on state. Muted greys out
           -- off, not wrong. */
        #pulseaudio.muted,
        #custom-mic.muted {
          color: ${theme.comment};
        }

        /* The exception worth colouring: something is listening. Not a
           severity but a privacy state, and the only one here you would want
           to catch out of the corner of your eye. */
        #custom-mic.capturing {
          color: ${theme.red};
        }

        /* Muted AND being recorded -- the "why can't they hear me" case. It
           flashes because it is neither safe nor exposed: something is
           recording you and getting silence, and you almost certainly did not
           mean that. */
        #custom-mic.muted-capturing {
          color: ${theme.red};
          animation: mic-alarm 1s steps(12) infinite alternate;
        }

        @keyframes mic-alarm {
          to {
            color: ${theme.comment};
          }
        }

        /* Tooltips are GTK3 toplevels, not part of the bar, so none of the
           rules above reach them -- unstyled they render in the ambient GTK
           theme and look nothing like the bar. `tooltip` is the GTK CSS node
           name; the inner `label` is what actually carries the text, so colour
           and padding have to go there rather than on the container.

           The `*` rule at the top of this sheet does reach them, which is why
           tooltip bodies come out in the same monospace face the bar uses --
           relied on by the tooltips that lay their contents out in columns. */
        tooltip {
          background: ${theme.bgDark};
          border: 1px solid ${theme.border};
          /* Matches decoration.rounding in hyprland.nix -- keep the two in step
             or popups read as belonging to a different desktop than windows. */
          border-radius: 2px;
        }

        tooltip label {
          color: ${theme.fg};
          padding: 6px 10px;
        }
      '';
    };
  };
}
