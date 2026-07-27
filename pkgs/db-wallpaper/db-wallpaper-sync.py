#!/usr/bin/env python3
"""db-wallpaper-sync — Download wallpapers from Digital Blasphemy.

Authenticates as a member using curl_cffi (browser TLS fingerprinting)
and downloads wallpapers at a given resolution. Idempotent: skips
already-downloaded files.
"""

import argparse
import json
import os
import re
import sys
import time
from urllib.parse import unquote, urlencode, urlparse

from curl_cffi.requests import Session


BASE_URL = "https://digitalblasphemy.com"
API_BASE_URL = "https://api.digitalblasphemy.com/v2/core"
# Non-wallpaper slugs that appear in /sec/ links
SLUG_BLOCKLIST = {"memberships", "tip-jar", "my-account", "cart", "checkout"}


class CloudflareChallengeError(RuntimeError):
    pass


class ApiError(RuntimeError):
    pass


def read_secret_file(
    path: str | None,
    label: str,
    required: bool = True,
) -> str | None:
    if not path:
        if required:
            print(f"Error: {label} file is required", file=sys.stderr)
            sys.exit(1)
        return None

    try:
        value = open(path).read().strip()
    except (OSError, IOError) as e:
        if required:
            print(f"Error reading {label}: {e}", file=sys.stderr)
            sys.exit(1)
        return None

    if not value and required:
        print(f"Error: {label} file is empty", file=sys.stderr)
        sys.exit(1)

    return value or None


def api_request(
    session: Session,
    method: str,
    path: str,
    token: str | None = None,
    **kwargs,
) -> dict:
    headers = kwargs.pop("headers", {})
    if token:
        headers["X-DB-Token"] = token

    resp = session.request(
        method,
        f"{API_BASE_URL}{path}",
        headers=headers,
        **kwargs,
    )

    if resp.status_code == 503:
        raise ApiError("Digital Blasphemy API is currently unavailable")

    try:
        payload = resp.json()
    except json.JSONDecodeError as e:
        raise ApiError(
            f"Digital Blasphemy API returned non-JSON HTTP {resp.status_code}"
        ) from e

    if resp.status_code >= 400:
        description = (
            payload.get("description")
            or payload.get("message")
            or resp.reason
        )
        raise ApiError(f"Digital Blasphemy API HTTP {resp.status_code}: {description}")

    return payload


def api_authenticate(session: Session, username: str, password: str) -> str:
    payload = api_request(
        session,
        "POST",
        "/account/auth",
        json={
            "username": username,
            "password": password,
            "force_new_key": False,
        },
    )
    api_key = payload.get("user", {}).get("api_key")
    if not api_key:
        raise ApiError(
            "Digital Blasphemy API auth response did not include user.api_key"
        )
    return api_key


def wallpaper_id(wallpaper: dict) -> int | str | None:
    return wallpaper.get("id") or wallpaper.get("wallpaper_id")


def wallpaper_name(wallpaper: dict, fallback: int | str) -> str:
    name = wallpaper.get("name") or wallpaper.get("title") or str(fallback)
    return (
        re.sub(r"[^a-zA-Z0-9._-]+", "-", name.lower()).strip("-")
        or str(fallback)
    )


def api_wallpapers(
    session: Session,
    token: str,
    page: int,
    include_resolutions: bool,
) -> list[dict]:
    payload = api_request(
        session,
        "GET",
        "/wallpapers",
        token=token,
        params={
            "include_resolutions": str(include_resolutions).lower(),
            "include_galleries": "false",
            "include_tags": "false",
            "include_wallpaper": "true",
            "limit": 50,
            "orderby": "date",
            "order": "desc",
            "page": page,
        },
    )
    wallpapers = payload.get("wallpapers", [])
    if isinstance(wallpapers, dict):
        return list(wallpapers.values())
    return wallpapers


def matching_api_resolution(wallpaper: dict, width: str, height: str) -> bool:
    resolutions = wallpaper.get("resolutions") or {}
    for item in resolutions.get("single", []):
        if str(item.get("width")) == width and str(item.get("height")) == height:
            return True
    return not resolutions


def download_url_filename(url: str) -> str | None:
    path = unquote(urlparse(url).path)
    name = os.path.basename(path)
    return name or None


def api_download_wallpaper(
    session: Session,
    token: str,
    wallpaper: dict,
    width: str,
    height: str,
    output_dir: str,
    show_watermark: bool,
) -> tuple[str, bool] | None:
    wid = wallpaper_id(wallpaper)
    if wid is None:
        print("  Skipped wallpaper without id", file=sys.stderr)
        return None

    payload = api_request(
        session,
        "GET",
        f"/download/wallpaper/{wid}",
        token=token,
        params={
            "type": "single",
            "width": width,
            "height": height,
            "show_watermark": str(show_watermark).lower(),
        },
    )
    url = payload.get("download", {}).get("url")
    if not url:
        print(f"  Skipped (no download URL): {wid}", file=sys.stderr)
        return None

    filename = (
        download_url_filename(url)
        or f"{wallpaper_name(wallpaper, wid)}_{width}x{height}.jpg"
    )
    outfile = os.path.join(output_dir, filename)
    if os.path.exists(outfile):
        return outfile, False

    resp = session.get(url, allow_redirects=True)
    if resp.status_code != 200:
        print(f"  Failed (HTTP {resp.status_code}): {wid}", file=sys.stderr)
        return None

    content_type = resp.headers.get("content-type", "")
    if not content_type.startswith("image/") and len(resp.content) < 1000:
        print(f"  Skipped (not an image): {wid}", file=sys.stderr)
        return None

    with open(outfile, "wb") as f:
        f.write(resp.content)
    return outfile, True


def sync_with_api(
    session: Session,
    token: str,
    output_dir: str,
    resolution: str,
    max_pages: int,
    show_watermark: bool,
) -> None:
    width, height = resolution.split("x")
    print(f"Scanning Digital Blasphemy API for wallpapers at {resolution}...")

    downloaded = 0
    skipped = 0

    for page in range(1, max_pages + 1):
        wallpapers = api_wallpapers(session, token, page, include_resolutions=True)
        if not wallpapers:
            break

        for wallpaper in wallpapers:
            if not matching_api_resolution(wallpaper, width, height):
                skipped += 1
                continue

            result = api_download_wallpaper(
                session,
                token,
                wallpaper,
                width,
                height,
                output_dir,
                show_watermark,
            )
            if result is None:
                skipped += 1
            else:
                outfile, was_downloaded = result
                if not was_downloaded:
                    skipped += 1
                    continue
                downloaded += 1
                print(f"  Downloaded: {os.path.basename(outfile)}")

            time.sleep(1)

    print(f"Sync complete: {downloaded} downloaded, {skipped} skipped")


def login(session: Session, username: str, password: str) -> bool:
    """Login via WooCommerce my-account form."""
    # Fetch login page to get nonce
    resp = session.get(f"{BASE_URL}/my-account/")
    if resp.status_code == 403 and resp.headers.get("cf-mitigated") == "challenge":
        raise CloudflareChallengeError(
            "Digital Blasphemy login page returned a Cloudflare challenge "
            "before credentials were submitted"
        )
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
        "--api-token-file",
        help="File containing a Digital Blasphemy API token (X-DB-Token)",
    )
    parser.add_argument("--username-file", help="File containing the username")
    parser.add_argument("--password-file", help="File containing the password")
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
    parser.add_argument(
        "--show-watermark",
        action="store_true",
        help="Request watermarked downloads from the API",
    )
    parser.add_argument(
        "--legacy-scrape",
        action="store_true",
        help="Use the old website scraper instead of the official API",
    )
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    if "x" not in args.resolution:
        print("Error: resolution must be WIDTHxHEIGHT", file=sys.stderr)
        sys.exit(1)

    with Session(impersonate="chrome131") as session:
        if not args.legacy_scrape:
            try:
                token = read_secret_file(
                    args.api_token_file,
                    "API token",
                    required=False,
                )
                if not token:
                    username = read_secret_file(args.username_file, "username")
                    password = read_secret_file(args.password_file, "password")
                    print("Authenticating to Digital Blasphemy API...")
                    token = api_authenticate(session, username, password)

                sync_with_api(
                    session,
                    token,
                    args.output_dir,
                    args.resolution,
                    args.max_pages,
                    args.show_watermark,
                )
            except ApiError as e:
                print(f"Error: {e}", file=sys.stderr)
                sys.exit(1)
            return

        username = read_secret_file(args.username_file, "username")
        password = read_secret_file(args.password_file, "password")
        width, height = args.resolution.split("x")

        try:
            print("Logging in to Digital Blasphemy...")
            if not login(session, username, password):
                print(
                    "Warning: Login may have failed, attempting downloads anyway",
                    file=sys.stderr,
                )

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
        except CloudflareChallengeError as e:
            print(f"Error: {e}", file=sys.stderr)
            print("Use the official API path with --api-token-file instead.", file=sys.stderr)
            sys.exit(1)
        except ApiError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
