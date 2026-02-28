# shellcheck shell=bash
# Fixed-width network speed widget for tmux status bar.
# Replaces the tokyo-night theme's variable-width netspeed display.

set -euo pipefail

# Check if enabled
ENABLED=$(tmux show-option -gv @tokyo-night-tmux_show_netspeed 2>/dev/null)
[[ ${ENABLED:-0} -ne 1 ]] && exit 0

# Tokyo Night "night" theme colors
FG="#a9b1d6"
RED="#f7768e"
BBLUE="#7aa2f7"
BGREEN="#41a6b5"
RESET="#[fg=${FG},bg=default,nobold,noitalics,nounderscore,nodim]"

# Nerd Font icons
ICON_RX="#[fg=${BGREEN}]$(printf '\U000f06f4')"  # nf-md-download_network
ICON_TX="#[fg=${BBLUE}]$(printf '\U000f06f6')"    # nf-md-upload_network
# shellcheck disable=SC2034 # used via indirect expansion: ${!IFACE_ICON_VAR}
ICON_WIFI_UP="#[fg=${FG}]$(printf '\U000f05a9')"   # nf-md-wifi
# shellcheck disable=SC2034
ICON_WIFI_DN="#[fg=${RED}]$(printf '\U000f05aa')"  # nf-md-wifi_off
# shellcheck disable=SC2034
ICON_WIRE_UP="#[fg=${FG}]$(printf '\U000f0318')"   # nf-md-lan_connect
# shellcheck disable=SC2034
ICON_WIRE_DN="#[fg=${RED}]$(printf '\U000f0319')"  # nf-md-lan_disconnect
ICON_IP="#[fg=${FG}]$(printf '\U000f0a5f')"        # nf-md-ip

SHOW_IP=$(tmux show-option -gv @tokyo-night-tmux_netspeed_showip 2>/dev/null || echo 0)
TIME_DIFF=$(tmux show-option -gv @tokyo-night-tmux_netspeed_refresh 2>/dev/null || echo 1)
TIME_DIFF=${TIME_DIFF:-1}

# --- Detect interface ---
INTERFACE=$(tmux show-option -gv @tokyo-night-tmux_netspeed_iface 2>/dev/null || true)
if [[ -z "$INTERFACE" ]]; then
  if [[ $(uname) == "Darwin" ]]; then
    INTERFACE=$(route get default 2>/dev/null | awk '/interface/{print $2}')
    [[ ${INTERFACE:0:4} == "utun" ]] && INTERFACE="en0"
  else
    INTERFACE=$(awk '$2 == 00000000 {print $1}' /proc/net/route 2>/dev/null)
  fi
  [[ -z "$INTERFACE" ]] && exit 1
  tmux set-option -g @tokyo-night-tmux_netspeed_iface "$INTERFACE"
fi

# --- Read bytes ---
get_bytes() {
  if [[ $(uname) == "Darwin" ]]; then
    netstat -ib | awk -v iface="$1" '$1 == iface {print $7, $10; exit}'
  else
    awk -v iface="$1" '$1 == iface ":" {print $2, $10}' /proc/net/dev
  fi
}

# --- Fixed-width speed format (8 chars: "999.9U/s" padded) ---
fmt_speed() {
  local bytes="$1" secs="$2"
  if [[ $bytes -lt 1048576 ]]; then
    printf '%5.1fK/s' "$(bc -l <<< "scale=1; $bytes / 1024 / $secs")"
  else
    printf '%5.1fM/s' "$(bc -l <<< "scale=1; $bytes / 1048576 / $secs")"
  fi
}

# --- Measure speed ---
read -r RX1 TX1 <<< "$(get_bytes "$INTERFACE")"
sleep "$TIME_DIFF"
read -r RX2 TX2 <<< "$(get_bytes "$INTERFACE")"

RX_SPEED=$(fmt_speed $((RX2 - RX1)) "$TIME_DIFF")
TX_SPEED=$(fmt_speed $((TX2 - TX1)) "$TIME_DIFF")

# --- Interface icon ---
if [[ $INTERFACE == "en0" ]] || [[ -d "/sys/class/net/${INTERFACE}/wireless" ]]; then
  IFACE_TYPE="wifi"
else
  IFACE_TYPE="wired"
fi

if [[ $(uname) == "Darwin" ]]; then
  IPV4=$(ipconfig getifaddr "$INTERFACE" 2>/dev/null || true)
else
  IPV4=$(ip -4 addr show "$INTERFACE" 2>/dev/null | awk '/inet /{sub("/.*","",$2); print $2}')
fi

if [[ -n "${IPV4:-}" ]]; then
  IFACE_ICON_VAR="ICON_${IFACE_TYPE^^}_UP"
else
  IFACE_ICON_VAR="ICON_${IFACE_TYPE^^}_DN"
fi
IFACE_ICON="${!IFACE_ICON_VAR}"

# --- Output ---
OUTPUT="${RESET}░ ${ICON_RX} #[fg=${FG}]${RX_SPEED} ${ICON_TX} #[fg=${FG}]${TX_SPEED} ${IFACE_ICON} #[dim]${INTERFACE} "
if [[ ${SHOW_IP:-0} -ne 0 ]] && [[ -n "${IPV4:-}" ]]; then
  OUTPUT+="${ICON_IP} #[dim]${IPV4} "
fi

echo -e "$OUTPUT"
