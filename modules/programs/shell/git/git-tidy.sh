# shellcheck shell=bash
# git-tidy — remove branches whose work is fully merged/pushed, and tidy worktrees.
#
# Two categories of "done" branch are cleaned up:
#   A. Local branches whose upstream is [gone] — the remote branch was deleted
#      (typically after a PR merge). These are deleted locally only; there is no
#      remote left to delete.
#   B. Local branches fully merged into the default branch that STILL have a live
#      origin/<branch> ref. These get the remote branch deleted AND the local one.
#
# Worktree hygiene: any worktree checked out to a to-be-removed branch is removed
# first (skipped with a warning if it has uncommitted changes), then stale
# worktree metadata is pruned.
#
# The current branch and the default branch are never touched. A plan is printed
# and confirmed interactively unless -y/--yes is given.
#
# Wired into the shell from git/default.nix (alias: gtidy).

set -euo pipefail

assume_yes=0
for arg in "$@"; do
  case "$arg" in
    -y | --yes) assume_yes=1 ;;
    -h | --help)
      cat <<'EOF'
Usage: git-tidy [-y|--yes]

Deletes local branches whose upstream is gone, deletes remote+local branches
that are fully merged into the default branch, removes their worktrees, and
prunes stale worktree metadata. Prints a plan and asks for confirmation unless
-y/--yes is given.
EOF
      exit 0
      ;;
    *)
      echo "git-tidy: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "git-tidy: not inside a git repository" >&2
  exit 1
fi

# Determine the default branch: prefer origin/HEAD, fall back to main/master.
default_branch=""
if ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
  default_branch="${ref#refs/remotes/origin/}"
fi
if [[ -z "$default_branch" ]]; then
  for b in main master; do
    if git show-ref --verify --quiet "refs/heads/$b"; then
      default_branch="$b"
      break
    fi
  done
fi

current_branch=$(git rev-parse --abbrev-ref HEAD)

echo "==> git fetch --all --prune"
git fetch --all --prune --quiet

# Category A: local branches whose upstream is gone.
gone_local=()
while IFS= read -r br; do
  [[ -z "$br" ]] && continue
  [[ "$br" == "$current_branch" || "$br" == "$default_branch" ]] && continue
  gone_local+=("$br")
done < <(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads |
  awk '$2 == "[gone]" { print $1 }')

# Category B: local branches merged into the default branch that still have a
# live origin/<branch> ref. Compare against origin/<default> when it exists so a
# stale local default doesn't hide merges.
merged_target=""
if [[ -n "$default_branch" ]]; then
  if git show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
    merged_target="origin/$default_branch"
  else
    merged_target="$default_branch"
  fi
fi

merged_remote=()
if [[ -n "$merged_target" ]]; then
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    [[ "$br" == "$current_branch" || "$br" == "$default_branch" ]] && continue
    # Skip ones already caught by category A.
    for g in "${gone_local[@]}"; do [[ "$g" == "$br" ]] && continue 2; done
    # Only if a live remote branch still exists to delete.
    git show-ref --verify --quiet "refs/remotes/origin/$br" || continue
    merged_remote+=("$br")
  done < <(git branch --merged "$merged_target" --format='%(refname:short)')
fi

if [[ ${#gone_local[@]} -eq 0 && ${#merged_remote[@]} -eq 0 ]]; then
  echo "==> Nothing to clean up. Pruning worktrees."
  git worktree prune --verbose
  exit 0
fi

# Map branch -> worktree path (for branches checked out in a linked worktree).
declare -A worktree_of
wt_path=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) wt_path="${line#worktree }" ;;
    "branch "*)
      br="${line#branch refs/heads/}"
      worktree_of["$br"]="$wt_path"
      ;;
  esac
done < <(git worktree list --porcelain)

main_worktree=$(git rev-parse --path-format=absolute --git-common-dir)
main_worktree=$(dirname "$main_worktree")

echo
echo "Plan:"
if [[ ${#gone_local[@]} -gt 0 ]]; then
  echo "  Delete local branches (upstream gone):"
  for br in "${gone_local[@]}"; do echo "    - $br"; done
fi
if [[ ${#merged_remote[@]} -gt 0 ]]; then
  echo "  Delete remote + local branches (merged into $default_branch):"
  for br in "${merged_remote[@]}"; do echo "    - $br  (origin/$br + local)"; done
fi

all_branches=("${gone_local[@]}" "${merged_remote[@]}")
wt_to_remove=()
for br in "${all_branches[@]}"; do
  wt="${worktree_of[$br]:-}"
  [[ -n "$wt" && "$wt" != "$main_worktree" ]] && wt_to_remove+=("$wt")
done
if [[ ${#wt_to_remove[@]} -gt 0 ]]; then
  echo "  Remove worktrees:"
  for wt in "${wt_to_remove[@]}"; do echo "    - $wt"; done
fi
echo

if [[ "$assume_yes" -ne 1 ]]; then
  read -r -p "Proceed? [y/N] " reply
  case "$reply" in
    [yY] | [yY][eE][sS]) ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
fi

# Remove worktrees first so their branches can be deleted.
for wt in "${wt_to_remove[@]}"; do
  if git worktree remove "$wt" 2>/dev/null; then
    echo "removed worktree: $wt"
  else
    echo "WARNING: worktree '$wt' has uncommitted changes or is locked; skipping (use 'gwr --force $wt')" >&2
  fi
done

# Delete remote branches for the merged category.
for br in "${merged_remote[@]}"; do
  git push origin --delete "$br" && echo "deleted remote: origin/$br"
done

# Delete local branches. -D is safe here: gone branches are merged upstream and
# merged branches are confirmed merged into the default branch.
for br in "${all_branches[@]}"; do
  git branch -D "$br" && echo "deleted local: $br"
done

echo "==> Pruning stale worktree metadata"
git worktree prune --verbose

echo "Done."
