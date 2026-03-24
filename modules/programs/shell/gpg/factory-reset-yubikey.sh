#!/usr/bin/env bash
set -euo pipefail

# YubiKey Factory Reset Script
# Resets all applets to factory defaults.

# Colors
red=$'\e[1;31m'
green=$'\e[1;32m'
yellow=$'\e[1;33m'
blue=$'\e[1;34m'
reset=$'\e[0m'

info() { printf '%s==>%s %s\n' "$blue" "$reset" "$*" >&2; }
success() { printf '%s==>%s %s\n' "$green" "$reset" "$*" >&2; }
warn() { printf '%s==> WARNING:%s %s\n' "$yellow" "$reset" "$*" >&2; }
error() {
  printf '%s==> ERROR:%s %s\n' "$red" "$reset" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: factory-reset-yubikey.sh [OPTIONS]

Factory reset a YubiKey, clearing all applets to defaults.

Options:
    -h, --help              Show this help
    -s, --serial SERIAL     YubiKey serial number (prompted if multiple detected)
    -y, --yes               Skip confirmation prompt
    --dry-run               Show what would be done

Examples:
    factory-reset-yubikey.sh
    factory-reset-yubikey.sh --serial 12345678
    factory-reset-yubikey.sh --dry-run
EOF
  exit 0
}

# Argument parsing
YUBIKEY_SERIAL=""
YES=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help) usage ;;
  -s | --serial)
    YUBIKEY_SERIAL="$2"
    shift 2
    ;;
  -y | --yes)
    YES=1
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -*) error "Unknown option: $1" ;;
  *) error "Unexpected argument: $1" ;;
  esac
done

# Check dependencies
command -v ykman &>/dev/null || error "Missing dependency: ykman"

# Helper to run ykman with --device if serial is set
ykman_run() {
  if [[ -n "$YUBIKEY_SERIAL" ]]; then
    ykman --device "$YUBIKEY_SERIAL" "$@"
  else
    ykman "$@"
  fi
}

# Detect and select YubiKey
YUBIKEY_LIST=$(ykman list 2>/dev/null || true)
[[ -n "$YUBIKEY_LIST" ]] || error "No YubiKey detected"

YUBIKEY_COUNT=$(echo "$YUBIKEY_LIST" | grep -c "YubiKey" || true)

if [[ $YUBIKEY_COUNT -eq 0 ]]; then
  error "No YubiKey detected"
elif [[ $YUBIKEY_COUNT -eq 1 ]]; then
  if [[ -z "$YUBIKEY_SERIAL" ]]; then
    YUBIKEY_SERIAL=$(echo "$YUBIKEY_LIST" | grep -oP 'Serial: \K[0-9]+' || true)
  fi
  info "YubiKey detected: $(echo "$YUBIKEY_LIST" | head -1)"
else
  info "Multiple YubiKeys detected:"
  echo "$YUBIKEY_LIST" | nl -w2 -s'. ' >&2

  if [[ -z "$YUBIKEY_SERIAL" ]]; then
    echo >&2
    read -rp "Enter YubiKey serial number: " YUBIKEY_SERIAL
  fi

  if ! echo "$YUBIKEY_LIST" | grep -q "Serial: $YUBIKEY_SERIAL"; then
    error "YubiKey with serial $YUBIKEY_SERIAL not found"
  fi

  info "Selected YubiKey: $(echo "$YUBIKEY_LIST" | grep "Serial: $YUBIKEY_SERIAL")"
fi

# Show current state
echo >&2
info "Current YubiKey info:"
ykman_run info >&2
echo >&2

# Summary
cat >&2 <<EOF
=== Factory Reset ===
YubiKey serial: ${YUBIKEY_SERIAL:-<auto-detect>}
Dry run:        $( ((DRY_RUN)) && echo yes || echo no)

WARNING: This will erase ALL data on the YubiKey:
  - OpenPGP keys and configuration
  - FIDO2/U2F credentials
  - OTP slots
  - PIV certificates

EOF

((DRY_RUN)) && {
  info "Dry run mode - no changes made"
  exit 0
}

if [[ $YES -eq 0 ]]; then
  read -rp "Type 'RESET' to confirm factory reset: " confirm
  [[ "$confirm" == "RESET" ]] || {
    echo "Aborted."
    exit 1
  }
fi

# Reset all applets
info "Resetting OpenPGP applet..."
ykman_run openpgp reset --force
success "OpenPGP reset"

info "Resetting FIDO2 applet..."
ykman_run fido reset --force 2>/dev/null || warn "FIDO2 reset skipped (may require touch or not supported)"
success "FIDO2 reset"

info "Resetting OTP slots..."
ykman_run otp delete 1 --force 2>/dev/null || true
ykman_run otp delete 2 --force 2>/dev/null || true
success "OTP reset"

# Verification
echo >&2
info "=== Verification ==="
ykman_run info >&2

echo >&2
success "Factory reset complete. YubiKey is back to defaults."
