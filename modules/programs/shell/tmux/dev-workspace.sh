# shellcheck shell=bash
set -euo pipefail

DEV_ROOT="${TMUX_DEV_ROOT:-$HOME/code}"
HISTORY_DIR="$HOME/.local/state/tmux-dev-workspaces"
HISTORY_FILE="$HISTORY_DIR/history"

mkdir -p "$HISTORY_DIR"
touch "$HISTORY_FILE"

update_history() {
  local dir="$1"
  grep -vxF "$dir" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" || true
  { echo "$dir"; cat "$HISTORY_FILE.tmp"; } > "$HISTORY_FILE"
  rm -f "$HISTORY_FILE.tmp"
}

resolve_path() {
  local input="$1"
  if [[ "$input" = /* ]]; then
    echo "$input"
  elif [[ "$input" = */* ]]; then
    (cd "$DEV_ROOT" && cd "$input" && pwd)
  else
    echo "$DEV_ROOT/$input"
  fi
}

create_workspace() {
  local project_dir="$1"
  local allow_inplace="${2:-false}"
  local project_name window_name
  project_name=$(basename "$project_dir")
  window_name="dev: $project_name"

  # Check if workspace already exists
  local existing_window
  existing_window=$(tmux list-windows -F '#{window_index}:#{window_name}' 2>/dev/null \
    | grep -F "$window_name" \
    | head -1 \
    | cut -d: -f1) || true

  if [[ -n "$existing_window" ]]; then
    tmux select-window -t "$existing_window"
    return
  fi

  local inplace=false
  if [[ "$allow_inplace" == "true" ]]; then
    local pane_count
    pane_count=$(tmux list-panes 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$pane_count" -le 1 ]]; then
      inplace=true
    fi
  fi

  if [[ "$inplace" == "true" ]]; then
    tmux rename-window "$window_name"
  else
    tmux new-window -n "$window_name" -c "$project_dir" \
      "zsh -i -c 'eval \"\$(direnv export zsh 2>/dev/null)\" && nvim'"
  fi

  # Claude pane (right, 40% width, full height)
  tmux split-window -h -l 40% -c "$project_dir" \
    "zsh -i -c 'eval \"\$(direnv export zsh 2>/dev/null)\" && claude'"

  # Terminal pane (bottom-left, 30% height)
  tmux select-pane -t '{left}'
  tmux split-window -v -l 30% -c "$project_dir"

  # Focus nvim/main pane
  tmux select-pane -t '{top-left}'

  if [[ "$inplace" == "true" ]]; then
    # Signal to wrapper to exec nvim
    echo "$project_dir"
  fi
}

if [[ "${1:-}" == "--pick" ]]; then
  shift

  build_list() {
    local -A seen

    while IFS= read -r dir; do
      if [[ -n "$dir" && -d "$dir" ]]; then
        local name
        name=$(basename "$dir")
        if tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qF "dev: $name"; then
          echo "* $dir"
        else
          echo "  $dir"
        fi
        seen["$dir"]=1
      fi
    done < "$HISTORY_FILE"

    if [[ -d "$DEV_ROOT" ]]; then
      for dir in "$DEV_ROOT"/*/; do
        dir="${dir%/}"
        if [[ -d "$dir" && -z "${seen[$dir]:-}" ]]; then
          local name
          name=$(basename "$dir")
          if tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qF "dev: $name"; then
            echo "* $dir"
          else
            echo "  $dir"
          fi
        fi
      done
    fi
  }

  # shellcheck disable=SC2016 # fzf --preview uses single quotes intentionally
  selection=$(build_list | fzf \
    --prompt="Dev Workspace: " \
    --header="Select project (* = open) or type path" \
    --height=100% \
    --reverse \
    --border \
    --print-query \
    --bind="enter:accept-or-print-query" \
    --nth=2 \
    --with-nth=1,2 \
    --preview='dir=$(echo {} | sed "s/^[* ] //"); echo "Project: $(basename "$dir")"; echo "Path: $dir"; echo; if [[ -f "$dir/README.md" ]]; then head -20 "$dir/README.md"; elif [[ -f "$dir/README" ]]; then head -20 "$dir/README"; else ls -la "$dir" 2>/dev/null | head -20; fi' \
    --preview-window="right:50%" \
    "$@" | tail -1)

  selection="${selection#[*\ ] }"

  if [[ -z "$selection" ]]; then
    exit 0
  fi

  project_dir=$(resolve_path "$selection")

  if [[ ! -d "$project_dir" ]]; then
    echo "Directory does not exist: $project_dir" >&2
    exit 1
  fi

  update_history "$project_dir"
  create_workspace "$project_dir" false
else
  input="${1:-$(pwd)}"
  project_dir=$(resolve_path "$input")

  if [[ ! -d "$project_dir" ]]; then
    echo "Directory does not exist: $project_dir" >&2
    exit 1
  fi

  update_history "$project_dir"
  create_workspace "$project_dir" true
fi
