#!/usr/bin/env bash
# agent-check — Diagnose and optionally fix GPG/SSH agent status
# Usage: agent-check [--local|--remote|--fix]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${BLUE}·${NC} $1"; }
header() { echo -e "\n${BOLD}$1${NC}"; }

MODE=""
FIX=false
ERRORS=0

for arg in "$@"; do
  case "$arg" in
    --local) MODE="local" ;;
    --remote) MODE="remote" ;;
    --fix) FIX=true ;;
    --help|-h)
      echo "Usage: agent-check [--local|--remote] [--fix]"
      echo ""
      echo "  --local   Assert local mode (YubiKey plugged in)"
      echo "  --remote  Assert remote mode (SSH with GPG forwarding)"
      echo "  --fix     Attempt to fix issues automatically"
      echo ""
      echo "  If no mode is given, auto-detects based on SSH_CONNECTION."
      exit 0
      ;;
  esac
done

# Auto-detect mode
if [[ -z "$MODE" ]]; then
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    MODE="remote"
  else
    MODE="local"
  fi
fi

header "Environment (mode: ${MODE})"
info "SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-<unset>}"
info "SSH_CONNECTION=${SSH_CONNECTION:-<unset>}"
info "GPG_AGENT_INFO=${GPG_AGENT_INFO:-<unset> (expected, deprecated)}"

# --- SSH Agent ---
header "SSH Agent"

SWITCHER_SOCK="/tmp/ssh-agent.${USER}"
if [[ "${SSH_AUTH_SOCK:-}" == "$SWITCHER_SOCK" ]]; then
  pass "SSH_AUTH_SOCK points to ssh-agent-switcher ($SWITCHER_SOCK)"
else
  warn "SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-<unset>} (expected $SWITCHER_SOCK)"
fi

if [[ -S "$SWITCHER_SOCK" ]]; then
  pass "Switcher socket exists"
else
  fail "Switcher socket missing: $SWITCHER_SOCK"
  ERRORS=$((ERRORS + 1))
  if $FIX; then
    warn "Restarting ssh-agent-switcher..."
    systemctl --user restart ssh-agent-switcher 2>/dev/null || fail "Could not restart ssh-agent-switcher"
  fi
fi

if systemctl --user is-active ssh-agent-switcher >/dev/null 2>&1; then
  pass "ssh-agent-switcher service is running"
else
  fail "ssh-agent-switcher service is not running"
  ERRORS=$((ERRORS + 1))
  if $FIX; then
    warn "Starting ssh-agent-switcher..."
    systemctl --user start ssh-agent-switcher 2>/dev/null || fail "Could not start ssh-agent-switcher"
  fi
fi

# Test SSH agent connectivity
SSH_KEYS=$(ssh-add -l 2>&1) || true
if [[ "$SSH_KEYS" == *"agent has no identities"* ]]; then
  warn "SSH agent has no identities loaded"
elif [[ "$SSH_KEYS" == *"Could not open"* || "$SSH_KEYS" == *"Error connecting"* ]]; then
  fail "Cannot connect to SSH agent"
  ERRORS=$((ERRORS + 1))
else
  KEY_COUNT=$(echo "$SSH_KEYS" | wc -l)
  pass "SSH agent has $KEY_COUNT key(s) loaded"
  echo "$SSH_KEYS" | while IFS= read -r line; do
    info "$line"
  done
fi

# Test GitHub SSH
header "GitHub SSH"
GH_RESULT=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1) || true
if [[ "$GH_RESULT" == *"successfully authenticated"* ]]; then
  pass "GitHub SSH authentication works"
  info "$GH_RESULT"
elif [[ "$GH_RESULT" == *"Permission denied"* ]]; then
  fail "GitHub SSH authentication failed"
  ERRORS=$((ERRORS + 1))
elif [[ "$GH_RESULT" == *"Connection"* || "$GH_RESULT" == *"resolve"* ]]; then
  warn "Cannot reach GitHub (network issue)"
else
  warn "Unexpected response: $GH_RESULT"
fi

# --- GPG Agent ---
header "GPG Agent"

GPG_SOCKET="$(gpgconf --list-dirs agent-socket 2>/dev/null || echo '<unknown>')"
GPG_SSH_SOCKET="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || echo '<unknown>')"
info "Agent socket: $GPG_SOCKET"
info "SSH socket:   $GPG_SSH_SOCKET"

if [[ -S "$GPG_SOCKET" ]]; then
  pass "GPG agent socket exists"
else
  fail "GPG agent socket missing: $GPG_SOCKET"
  ERRORS=$((ERRORS + 1))
  if $FIX && [[ "$MODE" == "local" ]]; then
    warn "Restoring local GPG agent..."
    gpgconf --kill gpg-agent
    systemctl --user restart gpg-agent.socket gpg-agent-ssh.socket 2>/dev/null || true
    sleep 1
    if [[ -S "$GPG_SOCKET" ]]; then
      pass "GPG agent socket restored"
    else
      fail "Could not restore GPG agent socket"
    fi
  elif [[ "$MODE" == "remote" ]]; then
    warn "Socket missing — reconnect SSH with GPG forwarding to fix"
  fi
fi

# Check systemd socket units
if [[ "$MODE" == "local" ]]; then
  if systemctl --user is-active gpg-agent.socket >/dev/null 2>&1; then
    pass "gpg-agent.socket is active"
  else
    fail "gpg-agent.socket is not active"
    ERRORS=$((ERRORS + 1))
    if $FIX; then
      warn "Starting gpg-agent.socket..."
      systemctl --user start gpg-agent.socket 2>/dev/null || true
    fi
  fi
fi

# GPG agent monitor
if systemctl --user is-active gpg-agent-monitor >/dev/null 2>&1; then
  pass "gpg-agent-monitor service is running"
else
  warn "gpg-agent-monitor service is not running"
  if $FIX; then
    warn "Starting gpg-agent-monitor..."
    systemctl --user start gpg-agent-monitor 2>/dev/null || true
  fi
fi

# GPG agent symlink for ssh-agent-switcher
GPG_AGENT_LINK="$HOME/.gnupg/agent.gpg-ssh"
if [[ -L "$GPG_AGENT_LINK" ]]; then
  pass "GPG-SSH discovery symlink exists"
  LINK_TARGET=$(readlink "$GPG_AGENT_LINK")
  info "Points to: $LINK_TARGET"
else
  warn "GPG-SSH discovery symlink missing: $GPG_AGENT_LINK"
fi

# --- YubiKey ---
header "YubiKey / Smart Card"

if command -v gpg-connect-agent >/dev/null 2>&1; then
  SCD_RESULT=$(gpg-connect-agent "scd getattr SERIALNO" /bye 2>&1) || true
  if [[ "$SCD_RESULT" == *"SERIALNO"* && "$SCD_RESULT" != *"error"* && "$SCD_RESULT" != *"No such device"* ]]; then
    SERIAL=$(echo "$SCD_RESULT" | grep "SERIALNO" | head -1 | awk '{print $3}')
    pass "YubiKey detected (serial: ${SERIAL:-unknown})"
  else
    if [[ "$MODE" == "local" ]]; then
      fail "No YubiKey detected (expected in local mode)"
      ERRORS=$((ERRORS + 1))
      warn "Plug in your YubiKey or check USB connection"
    else
      info "No local YubiKey (expected in remote mode)"
    fi
  fi
fi

# --- GPG Round Trip ---
header "GPG Round Trip"

GPG_KEY="0x06B3614378AFA59E"
RT_RESULT=$(echo "agent-check test" | gpg --batch --yes --encrypt --recipient "$GPG_KEY" 2>/dev/null | gpg --batch --yes --decrypt 2>/dev/null) || true
if [[ "$RT_RESULT" == "agent-check test" ]]; then
  pass "GPG encrypt/decrypt round trip succeeded"
else
  fail "GPG round trip failed"
  ERRORS=$((ERRORS + 1))
  if [[ "$MODE" == "local" ]]; then
    warn "Check YubiKey connection and run: gpg --card-status"
  else
    warn "Check GPG forwarding — reconnect SSH with: ssh -R <socket> ..."
  fi
fi

# --- Summary ---
header "Summary"
if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All checks passed${NC} (mode: ${MODE})"
else
  echo -e "  ${RED}${BOLD}${ERRORS} issue(s) found${NC} (mode: ${MODE})"
  if ! $FIX; then
    echo -e "  Run ${BOLD}agent-check --fix${NC} to attempt automatic fixes"
  fi
  if [[ "$MODE" == "remote" && $ERRORS -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}Tip:${NC} Disconnect and reconnect SSH with agent forwarding:"
    echo -e "    ssh -A -R \$(gpgconf --list-dirs agent-socket):\$(gpgconf --list-dirs agent-extra-socket) desktop"
  fi
fi
echo ""

exit "$ERRORS"
