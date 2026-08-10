#!/usr/bin/env bash

set -euo pipefail

case "${1:-}" in
  output)
    media_class="Audio/Sink"
    default_node="@DEFAULT_AUDIO_SINK@"
    prompt="Audio output"
    ;;
  input)
    media_class="Audio/Source"
    default_node="@DEFAULT_AUDIO_SOURCE@"
    prompt="Audio input"
    ;;
  *)
    printf 'usage: %s output|input\n' "${0##*/}" >&2
    exit 2
    ;;
esac

current_name=$(wpctl inspect "$default_node" 2>/dev/null |
  awk -F ' = ' '/node.name/ {gsub(/"/, "", $2); print $2; exit}')

mapfile -t nodes < <(
  pw-dump | jq -r --arg media_class "$media_class" '
    .[]
    | select(.type == "PipeWire:Interface:Node")
    | select(.info.props["media.class"] == $media_class)
    | [
        (.id | tostring),
        (.info.props["node.name"] // ""),
        (.info.props["node.description"]
          // .info.props["node.nick"]
          // .info.props["node.name"]
          // "Unknown device")
      ]
    | @tsv
  '
)

((${#nodes[@]})) || exit 0

ids=()
labels=()
for node in "${nodes[@]}"; do
  IFS=$'\t' read -r id name description <<<"$node"
  ids+=("$id")
  if [[ "$name" == "$current_name" ]]; then
    labels+=("● $description")
  else
    labels+=("  $description")
  fi
done

index=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "$prompt" -format i)
[[ "$index" =~ ^[0-9]+$ ]] || exit 0

wpctl set-default "${ids[index]}"
