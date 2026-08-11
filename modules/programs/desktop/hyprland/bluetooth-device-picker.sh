#!/usr/bin/env bash
set -euo pipefail

controller=$(bluetoothctl show)
powered=$(awk '/Powered:/ { print $2; exit }' <<<"$controller")
discoverable=$(awk '/Discoverable:/ { print $2; exit }' <<<"$controller")

labels=()
actions=()
addresses=()

if [[ "$powered" == "yes" ]]; then
  labels+=("󰂲  Turn Bluetooth off")
  actions+=(power-off)
else
  labels+=("  Turn Bluetooth on")
  actions+=(power-on)
fi
addresses+=("")

if [[ "$powered" == "yes" ]]; then
  if [[ "$discoverable" == "yes" ]]; then
    labels+=("󰂲  Stop discoverability")
    actions+=(discoverable-off)
  else
    labels+=("󰂰  Make discoverable")
    actions+=(discoverable-on)
  fi
  addresses+=("")
fi

labels+=("󰂰  Pair a new device…")
actions+=(manager)
addresses+=("")

if [[ "$powered" == "yes" ]]; then
  while read -r _ address name; do
    [[ -n "${address:-}" ]] || continue

    if bluetoothctl info "$address" | grep -q 'Connected: yes'; then
      labels+=("󰂱  $name")
      actions+=(disconnect)
    else
      labels+=("󰂯  $name")
      actions+=(connect)
    fi
    addresses+=("$address")
  done < <(bluetoothctl devices Paired)
fi

index=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p Bluetooth -format i)
[[ "$index" =~ ^[0-9]+$ ]] || exit 0

case "${actions[index]}" in
  power-on)
    gdbus call --session \
      --dest org.blueman.Applet \
      --object-path /org/blueman/Applet \
      --method org.blueman.Applet.SetBluetoothStatus true >/dev/null
    ;;
  power-off)
    gdbus call --session \
      --dest org.blueman.Applet \
      --object-path /org/blueman/Applet \
      --method org.blueman.Applet.SetBluetoothStatus false >/dev/null
    ;;
  discoverable-on)
    bluetoothctl discoverable on >/dev/null
    ;;
  discoverable-off)
    bluetoothctl discoverable off >/dev/null
    ;;
  manager)
    blueman-manager >/dev/null 2>&1 &
    ;;
  connect)
    timeout 15 bluetoothctl connect "${addresses[index]}" >/dev/null
    ;;
  disconnect)
    bluetoothctl disconnect "${addresses[index]}" >/dev/null
    ;;
esac
