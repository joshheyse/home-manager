#!/usr/bin/env python3
"""KiCad Parts Manager - Import and manage KiCad libraries from LCSC with metadata enrichment."""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

import requests

# Colors for terminal output
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"
NC = "\033[0m"  # No Color


def info(msg: str) -> None:
    print(f"{BLUE}[INFO]{NC} {msg}")


def warn(msg: str) -> None:
    print(f"{YELLOW}[WARN]{NC} {msg}")


def error(msg: str) -> None:
    print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr)


def success(msg: str) -> None:
    print(f"{GREEN}[OK]{NC} {msg}")


class DigikeyClient:
    """Digikey API client with OAuth2 authentication."""

    TOKEN_URL = "https://api.digikey.com/v1/oauth2/token"
    SEARCH_URL = "https://api.digikey.com/Search/v3/Products"

    def __init__(self):
        self.client_id = os.environ.get("DIGIKEY_CLIENT_ID")
        self.client_secret = os.environ.get("DIGIKEY_CLIENT_SECRET")
        self._token: Optional[str] = None
        self._token_expires: float = 0
        self._token_file = Path(tempfile.gettempdir()) / "digikey_token.json"

    @property
    def available(self) -> bool:
        return bool(self.client_id and self.client_secret)

    def _load_cached_token(self) -> Optional[str]:
        if not self._token_file.exists():
            return None
        try:
            data = json.loads(self._token_file.read_text())
            if time.time() < data.get("expires_at", 0):
                return data.get("access_token")
        except (json.JSONDecodeError, KeyError):
            pass
        return None

    def _save_token(self, token: str, expires_in: int) -> None:
        data = {"access_token": token, "expires_at": time.time() + expires_in - 60}
        self._token_file.write_text(json.dumps(data))
        self._token_file.chmod(0o600)

    def get_token(self) -> Optional[str]:
        # Check memory cache
        if self._token and time.time() < self._token_expires:
            return self._token

        # Check file cache
        cached = self._load_cached_token()
        if cached:
            self._token = cached
            return cached

        # Get new token
        try:
            resp = requests.post(
                self.TOKEN_URL,
                data={
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "grant_type": "client_credentials",
                },
                timeout=30,
            )
            resp.raise_for_status()
            data = resp.json()
            token = data["access_token"]
            expires_in = data.get("expires_in", 3600)
            self._save_token(token, expires_in)
            self._token = token
            self._token_expires = time.time() + expires_in - 60
            return token
        except Exception as e:
            warn(f"Failed to get Digikey token: {e}")
            return None

    def search(self, mpn: str) -> Optional[dict]:
        if not self.available:
            warn("Digikey API credentials not set (DIGIKEY_CLIENT_ID, DIGIKEY_CLIENT_SECRET)")
            return None

        token = self.get_token()
        if not token:
            return None

        try:
            resp = requests.get(
                f"{self.SEARCH_URL}/{mpn}",
                headers={
                    "Authorization": f"Bearer {token}",
                    "X-DIGIKEY-Client-Id": self.client_id,
                    "X-DIGIKEY-Locale-Site": "US",
                    "X-DIGIKEY-Locale-Language": "en",
                    "X-DIGIKEY-Locale-Currency": "USD",
                },
                timeout=30,
            )
            if resp.status_code == 200:
                return resp.json()
        except Exception as e:
            warn(f"Digikey API error: {e}")
        return None


class MouserClient:
    """Mouser API client."""

    SEARCH_URL = "https://api.mouser.com/api/v1/search/partnumber"

    def __init__(self):
        self.api_key = os.environ.get("MOUSER_API_KEY")

    @property
    def available(self) -> bool:
        return bool(self.api_key)

    def search(self, mpn: str) -> Optional[dict]:
        if not self.available:
            warn("Mouser API key not set (MOUSER_API_KEY)")
            return None

        try:
            resp = requests.post(
                f"{self.SEARCH_URL}?apiKey={self.api_key}",
                json={"SearchByPartRequest": {"mouserPartNumber": mpn}},
                headers={"Content-Type": "application/json"},
                timeout=30,
            )
            if resp.status_code == 200:
                return resp.json()
        except Exception as e:
            warn(f"Mouser API error: {e}")
        return None


class KicadSymbol:
    """Parser and modifier for KiCad symbol files."""

    def __init__(self, filepath: Path):
        self.filepath = filepath
        self.content = filepath.read_text() if filepath.exists() else ""

    def get_symbol_names(self) -> list[str]:
        """Extract symbol names (excluding internal sub-symbols with ':')."""
        pattern = r'\(symbol "([^":]+)"\s*\('
        return list(set(re.findall(pattern, self.content)))

    def get_property(self, symbol_name: str, prop_name: str) -> Optional[str]:
        """Get a property value from a symbol."""
        # Find the symbol block and extract property
        pattern = rf'\(property "{prop_name}" "([^"]*)"'
        match = re.search(pattern, self.content)
        return match.group(1) if match else None

    def set_property(self, symbol_name: str, prop_name: str, prop_value: str) -> None:
        """Add or update a property in a symbol (in main symbol, not sub-symbols)."""
        prop_value = prop_value.replace("\\", "\\\\").replace('"', '\\"')

        # Check if property already exists - handle both single-line and multi-line formats
        # Single-line: (property "Name" "Value" ...)
        # Multi-line:  (property\n  "Name"\n  "Value"\n  ...)
        lines = self.content.split("\n")
        found_prop = False
        in_target_prop = False
        prop_name_found = False

        for i, line in enumerate(lines):
            # Start of a property block
            if "(property" in line:
                # Check if property name is on same line or next line
                if f'"{prop_name}"' in line:
                    in_target_prop = True
                    prop_name_found = True
                elif "(property" in line and f'"{prop_name}"' not in line:
                    # Multi-line format - check next line for property name
                    in_target_prop = False
                    prop_name_found = False

            # Check for property name on its own line (multi-line format)
            if not prop_name_found and f'"{prop_name}"' in line and '"' == line.strip()[0]:
                in_target_prop = True
                prop_name_found = True
                continue

            # If we're in the target property, look for the value line
            if in_target_prop and prop_name_found:
                # Value line - starts with " and contains the value
                stripped = line.strip()
                if stripped.startswith('"') and stripped.endswith('"'):
                    # This is the value line - replace it
                    indent = line[:len(line) - len(line.lstrip())]
                    lines[i] = f'{indent}"{prop_value}"'
                    found_prop = True
                    break
                elif f'"{prop_name}"' in line:
                    # Single-line format: (property "Name" "Value" ...)
                    pattern = rf'(\(property\s+"{prop_name}"\s+")[^"]*(")'
                    lines[i] = re.sub(pattern, rf'\g<1>{prop_value}\g<2>', line)
                    found_prop = True
                    break

        if found_prop:
            self.content = "\n".join(lines)
            return
        else:
            # Add new property after the last existing property in the main symbol
            # Find the position just before the first sub-symbol (symbol "NAME_0_1" or similar)
            lines = self.content.split("\n")
            result = []
            inserted = False
            in_main_symbol = False
            last_property_idx = -1

            for i, line in enumerate(lines):
                # Detect main symbol start (exact match, not sub-symbols with _0_1 etc)
                if f'(symbol "{symbol_name}"' in line and "_" not in line.split('"')[1].replace(symbol_name, ""):
                    in_main_symbol = True

                # Track last property line in main symbol
                if in_main_symbol and "(property" in line:
                    last_property_idx = i

                # Detect sub-symbol start - this ends the main symbol's property section
                if in_main_symbol and f'(symbol "{symbol_name}_' in line:
                    in_main_symbol = False
                    if not inserted and last_property_idx >= 0:
                        # Insert after last property, maintaining proper structure
                        # We need to handle multi-line properties
                        pass

                result.append(line)

            # Find proper insertion point - after the last property block
            if last_property_idx >= 0:
                # Find the end of the last property (matching closing paren)
                depth = 0
                end_idx = last_property_idx
                for i in range(last_property_idx, len(result)):
                    depth += result[i].count("(") - result[i].count(")")
                    if depth == 0:
                        end_idx = i
                        break

                # Get the next id number
                max_id = 0
                for line in result:
                    id_match = re.search(r'\(id (\d+)\)', line)
                    if id_match:
                        max_id = max(max_id, int(id_match.group(1)))
                new_id = max_id + 1

                # Insert new property after the last property
                new_prop = (
                    f'    (property\n'
                    f'      "{prop_name}"\n'
                    f'      "{prop_value}"\n'
                    f'      (id {new_id})\n'
                    f'      (at 0 0 0)\n'
                    f'      (effects (font (size 1.27 1.27) ) hide)\n'
                    f'    )'
                )
                result.insert(end_idx + 1, new_prop)

            self.content = "\n".join(result)

    def extract_symbol(self, symbol_name: str) -> str:
        """Extract a complete symbol definition including sub-symbols."""
        lines = self.content.split("\n")
        result = []
        depth = 0
        capturing = False

        for line in lines:
            if f'(symbol "{symbol_name}"' in line or f'(symbol "{symbol_name}:' in line:
                capturing = True

            if capturing:
                result.append(line)
                depth += line.count("(") - line.count(")")
                if depth <= 0:
                    capturing = False
                    depth = 0

        return "\n".join(result)

    def remove_symbol(self, symbol_name: str) -> None:
        """Remove a symbol and its sub-symbols from the file."""
        lines = self.content.split("\n")
        result = []
        depth = 0
        skipping = False

        for line in lines:
            if f'(symbol "{symbol_name}"' in line or f'(symbol "{symbol_name}:' in line:
                skipping = True
                depth = 0

            if skipping:
                depth += line.count("(") - line.count(")")
                if depth <= 0:
                    skipping = False
                    depth = 0
                continue

            result.append(line)

        self.content = "\n".join(result)

    def save(self) -> None:
        """Save the content back to file."""
        self.filepath.write_text(self.content)


def get_staging_libs() -> Path:
    """Get and validate KICAD_STAGING_LIBS path."""
    path = os.environ.get("KICAD_STAGING_LIBS")
    if not path:
        error("KICAD_STAGING_LIBS environment variable is not set")
        sys.exit(1)
    staging = Path(path)
    staging.mkdir(parents=True, exist_ok=True)
    return staging


def get_production_libs() -> Path:
    """Get and validate MY_KICAD_LIBS path."""
    path = os.environ.get("MY_KICAD_LIBS")
    if not path:
        error("MY_KICAD_LIBS environment variable is not set")
        sys.exit(1)
    prod = Path(path)
    prod.mkdir(parents=True, exist_ok=True)
    return prod


def cmd_import(args: argparse.Namespace) -> None:
    """Import a part from LCSC."""
    lcsc_id = args.lcsc_id.upper()

    if not re.match(r"^C\d+$", lcsc_id):
        error(f"Invalid LCSC ID format: {lcsc_id}. Expected format: C<number> (e.g., C2040)")
        sys.exit(1)

    staging = get_staging_libs()
    output_base = staging / "easyeda2kicad"

    info(f"Importing part {lcsc_id} from LCSC/EasyEDA...")

    # Run easyeda2kicad
    try:
        subprocess.run(
            ["easyeda2kicad", "--full", f"--lcsc_id={lcsc_id}", f"--output={output_base}", "--overwrite"],
            check=True,
        )
    except subprocess.CalledProcessError:
        error("Failed to import part from LCSC")
        sys.exit(1)
    except FileNotFoundError:
        error("easyeda2kicad not found. Is it installed?")
        sys.exit(1)

    success("Downloaded symbol, footprint, and 3D model from LCSC")

    sym_file = Path(f"{output_base}.kicad_sym")
    if not sym_file.exists():
        error(f"Symbol file not found: {sym_file}")
        sys.exit(1)

    kicad = KicadSymbol(sym_file)
    symbols = kicad.get_symbol_names()

    if not symbols:
        error("No symbols found in downloaded file")
        sys.exit(1)

    mpn = symbols[0]
    info(f"Part MPN: {mpn}")

    # Add LCSC property
    kicad.set_property(mpn, "LCSC", lcsc_id)
    success(f"Added LCSC property: {lcsc_id}")

    # Query Digikey
    info("Querying Digikey API...")
    digikey = DigikeyClient()
    if dk_data := digikey.search(mpn):
        if dk_pn := dk_data.get("DigiKeyPartNumber"):
            kicad.set_property(mpn, "Digikey", dk_pn)
            success(f"Added Digikey PN: {dk_pn}")

        if dk_stock := dk_data.get("QuantityAvailable"):
            kicad.set_property(mpn, "Stock_Digikey", str(dk_stock))
            info(f"Digikey stock: {dk_stock}")

        if dk_ds := dk_data.get("PrimaryDatasheet"):
            kicad.set_property(mpn, "Datasheet", dk_ds)
            success("Added datasheet URL")

        if dk_mfr := dk_data.get("Manufacturer", {}).get("Value"):
            kicad.set_property(mpn, "Manufacturer", dk_mfr)
            success(f"Added manufacturer: {dk_mfr}")

        # Pricing tiers
        for pricing in dk_data.get("StandardPricing", []):
            qty = pricing.get("BreakQuantity")
            price = pricing.get("UnitPrice")
            if qty and price:
                kicad.set_property(mpn, f"Price_{qty}", f"${price}")

    # Query Mouser
    info("Querying Mouser API...")
    mouser = MouserClient()
    if m_data := mouser.search(mpn):
        parts = m_data.get("SearchResults", {}).get("Parts", [])
        if parts:
            part = parts[0]
            if m_pn := part.get("MouserPartNumber"):
                kicad.set_property(mpn, "Mouser", m_pn)
                success(f"Added Mouser PN: {m_pn}")

            if m_avail := part.get("Availability"):
                stock = re.search(r"\d+", m_avail)
                if stock:
                    kicad.set_property(mpn, "Stock_Mouser", stock.group())
                    info(f"Mouser stock: {stock.group()}")

            if m_mfr := part.get("Manufacturer"):
                if not kicad.get_property(mpn, "Manufacturer"):
                    kicad.set_property(mpn, "Manufacturer", m_mfr)
                    success(f"Added manufacturer: {m_mfr}")

    # Add MPN
    kicad.set_property(mpn, "MPN", mpn)
    kicad.save()

    print()
    success(f"Part {lcsc_id} imported successfully to staging!")
    print()
    info("Files created:")
    print(f"  Symbol:    {sym_file}")
    print(f"  Footprint: {output_base}.pretty/")
    print(f"  3D Models: {output_base}.3dshapes/")
    print()
    info("Use 'kicad-parts list' to view staged parts")
    info("Use 'kicad-parts accept' to move to production library")


def cmd_list(args: argparse.Namespace) -> None:
    """List parts in staging."""
    staging = get_staging_libs()
    sym_file = staging / "easyeda2kicad.kicad_sym"

    if not sym_file.exists():
        info("No parts in staging library")
        return

    kicad = KicadSymbol(sym_file)
    symbols = kicad.get_symbol_names()

    if not symbols:
        info("No parts in staging library")
        return

    print(f"{BLUE}Parts in staging library:{NC}")
    print()

    for symbol in sorted(symbols):
        print(f"{GREEN}{symbol}{NC}")

        if args.verbose:
            for prop in ["LCSC", "MPN", "Manufacturer", "Digikey", "Mouser", "Datasheet"]:
                if val := kicad.get_property(symbol, prop):
                    print(f"  {prop}: {val}")
            for prop in ["Price_1", "Price_10", "Price_100", "Stock_Digikey", "Stock_Mouser"]:
                if val := kicad.get_property(symbol, prop):
                    print(f"  {prop}: {val}")
            print()
        else:
            parts = []
            if lcsc := kicad.get_property(symbol, "LCSC"):
                parts.append(f"LCSC:{lcsc}")
            if mfr := kicad.get_property(symbol, "Manufacturer"):
                parts.append(mfr)
            if kicad.get_property(symbol, "Digikey"):
                parts.append("DK")
            if kicad.get_property(symbol, "Mouser"):
                parts.append("M")
            if parts:
                print(f"  {CYAN}{' | '.join(parts)}{NC}")

    print()
    info(f"Total: {len(symbols)} part(s) in staging")


def cmd_accept(args: argparse.Namespace) -> None:
    """Accept parts from staging to production."""
    staging = get_staging_libs()
    production = get_production_libs()

    staging_sym = staging / "easyeda2kicad.kicad_sym"
    staging_pretty = staging / "easyeda2kicad.pretty"
    staging_3d = staging / "easyeda2kicad.3dshapes"

    prod_sym = production / "my_parts.kicad_sym"
    prod_pretty = production / "my_parts.pretty"
    prod_3d = production / "my_parts.3dshapes"

    if not staging_sym.exists():
        info("No parts in staging library")
        return

    kicad = KicadSymbol(staging_sym)
    symbols = kicad.get_symbol_names()

    if not symbols:
        info("No parts in staging library")
        return

    # Determine which parts to accept
    if args.all:
        to_accept = symbols
    elif args.part:
        if args.part not in symbols:
            error(f"Part not found: {args.part}")
            sys.exit(1)
        to_accept = [args.part]
    else:
        # Interactive selection with fzf
        try:
            result = subprocess.run(
                ["fzf", "--multi", "--prompt=Select parts to accept: "],
                input="\n".join(symbols),
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                info("No parts selected")
                return
            to_accept = result.stdout.strip().split("\n")
        except FileNotFoundError:
            error("fzf not found. Specify part name or use --all")
            sys.exit(1)

    # Create production directories
    prod_pretty.mkdir(parents=True, exist_ok=True)
    prod_3d.mkdir(parents=True, exist_ok=True)

    # Initialize production symbol file if needed
    if not prod_sym.exists():
        prod_sym.write_text(
            '(kicad_symbol_lib\n  (version 20231120)\n  (generator "kicad-parts-manager")\n)\n'
        )

    prod_kicad = KicadSymbol(prod_sym)

    for symbol in to_accept:
        info(f"Accepting part: {symbol}")

        # Extract and move symbol
        symbol_content = kicad.extract_symbol(symbol)
        if not symbol_content:
            error(f"Could not extract symbol: {symbol}")
            continue

        # Append to production (before final closing paren)
        content = prod_kicad.content.rstrip()
        if content.endswith(")"):
            content = content[:-1] + symbol_content + "\n)\n"
            prod_kicad.content = content

        kicad.remove_symbol(symbol)
        success("Moved symbol to production library")

        # Move footprint
        fp_file = staging_pretty / f"{symbol}.kicad_mod"
        if fp_file.exists():
            fp_file.rename(prod_pretty / fp_file.name)
            success(f"Moved footprint: {fp_file.name}")
        else:
            # Try to find any footprint
            for fp in staging_pretty.glob("*.kicad_mod"):
                fp.rename(prod_pretty / fp.name)
                success(f"Moved footprint: {fp.name}")
                break

        # Move 3D models
        moved = 0
        for ext in ["wrl", "step", "WRL", "STEP", "stp", "STP"]:
            model = staging_3d / f"{symbol}.{ext}"
            if model.exists():
                model.rename(prod_3d / model.name)
                moved += 1
        # Also move any remaining models
        for model in staging_3d.glob("*"):
            if model.is_file():
                model.rename(prod_3d / model.name)
                moved += 1
        if moved:
            success(f"Moved {moved} 3D model file(s)")

        success(f"Part {symbol} accepted!")

    kicad.save()
    prod_kicad.save()

    print()
    success(f"Done! Parts moved to: {production}")


def cmd_reject(args: argparse.Namespace) -> None:
    """Reject parts from staging."""
    staging = get_staging_libs()

    staging_sym = staging / "easyeda2kicad.kicad_sym"
    staging_pretty = staging / "easyeda2kicad.pretty"
    staging_3d = staging / "easyeda2kicad.3dshapes"

    if args.all:
        warn("This will delete all staged parts!")
        confirm = input("Are you sure? [y/N] ")
        if confirm.lower() != "y":
            info("Cancelled")
            return

        import shutil

        if staging_sym.exists():
            staging_sym.unlink()
        if staging_pretty.exists():
            shutil.rmtree(staging_pretty)
        if staging_3d.exists():
            shutil.rmtree(staging_3d)

        success("Staging cleared!")
        return

    if not staging_sym.exists():
        info("No parts in staging library")
        return

    kicad = KicadSymbol(staging_sym)
    symbols = kicad.get_symbol_names()

    if not symbols:
        info("No parts in staging library")
        return

    # Determine which parts to reject
    if args.part:
        if args.part not in symbols:
            error(f"Part not found: {args.part}")
            sys.exit(1)
        to_reject = [args.part]
    else:
        # Interactive selection with fzf
        try:
            result = subprocess.run(
                ["fzf", "--multi", "--prompt=Select parts to reject: "],
                input="\n".join(symbols),
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                info("No parts selected")
                return
            to_reject = result.stdout.strip().split("\n")
        except FileNotFoundError:
            error("fzf not found. Specify part name or use --all")
            sys.exit(1)

    for symbol in to_reject:
        info(f"Rejecting part: {symbol}")

        kicad.remove_symbol(symbol)
        success("Removed symbol from library")

        # Delete footprint
        fp_file = staging_pretty / f"{symbol}.kicad_mod"
        if fp_file.exists():
            fp_file.unlink()
            success(f"Deleted footprint: {fp_file.name}")

        # Delete 3D models
        deleted = 0
        for ext in ["wrl", "step", "WRL", "STEP", "stp", "STP"]:
            model = staging_3d / f"{symbol}.{ext}"
            if model.exists():
                model.unlink()
                deleted += 1
        if deleted:
            success(f"Deleted {deleted} 3D model file(s)")

        success(f"Part {symbol} rejected!")

    kicad.save()
    print()
    success("Done!")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="KiCad Parts Manager - Import and manage KiCad libraries from LCSC"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # import command
    import_parser = subparsers.add_parser("import", help="Import a part from LCSC")
    import_parser.add_argument("lcsc_id", help="LCSC part number (e.g., C2040)")
    import_parser.set_defaults(func=cmd_import)

    # list command
    list_parser = subparsers.add_parser("list", help="List parts in staging")
    list_parser.add_argument("-v", "--verbose", action="store_true", help="Show detailed metadata")
    list_parser.set_defaults(func=cmd_list)

    # accept command
    accept_parser = subparsers.add_parser("accept", help="Accept parts to production")
    accept_parser.add_argument("part", nargs="?", help="Part name (interactive if omitted)")
    accept_parser.add_argument("--all", action="store_true", help="Accept all parts")
    accept_parser.set_defaults(func=cmd_accept)

    # reject command
    reject_parser = subparsers.add_parser("reject", help="Reject parts from staging")
    reject_parser.add_argument("part", nargs="?", help="Part name (interactive if omitted)")
    reject_parser.add_argument("--all", action="store_true", help="Clear all staging")
    reject_parser.set_defaults(func=cmd_reject)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
