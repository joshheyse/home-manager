#!/usr/bin/env bash
# db-wallpaper-sync — Download wallpapers from Digital Blasphemy
# Authenticates as a member and downloads wallpapers at a given resolution.
# Idempotent: skips already-downloaded files.

set -euo pipefail

USERNAME_FILE=""
PASSWORD_FILE=""
OUTPUT_DIR=""
RESOLUTION="3840x1600"
MAX_PAGES=5

usage() {
  echo "Usage: db-wallpaper-sync --username-file <path> --password-file <path> --output-dir <path> [--resolution WxH] [--max-pages N]"
  echo ""
  echo "  --username-file  File containing the username"
  echo "  --password-file  File containing the password"
  echo "  --output-dir     Directory to save wallpapers"
  echo "  --resolution     Target resolution (default: 3840x1600)"
  echo "  --max-pages      Max gallery pages to scan (default: 5)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username-file)
      USERNAME_FILE="$2"
      shift 2
      ;;
    --password-file)
      PASSWORD_FILE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --resolution)
      RESOLUTION="$2"
      shift 2
      ;;
    --max-pages)
      MAX_PAGES="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$USERNAME_FILE" || -z "$PASSWORD_FILE" || -z "$OUTPUT_DIR" ]]; then
  usage
fi

if [[ ! -r "$USERNAME_FILE" ]]; then
  echo "Error: Cannot read username file: $USERNAME_FILE" >&2
  exit 1
fi

if [[ ! -r "$PASSWORD_FILE" ]]; then
  echo "Error: Cannot read password file: $PASSWORD_FILE" >&2
  exit 1
fi

USERNAME=$(cat "$USERNAME_FILE")
PASSWORD=$(cat "$PASSWORD_FILE")

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
  echo "Error: Username or password file is empty" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Parse resolution into width/height
WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"

# Cookie jar for session
COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

echo "Logging in to Digital Blasphemy..."

# Login to get session cookies
LOGIN_RESULT=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -X POST "https://digitalblasphemy.com/wp-login.php" \
  -d "log=${USERNAME}&pwd=${PASSWORD}&wp-submit=Log+In&redirect_to=%2F" \
  -w "%{http_code}" \
  -o /dev/null \
  -L)

if [[ "$LOGIN_RESULT" != "200" ]]; then
  echo "Warning: Login returned HTTP $LOGIN_RESULT (may still work with cookies)" >&2
fi

echo "Scanning gallery for wallpapers at ${RESOLUTION}..."

DOWNLOADED=0
SKIPPED=0

# Scan gallery pages for wallpaper slugs
for page in $(seq 1 "$MAX_PAGES"); do
  GALLERY_URL="https://digitalblasphemy.com/wallpaper-resolutions/single/${RESOLUTION}/page/${page}/"

  PAGE_HTML=$(curl -s -b "$COOKIE_JAR" "$GALLERY_URL" || true)

  if [[ -z "$PAGE_HTML" ]]; then
    break
  fi

  # Extract wallpaper slugs from product links (pattern: /sec/SLUG/)
  SLUGS=$(echo "$PAGE_HTML" | grep -oP '(?<=/sec/)[a-zA-Z0-9_-]+(?=/)' | sort -u || true)

  if [[ -z "$SLUGS" ]]; then
    break
  fi

  for slug in $SLUGS; do
    OUTFILE="${OUTPUT_DIR}/${slug}_${RESOLUTION}.jpg"

    # Skip if already downloaded
    if [[ -f "$OUTFILE" ]]; then
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    # Download via db-serve endpoint
    DOWNLOAD_URL="https://digitalblasphemy.com/db-serve/wallpaper/${slug}/single/${WIDTH}/${HEIGHT}/"

    HTTP_CODE=$(curl -s -b "$COOKIE_JAR" \
      -o "$OUTFILE" \
      -w "%{http_code}" \
      "$DOWNLOAD_URL")

    if [[ "$HTTP_CODE" == "200" ]] && [[ -s "$OUTFILE" ]]; then
      # Verify it's actually an image (not an error page)
      FILE_TYPE=$(file -b --mime-type "$OUTFILE")
      if [[ "$FILE_TYPE" == image/* ]]; then
        DOWNLOADED=$((DOWNLOADED + 1))
        echo "  Downloaded: ${slug}"
      else
        rm -f "$OUTFILE"
        echo "  Skipped (not an image): ${slug}" >&2
      fi
    else
      rm -f "$OUTFILE"
      echo "  Failed (HTTP ${HTTP_CODE}): ${slug}" >&2
    fi

    # Rate limiting — be kind to the server
    sleep 1
  done
done

echo "Sync complete: ${DOWNLOADED} downloaded, ${SKIPPED} already present"
