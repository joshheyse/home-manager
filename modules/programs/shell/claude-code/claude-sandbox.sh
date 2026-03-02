#!/usr/bin/env bash
# claude-sandbox: Run Claude Code inside a Landlock sandbox
# Restricts filesystem access and network connections at the kernel level

set -euo pipefail

# Check that Landlock LSM is active
if [[ ! -f /sys/kernel/security/lsm ]] || ! grep -q landlock /sys/kernel/security/lsm; then
  echo "WARNING: Landlock LSM is not active on this kernel. Running without sandbox." >&2
  exec claude --dangerously-skip-permissions "$@"
fi

# Build landrun arguments
args=()

# Writable paths
args+=(--rw "$PWD")
args+=(--rw "$HOME/.claude")
args+=(--rw /tmp)

# Read-only + execute paths (binaries/packages)
args+=(--rox /nix/store)

# Read-only paths
args+=(--ro "$HOME")
args+=(--ro /proc)
args+=(--ro /dev)
args+=(--ro /sys)
args+=(--ro /etc)
args+=(--ro /run)
args+=(--ro /usr)
args+=(--ro /lib)
args+=(--ro /lib64)
args+=(--ro /bin)

# Network: allow only outbound HTTPS, HTTP, and SSH
args+=(--connect-tcp "443,80,22")

# Pass all current environment variables through
while IFS='=' read -r name _; do
  args+=(--env "${name}=${!name}")
done < <(env)

exec landrun "${args[@]}" -- claude --dangerously-skip-permissions "$@"
