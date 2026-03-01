# shellcheck shell=bash
# PANE_ICON is injected by the Nix wrapper (default.nix)
# shellcheck disable=SC2154
set -euo pipefail

DEV_ROOT="${TMUX_DEV_ROOT:-$HOME/code}"
HISTORY_DIR="$HOME/.local/state/tmux-dev-workspaces"
HISTORY_FILE="$HISTORY_DIR/history"

mkdir -p "$HISTORY_DIR"
touch "$HISTORY_FILE"

# --- History ---

update_history() {
  local entry="$1"
  grep -vxF "$entry" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" || true
  { echo "$entry"; cat "$HISTORY_FILE.tmp"; } > "$HISTORY_FILE"
  rm -f "$HISTORY_FILE.tmp"
}

# --- Helpers ---

# Check if a dev window with the given name is already open (exact match)
is_window_open() {
  local wname="$1"
  tmux list-windows -F "#{@window_type}	#{window_name}" 2>/dev/null \
    | grep -qxF "dev	$wname"
}

# Get the window index for an open dev window (exact match)
get_window_index() {
  local wname="$1"
  tmux list-windows -F "#{window_index}	#{@window_type}	#{window_name}" 2>/dev/null \
    | awk -F'\t' -v name="$wname" '$2 == "dev" && $3 == name { print $1; exit }'
}

# Parse "project:branch" spec. Only split on : for bare names (no slashes).
# Sets globals PARSED_PROJECT and PARSED_BRANCH.
parse_project_spec() {
  local spec="$1"
  PARSED_PROJECT=""
  PARSED_BRANCH=""

  if [[ "$spec" == */* ]]; then
    # Contains slash — treat as path, no branch splitting
    PARSED_PROJECT="$spec"
  elif [[ "$spec" == *:* ]]; then
    PARSED_PROJECT="${spec%%:*}"
    PARSED_BRANCH="${spec#*:}"
  else
    PARSED_PROJECT="$spec"
  fi
}

# Check if a directory is a worktree-style project (subdirs have .git, root does not)
is_worktree_project() {
  local dir="$1"
  [[ ! -e "$dir/.git" ]] || return 1
  local subdir
  for subdir in "$dir"/*/; do
    subdir="${subdir%/}"
    [[ -e "$subdir/.git" ]] && return 0
  done
  return 1
}

# Find the original checkout (the subdir where .git is a directory, not a file).
# Worktrees have .git as a file; the original repo has .git as a directory.
get_default_worktree() {
  local dir="$1"
  local subdir
  # First pass: find original repo (.git is a directory)
  for subdir in "$dir"/*/; do
    subdir="${subdir%/}"
    [[ -d "$subdir/.git" ]] && { echo "$subdir"; return 0; }
  done
  # Fallback: first subdir with .git (file = worktree)
  for subdir in "$dir"/*/; do
    subdir="${subdir%/}"
    [[ -e "$subdir/.git" ]] && { echo "$subdir"; return 0; }
  done
  return 1
}

# Replace / with - for directory names (branch "feature/foo" -> dir "feature-foo")
sanitize_branch_dir() {
  local branch="$1"
  echo "${branch//\//-}"
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

# --- Worktree management ---

# Convert a simple git repo into a worktree-style layout.
# ~/code/project/ -> ~/code/project/<current-branch>/
upgrade_to_worktree() {
  local project_dir="$1"
  local project_name
  project_name=$(basename "$project_dir")

  # Refuse if a tmux window is open for this project (paths would go stale)
  if is_window_open "$project_name"; then
    echo "Error: close the '$project_name' dev workspace first (paths would break)" >&2
    return 1
  fi

  # Get current branch
  local current_branch
  current_branch=$(git -C "$project_dir" branch --show-current)
  if [[ -z "$current_branch" ]]; then
    echo "Error: cannot upgrade — HEAD is detached (need a branch name for subdirectory)" >&2
    return 1
  fi

  local branch_dir
  branch_dir=$(sanitize_branch_dir "$current_branch")

  # Use a temp dir on the same filesystem for atomic mv
  local tmpdir
  tmpdir=$(mktemp -d "${project_dir}.upgrade.XXXXXX")

  # Trap to restore on failure
  restore_on_failure() {
    if [[ -d "$tmpdir" ]]; then
      # Move contents back if they were moved to tmpdir
      if [[ -e "$tmpdir/.git" ]]; then
        rm -rf "$project_dir" 2>/dev/null || true
        mv "$tmpdir" "$project_dir"
      else
        rm -rf "$tmpdir"
      fi
    fi
  }
  trap restore_on_failure ERR

  # Move repo contents to temp
  mv "$project_dir" "$tmpdir"

  # Recreate project container and move repo into branch subdir
  mkdir -p "$project_dir"
  mv "$tmpdir" "$project_dir/$branch_dir"

  trap - ERR
  echo "Upgraded '$project_name' to worktree layout (default branch: $branch_dir)" >&2
}

# Ensure a worktree exists for the given branch, creating it if needed.
# Prints the worktree directory path.
ensure_worktree() {
  local project_dir="$1"
  local branch="$2"
  local branch_dir
  branch_dir=$(sanitize_branch_dir "$branch")

  local worktree_path="$project_dir/$branch_dir"

  # Already exists
  if [[ -d "$worktree_path" ]]; then
    echo "$worktree_path"
    return 0
  fi

  # Find the main worktree to run git commands against
  local main_worktree
  main_worktree=$(get_default_worktree "$project_dir")

  # Check if local branch exists
  if git -C "$main_worktree" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git -C "$main_worktree" worktree add "$worktree_path" "$branch" >&2
  # Check if remote branch exists (auto-tracks)
  elif git -C "$main_worktree" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
    git -C "$main_worktree" worktree add "$worktree_path" "$branch" >&2
  else
    # Create new branch
    git -C "$main_worktree" worktree add -b "$branch" "$worktree_path" >&2
  fi

  echo "$worktree_path"
}

# --- Workspace creation ---

create_workspace() {
  local project_dir="$1"
  local window_name="$2"
  local allow_inplace="${3:-false}"

  # Check if workspace already exists (exact match)
  local existing_window
  existing_window=$(get_window_index "$window_name")

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

  # Tag window as dev type for icon display and script queries
  "$PANE_ICON" set dev

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

# --- Resolve a spec (possibly with :branch) into project_dir and window_name ---
# Sets globals: RESOLVED_DIR, RESOLVED_WINDOW_NAME
resolve_spec() {
  local input="$1"
  local allow_upgrade="${2:-true}"

  parse_project_spec "$input"
  local project_path
  project_path=$(resolve_path "$PARSED_PROJECT")

  if [[ ! -d "$project_path" ]]; then
    echo "Directory does not exist: $project_path" >&2
    return 1
  fi

  local project_name
  project_name=$(basename "$project_path")

  if [[ -n "$PARSED_BRANCH" ]]; then
    # Branch specified — need worktree layout
    if [[ -e "$project_path/.git" ]] && [[ "$allow_upgrade" == "true" ]]; then
      # Simple project — upgrade to worktree layout
      upgrade_to_worktree "$project_path"
    elif [[ -e "$project_path/.git" ]]; then
      echo "Error: '$project_name' is not a worktree project (use direct mode to upgrade)" >&2
      return 1
    fi
    RESOLVED_DIR=$(ensure_worktree "$project_path" "$PARSED_BRANCH")
    RESOLVED_WINDOW_NAME="$project_name:$PARSED_BRANCH"
  elif is_worktree_project "$project_path"; then
    # Worktree project without branch — open default
    RESOLVED_DIR=$(get_default_worktree "$project_path")
    RESOLVED_WINDOW_NAME="$project_name"
  else
    # Simple project
    RESOLVED_DIR="$project_path"
    RESOLVED_WINDOW_NAME="$project_name"
  fi
}

# --- Main ---

if [[ "${1:-}" == "--pick" ]]; then
  shift

  build_list() {
    local -A seen

    # Helper: emit list entry for a path with appropriate open marker
    emit_entry() {
      local display_name="$1" wname="$2"
      if is_window_open "$wname"; then
        echo "* $display_name"
      else
        echo "  $display_name"
      fi
    }

    # Process history entries
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue

      # History entries may be "path:branch" for worktree entries
      if [[ "$entry" == *:* ]]; then
        local hist_path="${entry%%:*}"
        local hist_branch="${entry#*:}"
        local hist_dir
        hist_dir="$hist_path/$(sanitize_branch_dir "$hist_branch")"
        if [[ -d "$hist_dir" ]]; then
          local hist_project
          hist_project=$(basename "$hist_path")
          emit_entry "$hist_path:$hist_branch" "$hist_project:$hist_branch"
          seen["$entry"]=1
        fi
      elif [[ -d "$entry" ]]; then
        if is_worktree_project "$entry"; then
          # Show each worktree subdir
          local subdir
          for subdir in "$entry"/*/; do
            subdir="${subdir%/}"
            [[ -e "$subdir/.git" ]] || continue
            local sub_name wt_branch
            sub_name=$(basename "$entry")
            wt_branch=$(basename "$subdir")
            emit_entry "$entry:$wt_branch" "$sub_name:$wt_branch"
            seen["$entry:$wt_branch"]=1
          done
        else
          local name
          name=$(basename "$entry")
          emit_entry "$entry" "$name"
        fi
        seen["$entry"]=1
      fi
    done < "$HISTORY_FILE"

    # Scan DEV_ROOT for projects not yet in history
    if [[ -d "$DEV_ROOT" ]]; then
      for dir in "$DEV_ROOT"/*/; do
        dir="${dir%/}"
        [[ -d "$dir" ]] || continue
        if is_worktree_project "$dir"; then
          local subdir
          for subdir in "$dir"/*/; do
            subdir="${subdir%/}"
            [[ -e "$subdir/.git" ]] || continue
            local proj_name wt_branch entry_key
            proj_name=$(basename "$dir")
            wt_branch=$(basename "$subdir")
            entry_key="$dir:$wt_branch"
            if [[ -z "${seen[$entry_key]:-}" ]]; then
              emit_entry "$dir:$wt_branch" "$proj_name:$wt_branch"
            fi
          done
        else
          if [[ -z "${seen[$dir]:-}" ]]; then
            local name
            name=$(basename "$dir")
            emit_entry "$dir" "$name"
          fi
        fi
      done
    fi
  }

  # shellcheck disable=SC2016 # fzf --preview uses single quotes intentionally
  selection=$(build_list | fzf \
    --prompt="Dev Workspace: " \
    --header="Select project (* = open) or type name[:branch]" \
    --height=100% \
    --reverse \
    --border \
    --print-query \
    --bind="enter:accept-or-print-query" \
    --nth=2 \
    --with-nth=1,2 \
    --preview='entry=$(echo {} | sed "s/^[* ] //"); if [[ "$entry" == *:* ]]; then path="${entry%%:*}"; branch="${entry#*:}"; bdir=$(echo "$branch" | tr "/" "-"); dir="$path/$bdir"; else dir="$entry"; fi; echo "Project: $(basename "$dir")"; echo "Path: $dir"; echo; if [[ -f "$dir/README.md" ]]; then head -20 "$dir/README.md"; elif [[ -f "$dir/README" ]]; then head -20 "$dir/README"; else ls -la "$dir" 2>/dev/null | head -20; fi' \
    --preview-window="right:50%" \
    "$@" | tail -1)

  selection="${selection#[*\ ] }"

  if [[ -z "$selection" ]]; then
    exit 0
  fi

  # Handle fzf selection: could be "path:branch" or plain path
  if [[ "$selection" == /* ]] || [[ "$selection" == "$DEV_ROOT"/* ]]; then
    # Absolute path or DEV_ROOT path — might be "path:branch"
    if [[ "$selection" == *:* ]]; then
      sel_path="${selection%%:*}"
      sel_branch="${selection#*:}"
      if [[ -d "$sel_path" ]]; then
        resolve_spec "$(basename "$sel_path"):$sel_branch" false
        update_history "$selection"
        create_workspace "$RESOLVED_DIR" "$RESOLVED_WINDOW_NAME" false
        exit 0
      fi
    fi
    # Plain absolute path
    if [[ -d "$selection" ]]; then
      resolve_spec "$selection" false
      update_history "$selection"
      create_workspace "$RESOLVED_DIR" "$RESOLVED_WINDOW_NAME" false
      exit 0
    fi
  fi

  # Bare name or name:branch — resolve via spec
  resolve_spec "$selection" false

  update_history "$selection"
  create_workspace "$RESOLVED_DIR" "$RESOLVED_WINDOW_NAME" false
else
  input="${1:-$(pwd)}"

  resolve_spec "$input" true

  # Build history entry
  history_entry="$input"
  if [[ -n "$PARSED_BRANCH" ]]; then
    parse_project_spec "$input"
    proj_path=$(resolve_path "$PARSED_PROJECT")
    history_entry="$proj_path:$PARSED_BRANCH"
  elif [[ "$RESOLVED_DIR" != "$(resolve_path "$PARSED_PROJECT")" ]]; then
    # Worktree project opened by default — store the base path
    history_entry="$RESOLVED_DIR"
  fi

  update_history "$history_entry"
  create_workspace "$RESOLVED_DIR" "$RESOLVED_WINDOW_NAME" true
fi
