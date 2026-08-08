# shellcheck shell=bash
# Waybar custom module: Tailscale state.
#
# Emits waybar's JSON object form so the icon, the hover text and the CSS class
# can all be driven from one poll. `class` is what the stylesheet colours on, so
# the bar shows connected/offline at a glance without reading the tooltip.
#
# Never exits non-zero: waybar renders a module that fails as empty, which is
# indistinguishable from "Tailscale is fine", so every failure path prints a
# deliberate offline state instead.
#
# The tooltip is Pango markup and the colours arrive as TN_* from the module
# that wraps this script, so the palette stays in one place.
#
# Two escaping rules hold this together:
#   - Pango attributes are quoted with 'single' quotes, never "double". The
#     tooltip is interpolated into the JSON below by hand, so a literal double
#     quote anywhere in it would terminate the JSON string early.
#   - Every value read out of `tailscale status` goes through jq's @html, which
#     escapes < > & ' " — an unlucky hostname would otherwise invalidate the
#     markup (Pango then renders the tooltip as raw tag soup) as well as the
#     JSON.

label() { printf "<span color='%s'>%s</span>" "$TN_DIM" "$1"; }

status=$(tailscale status --json 2>/dev/null) || {
  printf "{\"text\":\"\",\"tooltip\":\"<span color='%s'><b>Tailscale</b></span>\\\\ntailscaled not reachable\",\"class\":\"offline\"}\n" "$TN_RED"
  exit 0
}

field() { printf '%s' "$status" | jq -r "$1"; }

state=$(field '.BackendState // "Unknown" | @html')
self_ip=$(field '.TailscaleIPs[0] // empty | @html')
self_name=$(field '.Self.HostName // empty | @html')
tailnet=$(field '.CurrentTailnet.Name // empty | @html')

# An exit node routes ALL traffic, so surface it prominently — it changes what
# every other interface reading in this bar actually means.
exit_node=$(field '
  [.Peer // {} | .[] | select(.ExitNode == true) | .HostName] | first // empty | @html')

peers_online=$(field '
  [.Peer // {} | .[] | select(.Online == true)] | length')

heading() { printf "<span color='%s'><b>%s</b></span>" "$1" "$2"; }

case "$state" in
  Running)
    if [ "$exit_node" != "" ]; then
      text=" $exit_node"
      class="exitnode"
      tooltip=$(heading "$TN_YELLOW" 'Tailscale — via exit node')
    else
      text=""
      class="connected"
      tooltip=$(heading "$TN_GREEN" 'Tailscale — connected')
    fi

    [ "$self_name" != "" ] && tooltip="$tooltip\n$(label 'host   ') $self_name"
    [ "$self_ip" != "" ] && tooltip="$tooltip\n$(label 'addr   ') $self_ip"
    [ "$tailnet" != "" ] && tooltip="$tooltip\n$(label 'tailnet') $tailnet"
    [ "$exit_node" != "" ] && tooltip="$tooltip\n$(label 'exit   ') $exit_node"
    tooltip="$tooltip\n$(label 'peers  ') $peers_online online"
    ;;
  Stopped)
    text=""
    class="offline"
    tooltip=$(heading "$TN_RED" 'Tailscale — stopped')
    ;;
  NeedsLogin)
    text=""
    class="offline"
    tooltip="$(heading "$TN_RED" 'Tailscale — logged out')\n$(label 'fix    ') run tailscale up"
    ;;
  *)
    text=""
    class="offline"
    tooltip=$(heading "$TN_RED" "Tailscale — $state")
    ;;
esac

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
