#!/usr/bin/env bash
# Refresh the bazel target cache for the workspace containing $PWD.
# Usage: bazel-refresh-targets [--background] [workspace_root]

set -u

log() { printf '%s\n' "$*" >&2; }

find_workspace_root() {
    local dir="${1:-$PWD}"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/MODULE.bazel" || -f "$dir/WORKSPACE" || -f "$dir/WORKSPACE.bazel" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

cache_dir_for() {
    local workspace="$1"
    local hash
    hash=$(printf '%s' "$workspace" | shasum -a 256 | cut -c1-16)
    printf '%s/bazel-completion/%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}" "$hash"
}

background=0
if [[ "${1:-}" == "--background" ]]; then
    background=1
    shift
fi

workspace="${1:-}"
if [[ -z "$workspace" ]]; then
    workspace=$(find_workspace_root) || {
        log "bazel-refresh-targets: not inside a bazel workspace"
        exit 1
    }
fi

cache=$(cache_dir_for "$workspace")
mkdir -p "$cache"
targets_file="$cache/targets"
lock_file="$cache/refresh.lock"
workspace_file="$cache/workspace"

printf '%s\n' "$workspace" >"$workspace_file"

run_refresh() {
    # Atomically replace the cache so readers never see a partial file.
    local tmp
    tmp=$(mktemp "$targets_file.XXXXXX")
    if (cd "$workspace" && bazelisk query --output=label '//...' 2>/dev/null) >"$tmp"; then
        mv "$tmp" "$targets_file"
    else
        rm -f "$tmp"
        log "bazel-refresh-targets: query failed in $workspace"
        return 1
    fi
}

acquire_lock() {
    # mkdir is atomic; use it as a mutex so concurrent completions don't pile up queries.
    if ! mkdir "$lock_file" 2>/dev/null; then
        return 1
    fi
    trap 'rmdir "$lock_file" 2>/dev/null || true' EXIT
    return 0
}

if (( background )); then
    (
        acquire_lock || exit 0
        run_refresh
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    exit 0
fi

acquire_lock || {
    log "bazel-refresh-targets: another refresh is in progress"
    exit 0
}
run_refresh
