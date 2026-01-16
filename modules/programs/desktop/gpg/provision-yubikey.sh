#!/usr/bin/env bash
set -euo pipefail

# Yubikey OpenPGP Provisioning Script
# Imports GPG private key and moves subkeys to Yubikey

DEFAULT_TOUCH_POLICY="cached"
DEFAULT_PIN_RETRIES=8
DEFAULT_RESET_RETRIES=8
DEFAULT_ADMIN_RETRIES=8
FACTORY_USER_PIN="123456"
FACTORY_ADMIN_PIN="12345678"

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
Usage: provision-yubikey.sh [OPTIONS] <private-key-file>

Provision a Yubikey with GPG keys from backup.

Options:
    -h, --help              Show this help
    -r, --reset             Reset OpenPGP applet before provisioning
    -s, --serial SERIAL     YubiKey serial number (prompted if multiple detected)
    -t, --touch POLICY      Touch policy: off, on, fixed, cached, cached-fixed
                            (default: cached)
    --touch-sig POLICY      Touch policy for signature slot
    --touch-enc POLICY      Touch policy for encryption slot
    --touch-aut POLICY      Touch policy for authentication slot
    --user-pin PIN          User PIN (min 6 chars, prompted if not set)
    --admin-pin PIN         Admin PIN (min 8 chars, prompted if not set)
    --reset-code CODE       Reset code (min 8 chars, optional)
    --key-passphrase PASS   Passphrase for the GPG key (prompted if needed)
    --pin-retries N         User PIN retry count (default: 8, max: 127)
    --reset-retries N       Reset code retry count (default: 8, max: 127)
    --admin-retries N       Admin PIN retry count (default: 8, max: 127)
    -y, --yes               Skip confirmation prompts
    --dry-run               Show what would be done

Examples:
    provision-yubikey.sh -r ~/backup/secret-key.asc
    provision-yubikey.sh -r -t cached --user-pin 123456 --admin-pin 12345678 key.asc
    provision-yubikey.sh -r --serial 12345678 ~/backup/secret-key.asc
EOF
  exit 0
}

# Argument parsing
RESET_APPLET=0
YUBIKEY_SERIAL=""
TOUCH_SIG=""
TOUCH_ENC=""
TOUCH_AUT=""
USER_PIN=""
ADMIN_PIN=""
RESET_CODE=""
KEY_PASSPHRASE=""
PIN_RETRIES=""
RESET_RETRIES=""
ADMIN_RETRIES=""
YES=0
DRY_RUN=0
PRIVATE_KEY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help) usage ;;
  -r | --reset)
    RESET_APPLET=1
    shift
    ;;
  -s | --serial)
    YUBIKEY_SERIAL="$2"
    shift 2
    ;;
  -t | --touch)
    TOUCH_SIG="$2"
    TOUCH_ENC="$2"
    TOUCH_AUT="$2"
    shift 2
    ;;
  --touch-sig)
    TOUCH_SIG="$2"
    shift 2
    ;;
  --touch-enc)
    TOUCH_ENC="$2"
    shift 2
    ;;
  --touch-aut)
    TOUCH_AUT="$2"
    shift 2
    ;;
  --user-pin)
    USER_PIN="$2"
    shift 2
    ;;
  --admin-pin)
    ADMIN_PIN="$2"
    shift 2
    ;;
  --reset-code)
    RESET_CODE="$2"
    shift 2
    ;;
  --key-passphrase)
    KEY_PASSPHRASE="$2"
    shift 2
    ;;
  --pin-retries)
    PIN_RETRIES="$2"
    shift 2
    ;;
  --reset-retries)
    RESET_RETRIES="$2"
    shift 2
    ;;
  --admin-retries)
    ADMIN_RETRIES="$2"
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
  *)
    [[ -z "$PRIVATE_KEY_FILE" ]] || error "Unexpected argument: $1"
    PRIVATE_KEY_FILE="$1"
    shift
    ;;
  esac
done

# Defaults
TOUCH_SIG="${TOUCH_SIG:-$DEFAULT_TOUCH_POLICY}"
TOUCH_ENC="${TOUCH_ENC:-$DEFAULT_TOUCH_POLICY}"
TOUCH_AUT="${TOUCH_AUT:-$DEFAULT_TOUCH_POLICY}"
PIN_RETRIES="${PIN_RETRIES:-$DEFAULT_PIN_RETRIES}"
RESET_RETRIES="${RESET_RETRIES:-$DEFAULT_RESET_RETRIES}"
ADMIN_RETRIES="${ADMIN_RETRIES:-$DEFAULT_ADMIN_RETRIES}"

# Validation
[[ -n "$PRIVATE_KEY_FILE" ]] || error "Private key file required. Use -h for help."
[[ -f "$PRIVATE_KEY_FILE" ]] || error "File not found: $PRIVATE_KEY_FILE"

for policy in "$TOUCH_SIG" "$TOUCH_ENC" "$TOUCH_AUT"; do
  case "$policy" in
  off | on | fixed | cached | cached-fixed) ;;
  *) error "Invalid touch policy: $policy" ;;
  esac
done

for retries in "$PIN_RETRIES" "$RESET_RETRIES" "$ADMIN_RETRIES"; do
  [[ "$retries" =~ ^[0-9]+$ ]] || error "Retry count must be a number: $retries"
  ((retries >= 1 && retries <= 127)) || error "Retry count must be 1-127: $retries"
done

# Check dependencies
for cmd in gpg ykman expect; do
  command -v "$cmd" &>/dev/null || error "Missing dependency: $cmd"
done

# Helper function to run ykman with --device flag if serial is available
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
  # Only one YubiKey - use it
  if [[ -z "$YUBIKEY_SERIAL" ]]; then
    YUBIKEY_SERIAL=$(echo "$YUBIKEY_LIST" | grep -oP 'Serial: \K[0-9]+' || true)
  fi
  info "YubiKey detected: $(echo "$YUBIKEY_LIST" | head -1)"
else
  # Multiple YubiKeys detected
  info "Multiple YubiKeys detected:"
  echo "$YUBIKEY_LIST" | nl -w2 -s'. ' >&2

  if [[ -z "$YUBIKEY_SERIAL" ]]; then
    # Prompt user to select
    echo >&2
    read -rp "Enter YubiKey serial number: " YUBIKEY_SERIAL
  fi

  # Verify the serial exists
  if ! echo "$YUBIKEY_LIST" | grep -q "Serial: $YUBIKEY_SERIAL"; then
    error "YubiKey with serial $YUBIKEY_SERIAL not found"
  fi

  info "Selected YubiKey: $(echo "$YUBIKEY_LIST" | grep "Serial: $YUBIKEY_SERIAL")"
fi

# Allow empty serial only if exactly one YubiKey is detected
if [[ -z "$YUBIKEY_SERIAL" && $YUBIKEY_COUNT -ne 1 ]]; then
  error "Failed to determine YubiKey serial number"
fi

# If serial is still empty but we have exactly one key, log it
if [[ -z "$YUBIKEY_SERIAL" ]]; then
  info "Operating on single YubiKey (serial number hidden)"
fi

# Prompt for PINs if not provided
prompt_secret() {
  local name="$1" minlen="$2" varname="$3"
  local val val2
  while true; do
    read -rsp "Enter $name (min $minlen chars): " val
    echo >&2
    [[ ${#val} -ge $minlen ]] || {
      warn "Too short"
      continue
    }
    read -rsp "Confirm $name: " val2
    echo >&2
    [[ "$val" == "$val2" ]] || {
      warn "Mismatch"
      continue
    }
    break
  done
  printf -v "$varname" '%s' "$val"
}

[[ -n "$USER_PIN" ]] || prompt_secret "User PIN" 6 USER_PIN
[[ -n "$ADMIN_PIN" ]] || prompt_secret "Admin PIN" 8 ADMIN_PIN

if [[ -z "$RESET_CODE" && $YES -eq 0 ]]; then
  read -rp "Set a reset code? (recommended) [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] && prompt_secret "Reset Code" 8 RESET_CODE
fi

# Summary
cat <<EOF

=== Provisioning Summary ===
YubiKey serial: ${YUBIKEY_SERIAL:-<hidden/auto-detect>}
Key file:       $PRIVATE_KEY_FILE
Reset applet:   $( ((RESET_APPLET)) && echo yes || echo no)
Touch policies: sig=$TOUCH_SIG enc=$TOUCH_ENC aut=$TOUCH_AUT
Retry counts:   pin=$PIN_RETRIES reset=$RESET_RETRIES admin=$ADMIN_RETRIES
Reset code:     $([[ -n "$RESET_CODE" ]] && echo yes || echo no)
Dry run:        $( ((DRY_RUN)) && echo yes || echo no)

EOF

if [[ $YES -eq 0 ]]; then
  read -rp "Proceed? [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || {
    echo "Aborted."
    exit 1
  }
fi

((DRY_RUN)) && {
  info "Dry run mode - no changes made"
  exit 0
}

# Create temp GNUPGHOME
TEMP_GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$TEMP_GNUPGHOME"' EXIT
export GNUPGHOME="$TEMP_GNUPGHOME"

info "Using temp GNUPGHOME: $TEMP_GNUPGHOME"

# Initialize GPG
gpg --list-keys &>/dev/null || true

# Reset applet if requested
if ((RESET_APPLET)); then
  info "Resetting OpenPGP applet..."
  ykman_run openpgp reset --force
  success "Applet reset"
fi

# Import key
info "Importing private key..."
gpg --batch --import "$PRIVATE_KEY_FILE"
success "Key imported"

# Get key info
KEY_FPR=$(gpg --list-secret-keys --with-colons | grep '^fpr' | head -1 | cut -d: -f10)
[[ -n "$KEY_FPR" ]] || error "No secret key found after import"
info "Key fingerprint: $KEY_FPR"

# Show key structure
info "Key structure:"
gpg --list-secret-keys --keyid-format long "$KEY_FPR"

# Determine subkey count and capabilities
SUBKEY_COUNT=$(gpg --list-secret-keys --with-colons "$KEY_FPR" | grep -c '^ssb')
info "Found $SUBKEY_COUNT subkeys"

# Build expect script for keytocard
# This handles the interactive GPG session
EXPECT_SCRIPT=$(mktemp)
cat >"$EXPECT_SCRIPT" <<'EXPECTEOF'
#!/usr/bin/expect -f

set timeout 30
set fpr [lindex $argv 0]
set admin_pin [lindex $argv 1]
set passphrase [lindex $argv 2]

spawn gpg --edit-key $fpr

# For each subkey (1=sig, 2=enc, 3=aut), select and move to card
# Subkey 1 -> signature slot (1)
expect "gpg>"
send "key 1\r"
expect "gpg>"
send "keytocard\r"
expect {
    "Your selection?" {
        send "1\r"
    }
    "Passphrase:" {
        send "$passphrase\r"
        expect "Your selection?"
        send "1\r"
    }
}
expect {
    "Enter passphrase:" {
        send "$passphrase\r"
        exp_continue
    }
    "Admin PIN" {
        send "$admin_pin\r"
        exp_continue
    }
    "gpg>" {}
}

# Deselect key 1, select key 2
send "key 1\r"
expect "gpg>"
send "key 2\r"
expect "gpg>"
send "keytocard\r"
expect {
    "Your selection?" {
        send "2\r"
    }
    "Passphrase:" {
        send "$passphrase\r"
        expect "Your selection?"
        send "2\r"
    }
}
expect {
    "Enter passphrase:" {
        send "$passphrase\r"
        exp_continue
    }
    "Admin PIN" {
        send "$admin_pin\r"
        exp_continue
    }
    "gpg>" {}
}

# Deselect key 2, select key 3
send "key 2\r"
expect "gpg>"
send "key 3\r"
expect "gpg>"
send "keytocard\r"
expect {
    "Your selection?" {
        send "3\r"
    }
    "Passphrase:" {
        send "$passphrase\r"
        expect "Your selection?"
        send "3\r"
    }
}
expect {
    "Enter passphrase:" {
        send "$passphrase\r"
        exp_continue
    }
    "Admin PIN" {
        send "$admin_pin\r"
        exp_continue
    }
    "gpg>" {}
}

send "save\r"
expect eof
EXPECTEOF

chmod +x "$EXPECT_SCRIPT"

# If key has passphrase, we need it
if [[ -z "$KEY_PASSPHRASE" ]]; then
  # Try empty passphrase first, prompt if needed
  KEY_PASSPHRASE=""
fi

info "Moving subkeys to card..."
expect "$EXPECT_SCRIPT" "$KEY_FPR" "$FACTORY_ADMIN_PIN" "$KEY_PASSPHRASE" || {
  if [[ -z "$KEY_PASSPHRASE" ]]; then
    warn "Key may be passphrase protected"
    read -rsp "Enter key passphrase: " KEY_PASSPHRASE
    echo
    expect "$EXPECT_SCRIPT" "$KEY_FPR" "$FACTORY_ADMIN_PIN" "$KEY_PASSPHRASE"
  else
    error "Failed to move keys to card"
  fi
}
rm -f "$EXPECT_SCRIPT"
success "Subkeys moved to card"

# Set PINs
info "Setting Admin PIN..."
ykman_run openpgp access change-admin-pin \
  --admin-pin "$FACTORY_ADMIN_PIN" \
  --new-admin-pin "$ADMIN_PIN"
success "Admin PIN set"

info "Setting User PIN..."
ykman_run openpgp access change-pin \
  --pin "$FACTORY_USER_PIN" \
  --new-pin "$USER_PIN"
success "User PIN set"

# Set reset code if provided
if [[ -n "$RESET_CODE" ]]; then
  info "Setting reset code..."
  ykman_run openpgp access set-reset-code \
    --admin-pin "$ADMIN_PIN" \
    --reset-code "$RESET_CODE"
  success "Reset code set"
fi

# Set retry counts (enable reset code usage)
info "Setting retry counts to $PIN_RETRIES/$RESET_RETRIES/$ADMIN_RETRIES..."
ykman_run openpgp access set-retries "$PIN_RETRIES" "$RESET_RETRIES" "$ADMIN_RETRIES" --admin-pin "$ADMIN_PIN" --force
success "Retry counts set"

# Set touch policies
info "Setting touch policies..."
ykman_run openpgp keys set-touch sig "$TOUCH_SIG" --admin-pin "$ADMIN_PIN" --force
ykman_run openpgp keys set-touch enc "$TOUCH_ENC" --admin-pin "$ADMIN_PIN" --force
ykman_run openpgp keys set-touch aut "$TOUCH_AUT" --admin-pin "$ADMIN_PIN" --force
success "Touch policies set"

# Final status
echo
info "Final card status:"
ykman_run openpgp info

echo
success "Provisioning complete!"
cat <<EOF

Test commands:
  gpg --card-status
  echo test | gpg --clearsign
  ssh-add -L  # if using gpg-agent for SSH
EOF
