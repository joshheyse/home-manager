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
from kiutils.symbol import SymbolLib, Symbol
from kiutils.items.common import Property, Effects, Font, Position

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


def get_symbol_property(symbol: Symbol, prop_name: str) -> Optional[str]:
    """Get a property value from a symbol (case-insensitive)."""
    for prop in symbol.properties:
        if prop.key.lower() == prop_name.lower():
            return prop.value
    return None


def set_symbol_property(symbol: Symbol, prop_name: str, prop_value: str, hidden: bool = True) -> None:
    """Add or update a property in a symbol."""
    # Check if property exists (case-insensitive)
    for prop in symbol.properties:
        if prop.key.lower() == prop_name.lower():
            prop.value = prop_value
            # Also ensure visibility is set correctly
            if prop.effects:
                prop.effects.hide = hidden
            return

    # Add new property (hidden by default)
    new_prop = Property(
        key=prop_name,
        value=prop_value,
        effects=Effects(font=Font(width=1.27, height=1.27), hide=hidden),
        position=Position(X=0, Y=0, angle=0),
    )
    symbol.properties.append(new_prop)


# Properties that should be visible on schematic
VISIBLE_PROPERTIES = {"Reference", "Value"}


def normalize_symbol_visibility(symbol: Symbol) -> None:
    """Ensure only Reference and Value properties are visible, hide all others."""
    for prop in symbol.properties:
        should_be_visible = prop.key in VISIBLE_PROPERTIES
        if prop.effects:
            prop.effects.hide = not should_be_visible


def update_footprint_3d_paths(footprint_dir: Path, lib_env_var: str, lib_name: str) -> None:
    """Update 3D model paths in all footprints in a directory.

    Uses text replacement to avoid kiutils corrupting arc geometry.

    Args:
        footprint_dir: Directory containing .kicad_mod files
        lib_env_var: Environment variable for the library path (e.g., KICAD_STAGING_LIBS)
        lib_name: Library name for the 3dshapes folder (e.g., _staging or Connector_USB-JH)
    """
    if not footprint_dir.exists():
        return

    for fp_file in footprint_dir.glob("*.kicad_mod"):
        try:
            content = fp_file.read_text()
            # Match (model "path/to/file.ext") and replace with env var path
            # Keeps just the filename and builds new path
            def replace_path(match: re.Match) -> str:
                old_path = match.group(1)
                filename = Path(old_path).name
                return f'(model "${{{lib_env_var}}}/{lib_name}.3dshapes/{filename}"'

            new_content = re.sub(r'\(model\s+"([^"]+)"', replace_path, content)
            if new_content != content:
                fp_file.write_text(new_content)
        except Exception as e:
            warn(f"Failed to update 3D paths in {fp_file.name}: {e}")


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


# Standard KiCad library categories for autocomplete (from KiCad 9 installation)
KICAD_LIBRARY_CATEGORIES = [
    "4xxx",
    "4xxx_IEEE",
    "74xGxx",
    "74xx",
    "74xx_IEEE",
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
    "Battery_Management",
    "Buffer",
    "Comparator",
    "Connector",
    "Connector_Audio",
    "Connector_Generic",
    "Connector_Generic_MountingPin",
    "Connector_Generic_Shielded",
    "Converter_ACDC",
    "Converter_DCDC",
    "CPLD_Altera",
    "CPLD_Microchip",
    "CPLD_Renesas",
    "CPLD_Xilinx",
    "CPU",
    "CPU_NXP_6800",
    "CPU_NXP_68000",
    "CPU_NXP_IMX",
    "CPU_PowerPC",
    "Device",
    "Diode",
    "Diode_Bridge",
    "Diode_Laser",
    "Display_Character",
    "Display_Graphic",
    "Driver_Display",
    "Driver_FET",
    "Driver_Haptic",
    "Driver_LED",
    "Driver_Motor",
    "Driver_Relay",
    "Driver_TEC",
    "DSP_AnalogDevices",
    "DSP_Freescale",
    "DSP_Microchip_DSPIC33",
    "DSP_Motorola",
    "DSP_Texas",
    "Fiber_Optic",
    "Filter",
    "FPGA_CologneChip_GateMate",
    "FPGA_Efinix_Trion",
    "FPGA_Lattice",
    "FPGA_Microsemi",
    "FPGA_Xilinx",
    "FPGA_Xilinx_Artix7",
    "FPGA_Xilinx_Kintex7",
    "FPGA_Xilinx_Spartan6",
    "FPGA_Xilinx_Virtex5",
    "FPGA_Xilinx_Virtex6",
    "FPGA_Xilinx_Virtex7",
    "GPU",
    "Graphic",
    "Interface",
    "Interface_CAN_LIN",
    "Interface_CurrentLoop",
    "Interface_Ethernet",
    "Interface_Expansion",
    "Interface_HDMI",
    "Interface_HID",
    "Interface_LineDriver",
    "Interface_Optical",
    "Interface_Telecom",
    "Interface_UART",
    "Interface_USB",
    "Isolator",
    "Isolator_Analog",
    "Jumper",
    "LED",
    "Logic_LevelTranslator",
    "Logic_Programmable",
    "MCU_AnalogDevices",
    "MCU_Cypress",
    "MCU_Dialog",
    "MCU_Espressif",
    "MCU_Intel",
    "MCU_Microchip_8051",
    "MCU_Microchip_ATmega",
    "MCU_Microchip_ATtiny",
    "MCU_Microchip_AVR",
    "MCU_Microchip_AVR_Dx",
    "MCU_Microchip_PIC10",
    "MCU_Microchip_PIC12",
    "MCU_Microchip_PIC16",
    "MCU_Microchip_PIC18",
    "MCU_Microchip_PIC24",
    "MCU_Microchip_PIC32",
    "MCU_Microchip_SAMA",
    "MCU_Microchip_SAMD",
    "MCU_Microchip_SAME",
    "MCU_Microchip_SAML",
    "MCU_Microchip_SAMV",
    "MCU_Module",
    "MCU_Nordic",
    "MCU_NXP_ColdFire",
    "MCU_NXP_HC11",
    "MCU_NXP_HC12",
    "MCU_NXP_HCS12",
    "MCU_NXP_Kinetis",
    "MCU_NXP_LPC",
    "MCU_NXP_MAC7100",
    "MCU_NXP_MCore",
    "MCU_NXP_NTAG",
    "MCU_NXP_S08",
    "MCU_Parallax",
    "MCU_Puya",
    "MCU_RaspberryPi",
    "MCU_Renesas_Synergy_S1",
    "MCU_SiFive",
    "MCU_SiliconLabs",
    "MCU_ST_STM32C0",
    "MCU_ST_STM32F0",
    "MCU_ST_STM32F1",
    "MCU_ST_STM32F2",
    "MCU_ST_STM32F3",
    "MCU_ST_STM32F4",
    "MCU_ST_STM32F7",
    "MCU_ST_STM32G0",
    "MCU_ST_STM32G4",
    "MCU_ST_STM32H5",
    "MCU_ST_STM32H7",
    "MCU_ST_STM32L0",
    "MCU_ST_STM32L1",
    "MCU_ST_STM32L4",
    "MCU_ST_STM32L5",
    "MCU_ST_STM32MP1",
    "MCU_ST_STM32U0",
    "MCU_ST_STM32U5",
    "MCU_ST_STM32WB",
    "MCU_ST_STM32WL",
    "MCU_ST_STM8",
    "MCU_STC",
    "MCU_Texas",
    "MCU_Texas_MSP430",
    "MCU_Texas_SimpleLink",
    "MCU_Trident",
    "MCU_WCH_CH32V0",
    "MCU_WCH_CH32V2",
    "MCU_WCH_CH32V3",
    "MCU_WCH_CH32X0",
    "Mechanical",
    "Memory_EEPROM",
    "Memory_EPROM",
    "Memory_Flash",
    "Memory_NVRAM",
    "Memory_RAM",
    "Memory_ROM",
    "Memory_UniqueID",
    "Motor",
    "Oscillator",
    "Potentiometer_Digital",
    "Power_Management",
    "Power_Protection",
    "Power_Supervisor",
    "Reference_Current",
    "Reference_Voltage",
    "Regulator_Controller",
    "Regulator_Current",
    "Regulator_Linear",
    "Regulator_SwitchedCapacitor",
    "Regulator_Switching",
    "Relay",
    "Relay_SolidState",
    "RF",
    "RF_AM_FM",
    "RF_Amplifier",
    "RF_Bluetooth",
    "RF_Filter",
    "RF_GPS",
    "RF_GSM",
    "RF_Mixer",
    "RF_Module",
    "RF_NFC",
    "RF_RFID",
    "RF_Switch",
    "RF_WiFi",
    "RF_ZigBee",
    "Security",
    "Sensor",
    "Sensor_Audio",
    "Sensor_Current",
    "Sensor_Distance",
    "Sensor_Energy",
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
    "Transistor_FET_Other",
    "Transistor_IGBT",
    "Transistor_Power_Module",
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
    # Don't use check=True - easyeda2kicad may crash on 3D model export even if symbol/footprint succeed
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
        subprocess.run(cmd, check=False)
    except FileNotFoundError:
        error("easyeda2kicad not found. Is it installed?")
        sys.exit(1)

    # easyeda2kicad outputs to easyeda2kicad.* - rename to _staging.*
    easyeda_sym = staging / "easyeda2kicad.kicad_sym"
    easyeda_pretty = staging / "easyeda2kicad.pretty"
    easyeda_3d = staging / "easyeda2kicad.3dshapes"

    # Check what was successfully created
    has_symbol = False
    if easyeda_sym.exists():
        try:
            temp_lib = SymbolLib.from_file(str(easyeda_sym))
            has_symbol = len(temp_lib.symbols) > 0
        except Exception:
            pass
    has_footprint = easyeda_pretty.exists() and any(easyeda_pretty.glob("*.kicad_mod"))
    has_3d = easyeda_3d.exists() and any(easyeda_3d.glob("*"))

    if not has_symbol:
        error(f"Failed to download symbol for {lcsc_id} from LCSC/EasyEDA")
        sys.exit(1)

    if has_symbol and has_footprint and has_3d:
        success("Downloaded symbol, footprint, and 3D model from LCSC")
    elif has_symbol and has_footprint:
        success("Downloaded symbol and footprint from LCSC")
        warn("No 3D model available for this component")
    elif has_symbol:
        success("Downloaded symbol from LCSC")
        warn("No footprint or 3D model available for this component")

    sym_file = staging / "_staging.kicad_sym"
    staging_pretty = staging / "_staging.pretty"
    staging_3d = staging / "_staging.3dshapes"

    # Move symbol file (merge if _staging already exists)
    imported_symbol_name = None
    if easyeda_sym.exists():
        new_lib = SymbolLib.from_file(str(easyeda_sym))
        # Remember the symbol name we're importing (first/main symbol)
        if new_lib.symbols:
            imported_symbol_name = new_lib.symbols[0].entryName
        if sym_file.exists():
            existing_lib = SymbolLib.from_file(str(sym_file))
            # Remove duplicates and add new symbols
            existing_names = {s.entryName for s in existing_lib.symbols}
            for symbol in new_lib.symbols:
                if symbol.entryName in existing_names:
                    # Remove existing symbol with same name
                    existing_lib.symbols = [s for s in existing_lib.symbols if s.entryName != symbol.entryName]
                existing_lib.symbols.append(symbol)
            existing_lib.to_file(str(sym_file))
        else:
            new_lib.to_file(str(sym_file))
        easyeda_sym.unlink()

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

    # Update 3D model paths in footprints to use staging location
    update_footprint_3d_paths(staging_pretty, "KICAD_STAGING_LIBS", "_staging")

    if not sym_file.exists():
        error(f"Symbol file not found: {sym_file}")
        sys.exit(1)

    # Load symbol library with kiutils
    lib = SymbolLib.from_file(str(sym_file))

    if not lib.symbols:
        error("No symbols found in downloaded file")
        sys.exit(1)

    # Find the symbol we just imported
    symbol = None
    if imported_symbol_name:
        for s in lib.symbols:
            if s.entryName == imported_symbol_name:
                symbol = s
                break
    if not symbol:
        # Fallback to first symbol if name lookup fails
        symbol = lib.symbols[0]
    symbol_name = symbol.entryName
    info(f"Symbol name: {symbol_name}")

    # Fix footprint reference: easyeda2kicad:XXX -> _staging:XXX
    for prop in symbol.properties:
        if prop.key.lower() == "footprint" and "easyeda2kicad:" in prop.value:
            prop.value = prop.value.replace("easyeda2kicad:", "_staging:")

    # Clean up MPN for API searches - remove EasyEDA suffixes like _0_1, _0, etc.
    # These are internal KiCad sub-symbol identifiers, not part of the actual MPN
    mpn = re.sub(r"_\d+(_\d+)?$", "", symbol_name)
    if mpn != symbol_name:
        info(f"Cleaned MPN for API search: {mpn}")

    # Add LCSC property
    set_symbol_property(symbol, "LCSC", lcsc_id)
    success(f"Added LCSC property: {lcsc_id}")

    # Query Digikey
    info(f"Querying Digikey API for: {mpn}")
    digikey = DigikeyClient()
    dk_data = digikey.search(mpn)
    if dk_data:
        # V4 API field names
        if dk_pn := dk_data.get("DigiKeyProductNumber"):
            set_symbol_property(symbol, "Digikey", dk_pn)
            success(f"Added Digikey PN: {dk_pn}")

        if dk_stock := dk_data.get("QuantityAvailable"):
            set_symbol_property(symbol, "Stock_Digikey", str(dk_stock))
            info(f"Digikey stock: {dk_stock}")

        # V4 uses DatasheetUrl instead of PrimaryDatasheet
        if dk_ds := dk_data.get("DatasheetUrl"):
            # Fix protocol-relative URLs (start with //)
            if dk_ds.startswith("//"):
                dk_ds = "https:" + dk_ds
            set_symbol_property(symbol, "Datasheet", dk_ds)
            success("Added datasheet URL")

        # V4 has Description.ProductDescription and Description.DetailedDescription
        if dk_desc := dk_data.get("Description", {}):
            # Prefer DetailedDescription, fall back to ProductDescription
            desc = dk_desc.get("DetailedDescription") or dk_desc.get("ProductDescription")
            if desc:
                set_symbol_property(symbol, "ki_description", desc)
                success(f"Added description: {desc[:50]}...")

        # V4 uses Manufacturer.Name instead of Manufacturer.Value
        if dk_mfr := dk_data.get("Manufacturer", {}).get("Name"):
            set_symbol_property(symbol, "Manufacturer", dk_mfr)
            success(f"Added manufacturer: {dk_mfr}")

        # Pricing tiers (same structure in v4)
        for pricing in dk_data.get("StandardPricing", []):
            qty = pricing.get("BreakQuantity")
            price = pricing.get("UnitPrice")
            if qty and price:
                set_symbol_property(symbol, f"Price_{qty}", f"${price}")

    # Query Mouser
    info(f"Querying Mouser API for: {mpn}")
    mouser = MouserClient()
    if m_data := mouser.search(mpn):
        parts = m_data.get("SearchResults", {}).get("Parts", [])
        if parts:
            part = parts[0]
            if m_pn := part.get("MouserPartNumber"):
                set_symbol_property(symbol, "Mouser", m_pn)
                success(f"Added Mouser PN: {m_pn}")

            if m_avail := part.get("Availability"):
                stock = re.search(r"\d+", m_avail)
                if stock:
                    set_symbol_property(symbol, "Stock_Mouser", stock.group())
                    info(f"Mouser stock: {stock.group()}")

            if m_mfr := part.get("Manufacturer"):
                if not get_symbol_property(symbol, "Manufacturer"):
                    set_symbol_property(symbol, "Manufacturer", m_mfr)
                    success(f"Added manufacturer: {m_mfr}")

    # Add MPN (use the cleaned MPN, not the symbol name)
    set_symbol_property(symbol, "MPN", mpn)

    # Ensure only Reference and Value are visible
    normalize_symbol_visibility(symbol)
    lib.to_file(str(sym_file))

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
        info("Import parts first with: kicad-parts import <LCSC_ID>")
        sys.exit(1)

    staging_lib = SymbolLib.from_file(str(sym_file))
    all_symbol_names = [s.entryName for s in staging_lib.symbols]

    if not all_symbol_names:
        error("No symbols found in staging")
        sys.exit(1)

    # Filter symbols if a part name/pattern is specified
    if args.part:
        pattern = args.part.upper()
        symbols_to_accept = []
        for sym in staging_lib.symbols:
            lcsc = get_symbol_property(sym, "LCSC") or ""
            if pattern in sym.entryName.upper() or lcsc.upper() == pattern:
                symbols_to_accept.append(sym)
        if not symbols_to_accept:
            error(f"No staged parts match '{args.part}'")
            info(f"Available: {', '.join(all_symbol_names)}")
            sys.exit(1)
    else:
        symbols_to_accept = staging_lib.symbols[:]

    accepted_names = [s.entryName for s in symbols_to_accept]

    # Show what will be accepted
    info(f"Parts to accept: {', '.join(accepted_names)}")

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

    # Load or create production symbol library
    if prod_sym.exists():
        prod_lib = SymbolLib.from_file(str(prod_sym))
    else:
        prod_lib = SymbolLib()
        success(f"Created new library: {prod_sym.name}")

    # Add each symbol to production
    for symbol in symbols_to_accept:
        # Update footprint reference from _staging to production library
        for prop in symbol.properties:
            if prop.key.lower() == "footprint" and "_staging:" in prop.value:
                prop.value = prop.value.replace("_staging:", f"{lib_base}:")

        # Ensure only Reference and Value are visible
        normalize_symbol_visibility(symbol)

        # Remove existing symbol with same name if present
        prod_lib.symbols = [s for s in prod_lib.symbols if s.entryName != symbol.entryName]
        prod_lib.symbols.append(symbol)
        success(f"Added symbol: {symbol.entryName}")

    prod_lib.to_file(str(prod_sym))

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

    # Update 3D model paths in footprints to use production location
    update_footprint_3d_paths(prod_pretty, "KICAD_MY_LIBS", lib_base)

    # Clean up staging - remove accepted symbols
    remaining = [s for s in staging_lib.symbols if s.entryName not in accepted_names]
    if remaining:
        staging_lib.symbols = remaining
        staging_lib.to_file(str(sym_file))
        info(f"Remaining staged: {', '.join(s.entryName for s in remaining)}")
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
            info("Import parts with: kicad-parts import <LCSC_ID>")
            return

        lib = SymbolLib.from_file(str(sym_file))

        if not lib.symbols:
            info("No staged parts")
            return

        print(f"{BLUE}━━━ Staged Parts ━━━{NC}")
        print()

        # Collect data for table
        rows = []
        for symbol in sorted(lib.symbols, key=lambda s: s.entryName):
            lcsc = get_symbol_property(symbol, "LCSC") or ""
            desc = get_symbol_property(symbol, "Description") or ""
            rows.append((lcsc, symbol.entryName, desc))

        # Calculate column widths
        lcsc_width = max(4, max((len(r[0]) for r in rows), default=0))
        sym_width = max(6, max((len(r[1]) for r in rows), default=0))
        desc_width = max(11, max((len(r[2]) for r in rows), default=0))

        # Print table header
        print(f"  {'LCSC':<{lcsc_width}} │ {'Symbol':<{sym_width}} │ {'Description':<{desc_width}}")
        print(f"  {'─' * lcsc_width}─┼─{'─' * sym_width}─┼─{'─' * desc_width}")

        # Print rows
        for lcsc, sym, desc in rows:
            print(f"  {GREEN}{lcsc:<{lcsc_width}}{NC} │ {sym:<{sym_width}} │ {desc:<{desc_width}}")

        print()
        info(f"Total: {len(lib.symbols)} staged part(s)")
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

        lib = SymbolLib.from_file(str(lib_file))

        if not lib.symbols:
            continue

        print(f"{BLUE}━━━ {lib_name} ━━━{NC}")
        print()

        for symbol in sorted(lib.symbols, key=lambda s: s.entryName):
            print(f"  {GREEN}{symbol.entryName}{NC}")

            if args.verbose:
                for prop_name in [
                    "LCSC",
                    "MPN",
                    "Manufacturer",
                    "Digikey",
                    "Mouser",
                    "Datasheet",
                ]:
                    if val := get_symbol_property(symbol, prop_name):
                        print(f"    {prop_name}: {val}")
                for prop_name in [
                    "Price_1",
                    "Price_10",
                    "Price_100",
                    "Stock_Digikey",
                    "Stock_Mouser",
                ]:
                    if val := get_symbol_property(symbol, prop_name):
                        print(f"    {prop_name}: {val}")
                print()
            else:
                parts = []
                if lcsc := get_symbol_property(symbol, "LCSC"):
                    parts.append(f"LCSC:{lcsc}")
                if mfr := get_symbol_property(symbol, "Manufacturer"):
                    parts.append(mfr)
                if get_symbol_property(symbol, "Digikey"):
                    parts.append("DK")
                if get_symbol_property(symbol, "Mouser"):
                    parts.append("M")
                if parts:
                    print(f"    {CYAN}{' | '.join(parts)}{NC}")

        total_parts += len(lib.symbols)
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
        lib = SymbolLib.from_file(str(lib_file))
        for symbol in lib.symbols:
            all_parts.append((f"{lib_name}/{symbol.entryName}", lib_file, symbol.entryName))

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
    for _, lib_path, symbol_name in to_delete:
        by_library.setdefault(lib_path, []).append(symbol_name)

    for lib_path, symbol_names in by_library.items():
        lib_name = lib_path.stem
        lib = SymbolLib.from_file(str(lib_path))
        pretty_dir = production / f"{lib_name}.pretty"
        shapes_dir = production / f"{lib_name}.3dshapes"

        for symbol_name in symbol_names:
            info(f"Deleting {lib_name}/{symbol_name}...")

            # Remove symbol from library
            lib.symbols = [s for s in lib.symbols if s.entryName != symbol_name]

            # Delete footprint
            fp_file = pretty_dir / f"{symbol_name}.kicad_mod"
            if fp_file.exists():
                fp_file.unlink()
                success(f"Deleted footprint: {fp_file.name}")

            # Delete 3D models
            deleted = 0
            for ext in ["wrl", "step", "WRL", "STEP", "stp", "STP"]:
                model = shapes_dir / f"{symbol_name}.{ext}"
                if model.exists():
                    model.unlink()
                    deleted += 1
            if deleted:
                success(f"Deleted {deleted} 3D model file(s)")

        lib.to_file(str(lib_path))

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
