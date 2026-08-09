# shellcheck shell=bash
set -euo pipefail

MODE="${1:-}"
PATH_ARG="${2:-}"

strip_ansi() {
  sed $'s/\033\\[[0-9;]*m//g' | tr -d '\n'
}

render_module() {
  local module="$1"
  local color="$2"
  local output

  output=$(starship module "$module" --path "$PATH_ARG" --logical-path "$LOGICAL_PATH" | strip_ansi)
  if [[ -z "$output" ]]; then
    return 0
  fi
  # The command output is evaluated as part of tmux's status format. Escape
  # user-controlled path, branch, and status text so `#` cannot introduce a
  # tmux format expansion or style directive.
  output="${output//#/##}"

  if [[ "$WROTE_MODULE" == "true" ]]; then
    printf '  '
  fi
  printf '#[fg=%s]%s' "$color" "$output"
  WROTE_MODULE=true
}

render_modules() {
  WROTE_MODULE=false
  render_module directory "$DEV_STATUS_BLUE"
  render_module git_branch "$DEV_STATUS_BLUE1"
  render_module git_state "$DEV_STATUS_ORANGE"
  render_module git_status "$DEV_STATUS_YELLOW"
  render_module nix_shell "$DEV_STATUS_BLUE5"
  render_module direnv "$DEV_STATUS_CYAN"
}

if [[ "$MODE" == "--render" ]]; then
  LOGICAL_PATH="$PATH_ARG"
  if [[ "$PATH_ARG" == "$HOME" ]]; then
    LOGICAL_PATH="~"
  elif [[ "$PATH_ARG" == "$HOME/"* ]]; then
    LOGICAL_PATH="~"
    LOGICAL_PATH+="/${PATH_ARG#"$HOME/"}"
  fi
  render_modules
  exit 0
fi

PATH_ARG="$MODE"
[[ -d "$PATH_ARG" ]] || exit 0

# Render once inside the same direnv/Nix environment as the workspace. This
# makes Starship's direnv and nix_shell modules accurate without teaching tmux
# how either environment works. Fall back cleanly for denied/broken .envrc files.
if [[ -f "$PATH_ARG/.envrc" ]] && direnv exec "$PATH_ARG" "$0" --render "$PATH_ARG" 2>/dev/null; then
  exit 0
fi

"$0" --render "$PATH_ARG"
