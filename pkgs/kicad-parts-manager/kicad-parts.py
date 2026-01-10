#!/usr/bin/env python3
"""KiCad Parts Manager - Import and manage KiCad libraries from LCSC with metadata enrichment."""

import argparse
import json
import os
import re
import shutil
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
    """Digikey API client with OAuth2 authentication (v4 API)."""

    TOKEN_URL = "https://api.digikey.com/v1/oauth2/token"
    # Product Information API v4
    SEARCH_URL = "https://api.digikey.com/products/v4/search"

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
            warn(
                "Digikey API credentials not set (DIGIKEY_CLIENT_ID, DIGIKEY_CLIENT_SECRET)"
            )
            return None

        token = self.get_token()
        if not token:
            return None

        # Try keyword search first (more flexible for manufacturer part numbers)
        try:
            resp = requests.post(
                f"{self.SEARCH_URL}/keyword",
                headers={
                    "Authorization": f"Bearer {token}",
                    "X-DIGIKEY-Client-Id": self.client_id,
                    "X-DIGIKEY-Locale-Site": "US",
                    "X-DIGIKEY-Locale-Language": "en",
                    "X-DIGIKEY-Locale-Currency": "USD",
                    "Content-Type": "application/json",
                },
                json={
                    "Keywords": mpn,
                    "Limit": 1,
                    "Offset": 0,
                },
                timeout=30,
            )
            if resp.status_code == 200:
                data = resp.json()
                # V4 returns products in a "Products" array
                products = data.get("Products", [])
                if products:
                    return products[0]  # Return first match
                else:
                    warn(f"Digikey: No results for '{mpn}'")
            elif resp.status_code == 404:
                warn(f"Digikey: Part '{mpn}' not found")
            else:
                warn(f"Digikey API returned {resp.status_code}: {resp.text[:200]}")
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
        """Get a property value from a symbol (case-insensitive property name)."""
        # Find the symbol block and extract property
        pattern = rf'\(property\s+"{re.escape(prop_name)}"\s+"([^"]*)"'
        match = re.search(pattern, self.content, re.IGNORECASE)
        return match.group(1) if match else None

    def set_property(self, symbol_name: str, prop_name: str, prop_value: str) -> None:
        """Add or update a property in a symbol (in main symbol, not sub-symbols)."""
        prop_value = prop_value.replace("\\", "\\\\").replace('"', '\\"')

        # Check if property already exists - handle both single-line and multi-line formats
        # Single-line: (property "Name" "Value" ...)
        # Multi-line:  (property\n  "Name"\n  "Value"\n  ...)
        # Use case-insensitive matching for property names
        lines = self.content.split("\n")
        found_prop = False
        in_target_prop = False
        prop_name_found = False
        actual_prop_name = prop_name  # Store the actual name found in file

        for i, line in enumerate(lines):
            # Start of a property block
            if "(property" in line:
                # Check if property name is on same line (case-insensitive)
                match = re.search(r'\(property\s+"([^"]+)"', line, re.IGNORECASE)
                if match and match.group(1).lower() == prop_name.lower():
                    in_target_prop = True
                    prop_name_found = True
                    actual_prop_name = match.group(1)
                elif "(property" in line:
                    # Multi-line format - check next line for property name
                    in_target_prop = False
                    prop_name_found = False

            # Check for property name on its own line (multi-line format)
            if not prop_name_found and line.strip().startswith('"'):
                match = re.match(r'\s*"([^"]+)"', line)
                if match and match.group(1).lower() == prop_name.lower():
                    in_target_prop = True
                    prop_name_found = True
                    actual_prop_name = match.group(1)
                    continue

            # If we're in the target property, look for the value line
            if in_target_prop and prop_name_found:
                # Value line - starts with " and contains the value
                stripped = line.strip()
                if stripped.startswith('"') and stripped.endswith('"'):
                    # This is the value line - replace it
                    indent = line[: len(line) - len(line.lstrip())]
                    lines[i] = f'{indent}"{prop_value}"'
                    found_prop = True
                    break
                elif re.search(rf'"{re.escape(actual_prop_name)}"', line, re.IGNORECASE):
                    # Single-line format: (property "Name" "Value" ...)
                    pattern = rf'(\(property\s+"{re.escape(actual_prop_name)}"\s+")[^"]*(")'
                    lines[i] = re.sub(pattern, rf"\g<1>{prop_value}\g<2>", line, flags=re.IGNORECASE)
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
                if f'(symbol "{symbol_name}"' in line and "_" not in line.split('"')[
                    1
                ].replace(symbol_name, ""):
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
                    id_match = re.search(r"\(id (\d+)\)", line)
                    if id_match:
                        max_id = max(max_id, int(id_match.group(1)))
                new_id = max_id + 1

                # Insert new property after the last property
                new_prop = (
                    f"    (property\n"
                    f'      "{prop_name}"\n'
                    f'      "{prop_value}"\n'
                    f"      (id {new_id})\n"
                    f"      (at 0 0 0)\n"
                    f"      (effects (font (size 1.27 1.27) ) hide)\n"
                    f"    )"
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
    """Get and validate KICAD_MY_LIBS path."""
    path = os.environ.get("KICAD_MY_LIBS")
    if not path:
        error("KICAD_MY_LIBS environment variable is not set")
        sys.exit(1)
    prod = Path(path)
    prod.mkdir(parents=True, exist_ok=True)
    return prod


def get_kicad_config_dir() -> Path:
    """Get KiCad config directory."""
    path = os.environ.get("KICAD_CONFIG_DIR")
    if not path:
        error("KICAD_CONFIG_DIR environment variable is not set")
        sys.exit(1)
    return Path(path)


def ensure_lib_in_table(table_file: Path, lib_name: str, lib_uri: str, lib_type: str = "KiCad") -> bool:
    """Ensure a library is in the library table. Returns True if added."""
    if not table_file.exists():
        # Create new table
        if "sym" in table_file.name:
            table_file.write_text(f'(sym_lib_table\n  (version 7)\n  (lib (name "{lib_name}")(type "{lib_type}")(uri "{lib_uri}")(options "")(descr "Custom library"))\n)\n')
        else:
            table_file.write_text(f'(fp_lib_table\n  (version 7)\n  (lib (name "{lib_name}")(type "{lib_type}")(uri "{lib_uri}")(options "")(descr "Custom library"))\n)\n')
        return True

    content = table_file.read_text()

    # Check if library already exists
    if f'(name "{lib_name}")' in content:
        return False

    # Add library entry before closing paren
    new_entry = f'  (lib (name "{lib_name}")(type "{lib_type}")(uri "{lib_uri}")(options "")(descr "Custom library"))\n'
    content = content.rstrip()
    if content.endswith(")"):
        content = content[:-1] + new_entry + ")\n"
        table_file.write_text(content)
        return True

    return False


def ensure_kicad_env_var(config_dir: Path, var_name: str, var_value: str) -> bool:
    """Ensure an environment variable is set in KiCad's kicad_common.json."""
    common_file = config_dir / "kicad_common.json"

    if not common_file.exists():
        # Create minimal config with the env var
        config = {"environment": {"vars": {var_name: var_value}}}
        common_file.write_text(json.dumps(config, indent=2))
        return True

    try:
        config = json.loads(common_file.read_text())
    except json.JSONDecodeError:
        warn(f"Could not parse {common_file}")
        return False

    # Ensure environment.vars exists and is a dict
    if "environment" not in config:
        config["environment"] = {}
    if "vars" not in config["environment"] or config["environment"]["vars"] is None:
        config["environment"]["vars"] = {}

    # Check if already set
    if var_name in config["environment"]["vars"]:
        return False

    # Add the variable
    config["environment"]["vars"][var_name] = var_value
    common_file.write_text(json.dumps(config, indent=2))
    return True


def register_staging_libraries() -> None:
    """Register staging libraries in KiCad's library tables."""
    config_dir = get_kicad_config_dir()
    staging = get_staging_libs()

    # Ensure KICAD_STAGING_LIBS is set in KiCad's environment
    if ensure_kicad_env_var(config_dir, "KICAD_STAGING_LIBS", str(staging)):
        success("Added KICAD_STAGING_LIBS to KiCad configure paths")
    else:
        info("KICAD_STAGING_LIBS already in KiCad configure paths")

    sym_table = config_dir / "sym-lib-table"
    fp_table = config_dir / "fp-lib-table"

    # Use KICAD_STAGING_LIBS variable so paths are portable
    sym_uri = "${KICAD_STAGING_LIBS}/_staging.kicad_sym"
    fp_uri = "${KICAD_STAGING_LIBS}/_staging.pretty"

    if ensure_lib_in_table(sym_table, "_staging", sym_uri):
        success("Added _staging to symbol library table")
    else:
        info("_staging already in symbol library table")

    if ensure_lib_in_table(fp_table, "_staging", fp_uri):
        success("Added _staging to footprint library table")
    else:
        info("_staging already in footprint library table")


def register_libraries(lib_base: str) -> None:
    """Register symbol and footprint libraries in KiCad's library tables."""
    config_dir = get_kicad_config_dir()
    production = get_production_libs()

    # Ensure KICAD_MY_LIBS is set in KiCad's environment
    if ensure_kicad_env_var(config_dir, "KICAD_MY_LIBS", str(production)):
        success("Added KICAD_MY_LIBS to KiCad configure paths")
    else:
        info("KICAD_MY_LIBS already in KiCad configure paths")

    sym_table = config_dir / "sym-lib-table"
    fp_table = config_dir / "fp-lib-table"

    # Use KICAD_MY_LIBS variable so paths are portable
    sym_uri = f"${{KICAD_MY_LIBS}}/{lib_base}.kicad_sym"
    fp_uri = f"${{KICAD_MY_LIBS}}/{lib_base}.pretty"

    if ensure_lib_in_table(sym_table, lib_base, sym_uri):
        success(f"Added {lib_base} to symbol library table")
    else:
        info(f"{lib_base} already in symbol library table")

    if ensure_lib_in_table(fp_table, lib_base, fp_uri):
        success(f"Added {lib_base} to footprint library table")
    else:
        info(f"{lib_base} already in footprint library table")


# Standard KiCad library categories for autocomplete
KICAD_LIBRARY_CATEGORIES = [
    "Amplifier_Audio",
    "Amplifier_Buffer",
    "Amplifier_Current",
    "Amplifier_Difference",
    "Amplifier_Instrumentation",
    "Amplifier_Operational",
    "Amplifier_Video",
    "Analog",
    "Analog_ADC",
    "Analog_DAC",
    "Analog_Switch",
    "Audio",
    "Battery",
    "Comparator",
    "Connector",
    "Connector_Generic",
    "Converter_ACDC",
    "Converter_DCDC",
    "Device",
    "Diode",
    "Diode_Bridge",
    "Display_Character",
    "Driver_Display",
    "Driver_FET",
    "Driver_LED",
    "Driver_Motor",
    "Driver_Relay",
    "DSP_Microchip_DSPIC33",
    "Filter",
    "FPGA_Lattice",
    "FPGA_Xilinx",
    "GPS",
    "Graphic",
    "Interface",
    "Interface_CAN_LIN",
    "Interface_CurrentLoop",
    "Interface_Ethernet",
    "Interface_Expansion",
    "Interface_HID",
    "Interface_LineDriver",
    "Interface_Optical",
    "Interface_Telecom",
    "Interface_UART",
    "Interface_USB",
    "Isolator",
    "Jumper",
    "LED",
    "Logic",
    "MCU_Espressif",
    "MCU_Microchip_ATmega",
    "MCU_Microchip_ATtiny",
    "MCU_Microchip_PIC",
    "MCU_Nordic",
    "MCU_NXP",
    "MCU_Raspberry_Pi",
    "MCU_ST_STM32",
    "MCU_Texas",
    "Memory_Controller",
    "Memory_EEPROM",
    "Memory_Flash",
    "Memory_RAM",
    "Memory_ROM",
    "Motor",
    "Oscillator",
    "Power_Management",
    "Power_Protection",
    "Power_Supervisor",
    "Reference_Current",
    "Reference_Voltage",
    "Regulator_Controller",
    "Regulator_Current",
    "Regulator_Linear",
    "Regulator_Switching",
    "Relay",
    "Relay_SolidState",
    "RF",
    "RF_Amplifier",
    "RF_Bluetooth",
    "RF_GPS",
    "RF_Mixer",
    "RF_Module",
    "RF_Switch",
    "RF_WiFi",
    "RF_ZigBee",
    "Sensor",
    "Sensor_Audio",
    "Sensor_Current",
    "Sensor_Gas",
    "Sensor_Humidity",
    "Sensor_Magnetic",
    "Sensor_Motion",
    "Sensor_Optical",
    "Sensor_Pressure",
    "Sensor_Proximity",
    "Sensor_Temperature",
    "Sensor_Touch",
    "Sensor_Voltage",
    "Switch",
    "Timer",
    "Timer_PLL",
    "Timer_RTC",
    "Transformer",
    "Transistor_Array",
    "Transistor_BJT",
    "Transistor_FET",
    "Transistor_IGBT",
    "Triac_Thyristor",
    "Valve",
    "Video",
]


def prompt_library_name() -> str:
    """Prompt user for library name with autocomplete from KiCad categories."""
    try:
        result = subprocess.run(
            ["fzf", "--prompt=Select library category: ", "--print-query", "--select-1", "--exit-0"],
            input="\n".join(KICAD_LIBRARY_CATEGORIES),
            capture_output=True,
            text=True,
        )
        lines = result.stdout.strip().split("\n")
        # fzf --print-query returns query on first line, selection on second
        if len(lines) >= 2 and lines[1]:
            return lines[1]  # User selected from list
        elif lines[0]:
            return lines[0]  # User typed custom name
        else:
            error("No library selected")
            sys.exit(1)
    except FileNotFoundError:
        # Fallback to simple input if fzf not available
        print(f"{CYAN}Available categories:{NC}")
        for cat in KICAD_LIBRARY_CATEGORIES[:20]:
            print(f"  {cat}")
        print("  ...")
        lib_name = input(f"{BLUE}Enter library name: {NC}").strip()
        if not lib_name:
            error("No library name provided")
            sys.exit(1)
        return lib_name


def cmd_import(args: argparse.Namespace) -> None:
    """Import a part from LCSC to staging."""
    lcsc_id = args.lcsc_id.upper()

    if not re.match(r"^C\d+$", lcsc_id):
        error(
            f"Invalid LCSC ID format: {lcsc_id}. Expected format: C<number> (e.g., C2040)"
        )
        sys.exit(1)

    staging = get_staging_libs()

    info(f"Importing part {lcsc_id} from LCSC/EasyEDA...")

    # Run easyeda2kicad (note: it ignores the lib name and always uses "easyeda2kicad")
    cmd = [
        "easyeda2kicad",
        "--full",
        "--lcsc_id",
        lcsc_id,
        "--output",
        str(staging / "easyeda2kicad"),
        "--overwrite",
    ]
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError:
        error("Failed to import part from LCSC")
        sys.exit(1)
    except FileNotFoundError:
        error("easyeda2kicad not found. Is it installed?")
        sys.exit(1)

    success("Downloaded symbol, footprint, and 3D model from LCSC")

    # easyeda2kicad outputs to easyeda2kicad.* - rename to _staging.*
    easyeda_sym = staging / "easyeda2kicad.kicad_sym"
    easyeda_pretty = staging / "easyeda2kicad.pretty"
    easyeda_3d = staging / "easyeda2kicad.3dshapes"

    sym_file = staging / "_staging.kicad_sym"
    staging_pretty = staging / "_staging.pretty"
    staging_3d = staging / "_staging.3dshapes"

    # Move symbol file (merge if _staging already exists)
    if easyeda_sym.exists():
        if sym_file.exists():
            existing = KicadSymbol(sym_file)
            new_symbols = KicadSymbol(easyeda_sym)
            for symbol in new_symbols.get_symbol_names():
                symbol_content = new_symbols.extract_symbol(symbol)
                if symbol_content:
                    content = existing.content.rstrip()
                    if content.endswith(")"):
                        content = content[:-1] + symbol_content + "\n)\n"
                        existing.content = content
            existing.save()
            easyeda_sym.unlink()
        else:
            easyeda_sym.rename(sym_file)

    # Move footprints
    if easyeda_pretty.exists():
        staging_pretty.mkdir(parents=True, exist_ok=True)
        for fp in easyeda_pretty.glob("*.kicad_mod"):
            fp.rename(staging_pretty / fp.name)
        shutil.rmtree(easyeda_pretty)

    # Move 3D models
    if easyeda_3d.exists():
        staging_3d.mkdir(parents=True, exist_ok=True)
        for model in easyeda_3d.glob("*"):
            if model.is_file():
                model.rename(staging_3d / model.name)
        shutil.rmtree(easyeda_3d)
    if not sym_file.exists():
        error(f"Symbol file not found: {sym_file}")
        sys.exit(1)

    kicad = KicadSymbol(sym_file)
    symbols = kicad.get_symbol_names()

    if not symbols:
        error("No symbols found in downloaded file")
        sys.exit(1)

    symbol_name = symbols[0]
    info(f"Symbol name: {symbol_name}")

    # Clean up MPN for API searches - remove EasyEDA suffixes like _0_1, _0, etc.
    # These are internal KiCad sub-symbol identifiers, not part of the actual MPN
    mpn = re.sub(r"_\d+(_\d+)?$", "", symbol_name)
    if mpn != symbol_name:
        info(f"Cleaned MPN for API search: {mpn}")

    # Add LCSC property
    kicad.set_property(symbol_name, "LCSC", lcsc_id)
    success(f"Added LCSC property: {lcsc_id}")

    # Query Digikey
    info(f"Querying Digikey API for: {mpn}")
    digikey = DigikeyClient()
    dk_data = digikey.search(mpn)
    if dk_data:
        # V4 API field names
        if dk_pn := dk_data.get("DigiKeyProductNumber"):
            kicad.set_property(symbol_name, "Digikey", dk_pn)
            success(f"Added Digikey PN: {dk_pn}")

        if dk_stock := dk_data.get("QuantityAvailable"):
            kicad.set_property(symbol_name, "Stock_Digikey", str(dk_stock))
            info(f"Digikey stock: {dk_stock}")

        # V4 uses DatasheetUrl instead of PrimaryDatasheet
        if dk_ds := dk_data.get("DatasheetUrl"):
            kicad.set_property(symbol_name, "Datasheet", dk_ds)
            success("Added datasheet URL")

        # V4 uses Manufacturer.Name instead of Manufacturer.Value
        if dk_mfr := dk_data.get("Manufacturer", {}).get("Name"):
            kicad.set_property(symbol_name, "Manufacturer", dk_mfr)
            success(f"Added manufacturer: {dk_mfr}")

        # Pricing tiers (same structure in v4)
        for pricing in dk_data.get("StandardPricing", []):
            qty = pricing.get("BreakQuantity")
            price = pricing.get("UnitPrice")
            if qty and price:
                kicad.set_property(symbol_name, f"Price_{qty}", f"${price}")

    # Query Mouser
    info(f"Querying Mouser API for: {mpn}")
    mouser = MouserClient()
    if m_data := mouser.search(mpn):
        parts = m_data.get("SearchResults", {}).get("Parts", [])
        if parts:
            part = parts[0]
            if m_pn := part.get("MouserPartNumber"):
                kicad.set_property(symbol_name, "Mouser", m_pn)
                success(f"Added Mouser PN: {m_pn}")

            if m_avail := part.get("Availability"):
                stock = re.search(r"\d+", m_avail)
                if stock:
                    kicad.set_property(symbol_name, "Stock_Mouser", stock.group())
                    info(f"Mouser stock: {stock.group()}")

            if m_mfr := part.get("Manufacturer"):
                if not kicad.get_property(symbol_name, "Manufacturer"):
                    kicad.set_property(symbol_name, "Manufacturer", m_mfr)
                    success(f"Added manufacturer: {m_mfr}")

    # Add MPN (use the cleaned MPN, not the symbol name)
    kicad.set_property(symbol_name, "MPN", mpn)
    kicad.save()

    # Register staging libraries in KiCad
    register_staging_libraries()

    print()
    success(f"Part {lcsc_id} ({mpn}) imported to staging!")
    print()
    info("Files created:")
    print(f"  Symbol:    {sym_file}")
    print(f"  Footprint: {staging_pretty}/")
    print(f"  3D Models: {staging_3d}/")
    print()
    info("Use 'kicad-parts list --staging' to view staged parts")
    info("Use 'kicad-parts accept' to move to production library")


def cmd_accept(args: argparse.Namespace) -> None:
    """Move staged parts to production library."""
    staging = get_staging_libs()
    production = get_production_libs()

    sym_file = staging / "_staging.kicad_sym"
    staging_pretty = staging / "_staging.pretty"
    staging_3d = staging / "_staging.3dshapes"

    if not sym_file.exists():
        error("No staged parts found")
        info(f"Import parts first with: kicad-parts import <LCSC_ID>")
        sys.exit(1)

    kicad = KicadSymbol(sym_file)
    all_symbols = kicad.get_symbol_names()

    if not all_symbols:
        error("No symbols found in staging")
        sys.exit(1)

    # Filter symbols if a part name/pattern is specified
    if args.part:
        pattern = args.part.upper()
        symbols = [s for s in all_symbols if pattern in s.upper() or
                   (kicad.get_property(s, "LCSC") or "").upper() == pattern]
        if not symbols:
            error(f"No staged parts match '{args.part}'")
            info(f"Available: {', '.join(all_symbols)}")
            sys.exit(1)
    else:
        symbols = all_symbols

    # Show what will be accepted
    info(f"Parts to accept: {', '.join(symbols)}")

    # Prompt for library category
    if args.library:
        lib_name = args.library
    else:
        lib_name = prompt_library_name()

    lib_base = f"{lib_name}-JH"
    prod_sym = production / f"{lib_base}.kicad_sym"
    prod_pretty = production / f"{lib_base}.pretty"
    prod_3d = production / f"{lib_base}.3dshapes"

    info(f"Moving to production library: {lib_base}")

    # Create production directories
    prod_pretty.mkdir(parents=True, exist_ok=True)
    prod_3d.mkdir(parents=True, exist_ok=True)

    # Initialize production symbol file if needed
    if not prod_sym.exists():
        prod_sym.write_text(
            '(kicad_symbol_lib\n  (version 20231120)\n  (generator "kicad-parts-manager")\n  (generator_version "1.0")\n)\n'
        )
        success(f"Created new library: {prod_sym.name}")

    prod_kicad = KicadSymbol(prod_sym)

    # Extract and add each symbol to production
    for mpn in symbols:
        symbol_content = kicad.extract_symbol(mpn)
        if symbol_content:
            content = prod_kicad.content.rstrip()
            if content.endswith(")"):
                content = content[:-1] + symbol_content + "\n)\n"
                prod_kicad.content = content
            success(f"Added symbol: {mpn}")

    prod_kicad.save()

    # Move footprints
    if staging_pretty.exists():
        for fp in staging_pretty.glob("*.kicad_mod"):
            fp.rename(prod_pretty / fp.name)
            success(f"Moved footprint: {fp.name}")

    # Move 3D models
    if staging_3d.exists():
        moved = 0
        for model in staging_3d.glob("*"):
            if model.is_file():
                model.rename(prod_3d / model.name)
                moved += 1
        if moved:
            success(f"Moved {moved} 3D model file(s)")

    # Clean up staging - remove accepted symbols
    remaining_symbols = [s for s in all_symbols if s not in symbols]
    if remaining_symbols:
        # Keep staging file with remaining symbols
        for accepted in symbols:
            kicad.remove_symbol(accepted)
        kicad.save()
        info(f"Remaining staged: {', '.join(remaining_symbols)}")
    else:
        # All symbols accepted - clean up completely
        if sym_file.exists():
            sym_file.unlink()
        if staging_pretty.exists():
            shutil.rmtree(staging_pretty)
        if staging_3d.exists():
            shutil.rmtree(staging_3d)

    # Register libraries in KiCad's library tables
    register_libraries(lib_base)

    print()
    success(f"Parts moved to production library!")
    print()
    info("Files updated:")
    print(f"  Symbol:    {prod_sym}")
    print(f"  Footprint: {prod_pretty}/")
    print(f"  3D Models: {prod_3d}/")
    print()
    info(f"Library '{lib_base}' is ready to use in KiCad")


def cmd_list(args: argparse.Namespace) -> None:
    """List parts in production or staging libraries."""
    if args.staging:
        # List staged parts
        staging = get_staging_libs()
        sym_file = staging / "_staging.kicad_sym"

        if not sym_file.exists():
            info("No staged parts")
            info(f"Import parts with: kicad-parts import <LCSC_ID>")
            return

        kicad = KicadSymbol(sym_file)
        symbols = kicad.get_symbol_names()

        if not symbols:
            info("No staged parts")
            return

        print(f"{BLUE}━━━ Staged Parts ━━━{NC}")
        print()
        for symbol in sorted(symbols):
            print(f"  {GREEN}{symbol}{NC}")
            if args.verbose:
                for prop in ["LCSC", "MPN", "Manufacturer"]:
                    if val := kicad.get_property(symbol, prop):
                        print(f"    {prop}: {val}")
        print()
        info(f"Total: {len(symbols)} staged part(s)")
        info("Use 'kicad-parts accept' to move to production")
        return

    production = get_production_libs()

    # Find all *-JH.kicad_sym libraries
    lib_files = sorted(production.glob("*-JH.kicad_sym"))

    if not lib_files:
        info("No parts libraries found")
        info(f"Libraries are stored in: {production}")
        return

    total_parts = 0

    for lib_file in lib_files:
        lib_name = lib_file.stem  # e.g., "Connector-JH"

        kicad = KicadSymbol(lib_file)
        symbols = kicad.get_symbol_names()

        if not symbols:
            continue

        print(f"{BLUE}━━━ {lib_name} ━━━{NC}")
        print()

        for symbol in sorted(symbols):
            print(f"  {GREEN}{symbol}{NC}")

            if args.verbose:
                for prop in [
                    "LCSC",
                    "MPN",
                    "Manufacturer",
                    "Digikey",
                    "Mouser",
                    "Datasheet",
                ]:
                    if val := kicad.get_property(symbol, prop):
                        print(f"    {prop}: {val}")
                for prop in [
                    "Price_1",
                    "Price_10",
                    "Price_100",
                    "Stock_Digikey",
                    "Stock_Mouser",
                ]:
                    if val := kicad.get_property(symbol, prop):
                        print(f"    {prop}: {val}")
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
                    print(f"    {CYAN}{' | '.join(parts)}{NC}")

        total_parts += len(symbols)
        print()

    info(f"Total: {total_parts} part(s) across {len(lib_files)} library/libraries")


def cmd_delete(args: argparse.Namespace) -> None:
    """Delete parts from production libraries."""
    production = get_production_libs()

    # Find all libraries
    lib_files = sorted(production.glob("*-JH.kicad_sym"))

    if not lib_files:
        info("No parts libraries found")
        return

    # Build a list of all parts across all libraries
    all_parts: list[tuple[str, Path, str]] = []  # (display_name, lib_path, symbol_name)

    for lib_file in lib_files:
        lib_name = lib_file.stem
        kicad = KicadSymbol(lib_file)
        for symbol in kicad.get_symbol_names():
            all_parts.append((f"{lib_name}/{symbol}", lib_file, symbol))

    if not all_parts:
        info("No parts found in libraries")
        return

    # Filter by library if specified
    if args.library:
        lib_filter = args.library if args.library.endswith("-JH") else f"{args.library}-JH"
        all_parts = [(d, l, s) for d, l, s in all_parts if l.stem == lib_filter]
        if not all_parts:
            error(f"No parts found in library: {lib_filter}")
            sys.exit(1)

    # Determine which parts to delete
    if args.part:
        # Find part by name
        matches = [(d, l, s) for d, l, s in all_parts if s == args.part or d == args.part]
        if not matches:
            error(f"Part not found: {args.part}")
            sys.exit(1)
        to_delete = matches
    else:
        # Interactive selection with fzf
        try:
            result = subprocess.run(
                ["fzf", "--multi", "--prompt=Select parts to delete: "],
                input="\n".join(d for d, _, _ in all_parts),
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                info("No parts selected")
                return
            selected = result.stdout.strip().split("\n")
            to_delete = [(d, l, s) for d, l, s in all_parts if d in selected]
        except FileNotFoundError:
            error("fzf not found. Specify part name with -l LIBRARY PART")
            sys.exit(1)

    # Confirm deletion
    print(f"{YELLOW}Parts to delete:{NC}")
    for display, _, _ in to_delete:
        print(f"  {display}")
    print()
    confirm = input(f"Delete {len(to_delete)} part(s)? [y/N] ")
    if confirm.lower() != "y":
        info("Cancelled")
        return

    # Group by library
    by_library: dict[Path, list[str]] = {}
    for _, lib_path, symbol in to_delete:
        by_library.setdefault(lib_path, []).append(symbol)

    for lib_path, symbols in by_library.items():
        lib_name = lib_path.stem
        kicad = KicadSymbol(lib_path)
        pretty_dir = production / f"{lib_name}.pretty"
        shapes_dir = production / f"{lib_name}.3dshapes"

        for symbol in symbols:
            info(f"Deleting {lib_name}/{symbol}...")

            kicad.remove_symbol(symbol)

            # Delete footprint
            fp_file = pretty_dir / f"{symbol}.kicad_mod"
            if fp_file.exists():
                fp_file.unlink()
                success(f"Deleted footprint: {fp_file.name}")

            # Delete 3D models
            deleted = 0
            for ext in ["wrl", "step", "WRL", "STEP", "stp", "STP"]:
                model = shapes_dir / f"{symbol}.{ext}"
                if model.exists():
                    model.unlink()
                    deleted += 1
            if deleted:
                success(f"Deleted {deleted} 3D model file(s)")

        kicad.save()

    print()
    success(f"Deleted {len(to_delete)} part(s)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="KiCad Parts Manager - Import and manage KiCad libraries from LCSC"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # import command
    import_parser = subparsers.add_parser("import", help="Import a part from LCSC to staging")
    import_parser.add_argument("lcsc_id", help="LCSC part number (e.g., C2040)")
    import_parser.set_defaults(func=cmd_import)

    # accept command
    accept_parser = subparsers.add_parser("accept", help="Move staged parts to production library")
    accept_parser.add_argument(
        "part", nargs="?",
        help="Part name or LCSC number to accept (accepts all if omitted)"
    )
    accept_parser.add_argument(
        "-l", "--library",
        help="Library category (e.g., 'Connector', 'MCU_ST_STM32'). Prompts interactively if omitted."
    )
    accept_parser.set_defaults(func=cmd_accept)

    # list command
    list_parser = subparsers.add_parser("list", help="List parts in all libraries")
    list_parser.add_argument(
        "-v", "--verbose", action="store_true", help="Show detailed metadata"
    )
    list_parser.add_argument(
        "-s", "--staging", action="store_true", help="List staged parts instead of production"
    )
    list_parser.set_defaults(func=cmd_list)

    # delete command (replaces reject)
    delete_parser = subparsers.add_parser("delete", help="Delete parts from libraries")
    delete_parser.add_argument(
        "part", nargs="?", help="Part name (interactive if omitted)"
    )
    delete_parser.add_argument(
        "-l", "--library", help="Library name (e.g., 'Connector-JH')"
    )
    delete_parser.set_defaults(func=cmd_delete)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
