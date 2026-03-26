#!/usr/bin/env python3
"""db-wallpaper-sync — Download wallpapers from Digital Blasphemy.

Authenticates as a member using curl_cffi (browser TLS fingerprinting)
and downloads wallpapers at a given resolution. Idempotent: skips
already-downloaded files.
"""

import argparse
import os
import re
import sys
import time
from urllib.parse import urlencode

from curl_cffi.requests import Session


BASE_URL = "https://digitalblasphemy.com"
# Non-wallpaper slugs that appear in /sec/ links
SLUG_BLOCKLIST = {"memberships", "tip-jar", "my-account", "cart", "checkout"}


def login(session: Session, username: str, password: str) -> bool:
    """Login via WooCommerce my-account form."""
    # Fetch login page to get nonce
    resp = session.get(f"{BASE_URL}/my-account/")
    resp.raise_for_status()

    match = re.search(
        r'name="woocommerce-login-nonce"\s+value="([^"]+)"', resp.text
    )
    if not match:
        print("Error: Could not extract login nonce", file=sys.stderr)
        return False

    nonce = match.group(1)

    # Submit login form with explicit urlencode to handle special chars in password
    form_data = urlencode({
        "username": username,
        "password": password,
        "woocommerce-login-nonce": nonce,
        "_wp_http_referer": "/my-account/",
        "login": "Log in",
        "rememberme": "forever",
    })
    resp = session.post(
        f"{BASE_URL}/my-account/",
        data=form_data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        allow_redirects=True,
    )

    # Check if login succeeded by looking for logout link or dashboard content
    if "woocommerce-MyAccount-navigation" in resp.text or "Log out" in resp.text:
        return True

    # Check for error messages
    if "woocommerce-error" in resp.text:
        error_match = re.search(r"<li[^>]*>(.*?)</li>", resp.text)
        if error_match:
            print(f"Login error: {error_match.group(1)}", file=sys.stderr)
        return False

    # Might still be logged in even without explicit markers
    return True


def get_wallpaper_slugs(session: Session, resolution: str, page: int) -> list[str]:
    """Extract wallpaper slugs from a gallery page."""
    url = f"{BASE_URL}/wallpaper-resolutions/single/{resolution}/page/{page}/"
    resp = session.get(url)

    if resp.status_code != 200:
        return []

    slugs = re.findall(r"/sec/([a-zA-Z0-9_-]+)/", resp.text)
    # Deduplicate while preserving order, filter blocklist
    seen = set()
    result = []
    for slug in slugs:
        if slug not in seen and slug not in SLUG_BLOCKLIST:
            seen.add(slug)
            result.append(slug)
    return result


def download_wallpaper(
    session: Session, slug: str, width: str, height: str, outfile: str
) -> bool:
    """Download a single wallpaper. Returns True on success."""
    url = f"{BASE_URL}/db-serve/wallpaper/{slug}/single/{width}/{height}/"
    resp = session.get(url, allow_redirects=True)

    if resp.status_code != 200:
        print(f"  Failed (HTTP {resp.status_code}): {slug}", file=sys.stderr)
        return False

    content_type = resp.headers.get("content-type", "")
    if not content_type.startswith("image/"):
        # Check if we got redirected to an error page
        if "unauthorized" in resp.url or len(resp.content) < 1000:
            print(f"  Skipped (not authorized): {slug}", file=sys.stderr)
            return False
        # Large response with wrong content-type might still be an image
        # Fall through and save it

    if len(resp.content) < 100:
        print(f"  Skipped (empty response): {slug}", file=sys.stderr)
        return False

    with open(outfile, "wb") as f:
        f.write(resp.content)
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Download wallpapers from Digital Blasphemy"
    )
    parser.add_argument(
        "--username-file", required=True, help="File containing the username"
    )
    parser.add_argument(
        "--password-file", required=True, help="File containing the password"
    )
    parser.add_argument(
        "--output-dir", required=True, help="Directory to save wallpapers"
    )
    parser.add_argument(
        "--resolution", default="3840x1600", help="Target resolution (default: 3840x1600)"
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=5,
        help="Max gallery pages to scan (default: 5)",
    )
    args = parser.parse_args()

    # Read credentials
    try:
        username = open(args.username_file).read().strip()
        password = open(args.password_file).read().strip()
    except (OSError, IOError) as e:
        print(f"Error reading credentials: {e}", file=sys.stderr)
        sys.exit(1)

    if not username or not password:
        print("Error: Username or password file is empty", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)

    width, height = args.resolution.split("x")

    # Use curl_cffi with Chrome fingerprint to bypass Cloudflare
    with Session(impersonate="chrome131") as session:
        print("Logging in to Digital Blasphemy...")
        if not login(session, username, password):
            print("Warning: Login may have failed, attempting downloads anyway", file=sys.stderr)

        print(f"Scanning gallery for wallpapers at {args.resolution}...")

        downloaded = 0
        skipped = 0

        for page in range(1, args.max_pages + 1):
            slugs = get_wallpaper_slugs(session, args.resolution, page)
            if not slugs:
                break

            for slug in slugs:
                outfile = os.path.join(
                    args.output_dir, f"{slug}_{args.resolution}.jpg"
                )

                if os.path.exists(outfile):
                    skipped += 1
                    continue

                if download_wallpaper(session, slug, width, height, outfile):
                    downloaded += 1
                    print(f"  Downloaded: {slug}")

                # Rate limiting
                time.sleep(1)

        print(f"Sync complete: {downloaded} downloaded, {skipped} already present")


if __name__ == "__main__":
    main()
