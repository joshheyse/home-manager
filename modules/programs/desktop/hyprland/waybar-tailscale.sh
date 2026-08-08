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

status=$(tailscale status --json 2>/dev/null) || {
  printf '{"text":"","tooltip":"Tailscale: tailscaled not reachable","class":"offline"}\n'
  exit 0
}

state=$(printf '%s' "$status" | jq -r '.BackendState // "Unknown"')
self_ip=$(printf '%s' "$status" | jq -r '.TailscaleIPs[0] // empty')
self_name=$(printf '%s' "$status" | jq -r '.Self.HostName // empty')
tailnet=$(printf '%s' "$status" | jq -r '.CurrentTailnet.Name // empty')

# An exit node routes ALL traffic, so surface it prominently — it changes what
# every other interface reading in this bar actually means.
exit_node=$(printf '%s' "$status" | jq -r '
  [.Peer // {} | .[] | select(.ExitNode == true) | .HostName] | first // empty')

peers_online=$(printf '%s' "$status" | jq -r '
  [.Peer // {} | .[] | select(.Online == true)] | length')

case "$state" in
  Running)
    if [ "$exit_node" != "" ]; then
      text=" $exit_node"
      class="exitnode"
    else
      text=""
      class="connected"
    fi
    tooltip="Tailscale: connected"
    [ "$self_name" != "" ] && tooltip="$tooltip\n$self_name"
    [ "$self_ip" != "" ] && tooltip="$tooltip ($self_ip)"
    [ "$tailnet" != "" ] && tooltip="$tooltip\ntailnet: $tailnet"
    [ "$exit_node" != "" ] && tooltip="$tooltip\nexit node: $exit_node"
    tooltip="$tooltip\npeers online: $peers_online"
    ;;
  Stopped)
    text=""
    class="offline"
    tooltip="Tailscale: stopped"
    ;;
  NeedsLogin)
    text=""
    class="offline"
    tooltip="Tailscale: logged out — run 'tailscale up'"
    ;;
  *)
    text=""
    class="offline"
    tooltip="Tailscale: $state"
    ;;
esac

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
