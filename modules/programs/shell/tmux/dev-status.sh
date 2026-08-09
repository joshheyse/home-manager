# shellcheck shell=bash
set -euo pipefail

MODE="${1:-}"
PATH_ARG="${2:-}"

render_modules() {
  local module
  for module in directory git_branch git_state git_status nix_shell direnv; do
    starship module "$module" --path "$PATH_ARG" --logical-path "$PATH_ARG"
  done
}

if [[ "$MODE" == "--render" ]]; then
  # Starship emits terminal ANSI styling even with NO_COLOR. Tmux status lines
  # use their own style language, so preserve Starship's symbols/text while
  # removing only its terminal control sequences and embedded newlines.
  render_modules \
    | sed $'s/\033\\[[0-9;]*m//g' \
    | tr -d '\n'
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
