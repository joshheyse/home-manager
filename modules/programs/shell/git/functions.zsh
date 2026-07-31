# Git-oriented shell functions. Sourced from ~/.zshrc via git/default.nix.

# gpt <tag> [message] — create an annotated tag (if missing) and push it.
function gpt() {
  tag=$1
  if [ -z "$tag" ]; then
    echo "Tag name is required"
    return 1
  fi
  message=$2
  ((git tag | grep $1) || git tag -a $1 -m "${message:-"tagging $1"}") && git push origin $1
}

# glm — compact git log for commits authored by the configured git identity.
function glm() {
  local author
  author=$(git config user.email)
  if [ -z "$author" ]; then
    author=$(git config user.name)
  fi

  if [ -z "$author" ]; then
    print -u2 "git user.email or user.name is required"
    return 1
  fi

  git log --oneline --decorate --date=relative --author="$author" "$@"
}

# groot — cd to the current repository root.
function groot() {
  local root
  root=$(git rev-parse --show-toplevel) || return
  cd "$root" || return
}

# _gw_sibling_path <branch> — path for a new worktree derived from a branch name:
# a sibling of the current worktree's top level, with slashes flattened to dashes.
# e.g. from ~/code/proj/main with branch feature/foo -> ~/code/proj/feature-foo
function _gw_sibling_path() {
  local branch="$1" top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { print -r -- "$branch"; return; }
  print -r -- "${top:h}/${branch//\//-}"
}

# gwa — git worktree add for an EXISTING branch.
#   gwa <folder> <branch>   explicit folder + branch
#   gwa <branch>            folder derived from the branch name (branch must exist)
function gwa() {
  if (( $# == 1 )); then
    git worktree add "$(_gw_sibling_path "$1")" "$1"
  elif (( $# == 2 )); then
    git worktree add "$1" "$2"
  else
    print -u2 "usage: gwa <folder> <branch>  |  gwa <existing-branch>"
    return 1
  fi
}

# gwan — git worktree add creating a NEW branch.
#   gwan <folder> <new-branch>   explicit folder + new branch
#   gwan <new-branch>           folder derived from the new branch name
function gwan() {
  if (( $# == 1 )); then
    git worktree add -b "$1" "$(_gw_sibling_path "$1")"
  elif (( $# == 2 )); then
    git worktree add "$1" -b "$2"
  else
    print -u2 "usage: gwan <folder> <new-branch>  |  gwan <new-branch>"
    return 1
  fi
}
