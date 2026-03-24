#!/usr/bin/env bash
set -euo pipefail

# GPG Subkey Rotation Script
# Extends expiry on all subkeys from a GPG backup directory.
# Writes rotated keys to a sibling output directory (original is never modified),
# then publishes to keyserver.

DEFAULT_EXPIRATION="2y"

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
Usage: rotate-gpg-subkeys.sh [OPTIONS] <backup-dir>

Extend GPG subkey expiry from a backup directory and publish to keyserver.
The original backup is never modified — rotated keys are written to a sibling
directory (e.g., gnupg_2y_rotate).

Arguments:
    <backup-dir>            Path to GPG backup directory containing
                            private-keys-v1.d/ (e.g., ~/gnupg_backup/gnupg)

Options:
    -h, --help              Show this help
    --expiration DURATION   Subkey expiry duration (default: 2y)
    --passphrase PASS       Master key passphrase (prompted if not set)
    -y, --yes               Skip confirmation prompts
    --dry-run               Show what would be done

Examples:
    rotate-gpg-subkeys.sh ~/gnupg_backup/gnupg
    rotate-gpg-subkeys.sh --expiration 1y ~/gnupg_backup/gnupg
    rotate-gpg-subkeys.sh --dry-run ~/gnupg_backup/gnupg
EOF
  exit 0
}

prompt_secret() {
  local name="$1" varname="$2"
  local val
  read -rsp "Enter $name: " val
  echo >&2
  [[ -n "$val" ]] || error "$name cannot be empty"
  printf -v "$varname" '%s' "$val"
}

# Argument parsing
EXPIRATION=""
PASSPHRASE=""
YES=0
DRY_RUN=0
BACKUP_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help) usage ;;
  --expiration)
    EXPIRATION="$2"
    shift 2
    ;;
  --passphrase)
    PASSPHRASE="$2"
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
    [[ -z "$BACKUP_DIR" ]] || error "Unexpected argument: $1"
    BACKUP_DIR="$1"
    shift
    ;;
  esac
done

# Defaults
EXPIRATION="${EXPIRATION:-$DEFAULT_EXPIRATION}"

# Validation
[[ -n "$BACKUP_DIR" ]] || error "Backup directory required. Use -h for help."
[[ -d "$BACKUP_DIR" ]] || error "Directory not found: $BACKUP_DIR"
[[ -d "$BACKUP_DIR/private-keys-v1.d" ]] || error "Not a GPG backup directory (missing private-keys-v1.d/): $BACKUP_DIR"

# Check dependencies
command -v gpg &>/dev/null || error "Missing dependency: gpg"

# Create temp GNUPGHOME from backup
TEMP_GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$TEMP_GNUPGHOME"' EXIT
export GNUPGHOME="$TEMP_GNUPGHOME"

info "Copying backup to temp GNUPGHOME: $TEMP_GNUPGHOME"
cp -a "$BACKUP_DIR"/. "$TEMP_GNUPGHOME"/

# Fix permissions
chmod 700 "$TEMP_GNUPGHOME"
find "$TEMP_GNUPGHOME" -type f -exec chmod 600 {} +
find "$TEMP_GNUPGHOME" -type d -exec chmod 700 {} +

# Import/detect keys
gpg --list-keys &>/dev/null 2>&1 || true

KEY_FPR=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^fpr' | head -1 | cut -d: -f10)
[[ -n "$KEY_FPR" ]] || error "No secret key found in backup directory"

KEYID=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec' | head -1 | cut -d: -f5)
[[ -n "$KEYID" ]] || error "Could not determine key ID"

info "Key ID: $KEYID"
info "Fingerprint: $KEY_FPR"

# Show current key state
echo >&2
info "Current key state:"
gpg --list-secret-keys --keyid-format long "$KEY_FPR" >&2

# Count subkeys
SUBKEY_COUNT=$(gpg --list-secret-keys --with-colons "$KEY_FPR" | grep -c '^ssb')
info "Found $SUBKEY_COUNT subkeys to extend"

# Estimate output directory name using date arithmetic
# Parse expiration duration (e.g., 2y, 6m, 30d) into a date string for GNU date
estimate_expiry_date() {
  local dur="$1"
  local num="${dur%[ymd]}"
  local unit="${dur##*[0-9]}"
  case "$unit" in
  y) date -d "+${num} years" +%F ;;
  m) date -d "+${num} months" +%F ;;
  d) date -d "+${num} days" +%F ;;
  *) echo "unknown" ;;
  esac
}
ESTIMATED_EXPIRY=$(estimate_expiry_date "$EXPIRATION")

BACKUP_BASENAME=$(basename "$BACKUP_DIR")
BACKUP_PARENT=$(dirname "$BACKUP_DIR")
OUTPUT_DIR="$BACKUP_PARENT/${BACKUP_BASENAME}_${ESTIMATED_EXPIRY}_rotate"

# Summary
cat >&2 <<EOF

=== Rotation Summary ===
Key ID:       $KEYID
Fingerprint:  $KEY_FPR
Subkeys:      $SUBKEY_COUNT
New expiry:   $EXPIRATION from today (~$ESTIMATED_EXPIRY)
Input dir:    $BACKUP_DIR (read-only, not modified)
Output dir:   $OUTPUT_DIR
Dry run:      $( ((DRY_RUN)) && echo yes || echo no)

EOF

((DRY_RUN)) && {
  info "Dry run mode - no changes made"
  exit 0
}

# Prompt for passphrase if not provided
[[ -n "$PASSPHRASE" ]] || prompt_secret "master key passphrase" PASSPHRASE

if [[ $YES -eq 0 ]]; then
  read -rp "Proceed? [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || {
    echo "Aborted."
    exit 1
  }
fi

# Extend subkey expiry
info "Extending subkey expiry to $EXPIRATION..."
echo "$PASSPHRASE" | gpg --batch --pinentry-mode=loopback \
  --passphrase-fd 0 --quick-set-expire "$KEY_FPR" "$EXPIRATION" "*"
success "Subkey expiry extended"

# Read the actual expiry date from GPG and update output dir name
NEW_EXPIRY_EPOCH=$(gpg --list-keys --with-colons "$KEY_FPR" | grep '^sub' | head -1 | cut -d: -f7)
NEW_EXPIRY_DATE=$(date -d "@$NEW_EXPIRY_EPOCH" +%F)
OUTPUT_DIR="$BACKUP_PARENT/${BACKUP_BASENAME}_${NEW_EXPIRY_DATE}_rotate"
info "New expiry date: $NEW_EXPIRY_DATE"

# Show updated key state
echo >&2
info "Updated key state:"
gpg --list-secret-keys --keyid-format long "$KEY_FPR" >&2

# Create output directory (copy full rotated GNUPGHOME)
[[ ! -d "$OUTPUT_DIR" ]] || error "Output directory already exists: $OUTPUT_DIR"
info "Copying rotated keyring to $OUTPUT_DIR..."
cp -a "$TEMP_GNUPGHOME" "$OUTPUT_DIR"
success "Rotated keyring saved: $OUTPUT_DIR"

# Export updated public key into output dir
KEYFILE="$OUTPUT_DIR/$KEYID-$(date +%F).asc"
info "Exporting public key to $KEYFILE..."
gpg --armor --export "$KEYID" >"$KEYFILE"
success "Public key exported: $KEYFILE"

# Re-export master+sub secret key into output dir
MASTERSUB_FILE="$OUTPUT_DIR/mastersub.key"
info "Exporting master+sub secret key to $MASTERSUB_FILE..."
echo "$PASSPHRASE" | gpg --batch --pinentry-mode=loopback \
  --passphrase-fd 0 --armor --export-secret-keys "$KEY_FPR" >"$MASTERSUB_FILE"
success "Secret key exported: $MASTERSUB_FILE"

# Lock down output directory
chmod 700 "$OUTPUT_DIR"
find "$OUTPUT_DIR" -type f -exec chmod 400 {} +
find "$OUTPUT_DIR" -type d -exec chmod 500 {} +

# Publish to keyserver
info "Publishing key to keyserver..."
gpg --send-key "$KEYID"
success "Key published"

# Verify: fetch back from keyserver
info "Fetching key back from keyserver to verify..."
gpg --recv-keys "$KEYID" 2>&1 | grep -v '^$' >&2 || true

# Final verification
echo >&2
info "=== Verification ==="

info "Key details:"
gpg --list-keys --keyid-format long --with-fingerprint --with-subkey-fingerprint "$KEY_FPR" >&2
echo >&2

info "Secret key details:"
gpg --list-secret-keys --keyid-format long "$KEY_FPR" >&2
echo >&2

info "Exported files:"
ls -lh "$KEYFILE" "$MASTERSUB_FILE" >&2

echo >&2
success "Rotation complete!"
cat >&2 <<EOF

Output:   $OUTPUT_DIR
          (original backup untouched: $BACKUP_DIR)

Next steps:
  1. Run provision-yubikey.sh to load updated subkeys onto YubiKey(s):
     provision-yubikey.sh -r $MASTERSUB_FILE
  2. Verify with: gpg --card-status
  3. Test signing: echo test | gpg --clearsign
EOF
