#!/usr/bin/env python3
"""Update KiCad symbol pin names and types from IMXRT1060 datasheet."""

from pathlib import Path
from kiutils.symbol import SymbolLib

# Ball map from Table 84 (10x10 mm, 0.65 mm pitch)
BALL_MAP = {
    # Row A
    "A1": "VSS", "A2": "GPIO_EMC_27", "A3": "GPIO_EMC_20", "A4": "GPIO_EMC_17",
    "A5": "GPIO_EMC_16", "A6": "GPIO_EMC_13", "A7": "GPIO_EMC_40", "A8": "GPIO_B0_06",
    "A9": "GPIO_B0_07", "A10": "GPIO_B0_11", "A11": "GPIO_B1_00", "A12": "GPIO_B1_08",
    "A13": "GPIO_B1_09", "A14": "VSS",
    # Row B
    "B1": "GPIO_EMC_15", "B2": "GPIO_EMC_18", "B3": "GPIO_EMC_26", "B4": "GPIO_EMC_19",
    "B5": "VSS", "B6": "GPIO_EMC_14", "B7": "GPIO_EMC_39", "B8": "GPIO_B0_05",
    "B9": "GPIO_B0_08", "B10": "VSS", "B11": "GPIO_B1_01", "B12": "GPIO_B1_07",
    "B13": "GPIO_B1_10", "B14": "GPIO_B1_15",
    # Row C
    "C1": "GPIO_EMC_21", "C2": "GPIO_EMC_09", "C3": "GPIO_EMC_36", "C4": "GPIO_EMC_33",
    "C5": "GPIO_EMC_31", "C6": "GPIO_EMC_30", "C7": "GPIO_EMC_41", "C8": "GPIO_B0_04",
    "C9": "GPIO_B0_09", "C10": "GPIO_B0_12", "C11": "GPIO_B1_02", "C12": "GPIO_B1_06",
    "C13": "GPIO_B1_11", "C14": "GPIO_B1_14",
    # Row D
    "D1": "GPIO_EMC_28", "D2": "GPIO_EMC_25", "D3": "GPIO_EMC_24", "D4": "GPIO_EMC_34",
    "D5": "GPIO_EMC_32", "D6": "GPIO_EMC_38", "D7": "GPIO_B0_00", "D8": "GPIO_B0_03",
    "D9": "GPIO_B0_10", "D10": "GPIO_B0_13", "D11": "GPIO_B1_03", "D12": "GPIO_B1_05",
    "D13": "GPIO_B1_12", "D14": "GPIO_B1_13",
    # Row E
    "E1": "GPIO_EMC_29", "E2": "VSS", "E3": "GPIO_EMC_00", "E4": "GPIO_EMC_37",
    "E5": "GPIO_EMC_35", "E6": "NVCC_EMC", "E7": "GPIO_B0_01", "E8": "GPIO_B0_02",
    "E9": "NVCC_GPIO", "E10": "GPIO_B0_14", "E11": "GPIO_B0_15", "E12": "GPIO_B1_04",
    "E13": "VSS", "E14": "GPIO_AD_B0_06",
    # Row F
    "F1": "GPIO_EMC_22", "F2": "GPIO_EMC_04", "F3": "GPIO_EMC_01", "F4": "GPIO_EMC_02",
    "F5": "NVCC_EMC", "F6": "VDD_SOC_IN", "F7": "VDD_SOC_IN", "F8": "VDD_SOC_IN",
    "F9": "VDD_SOC_IN", "F10": "NVCC_GPIO", "F11": "GPIO_AD_B0_04", "F12": "GPIO_AD_B0_07",
    "F13": "GPIO_AD_B0_08", "F14": "GPIO_AD_B0_09",
    # Row G
    "G1": "GPIO_EMC_10", "G2": "GPIO_EMC_23", "G3": "GPIO_EMC_11", "G4": "GPIO_EMC_03",
    "G5": "GPIO_EMC_05", "G6": "VDD_SOC_IN", "G7": "VSS", "G8": "VSS",
    "G9": "VDD_SOC_IN", "G10": "GPIO_AD_B0_11", "G11": "GPIO_AD_B0_03", "G12": "GPIO_AD_B1_14",
    "G13": "GPIO_AD_B0_10", "G14": "GPIO_AD_B0_05",
    # Row H
    "H1": "GPIO_EMC_12", "H2": "GPIO_SD_B0_04", "H3": "GPIO_EMC_08", "H4": "GPIO_EMC_07",
    "H5": "GPIO_EMC_06", "H6": "VDD_SOC_IN", "H7": "VSS", "H8": "VSS",
    "H9": "VDD_SOC_IN", "H10": "GPIO_AD_B0_01", "H11": "GPIO_AD_B1_13", "H12": "GPIO_AD_B1_12",
    "H13": "GPIO_AD_B1_08", "H14": "GPIO_AD_B0_14",
    # Row J
    "J1": "GPIO_SD_B0_02", "J2": "GPIO_SD_B0_05", "J3": "GPIO_SD_B0_01", "J4": "GPIO_SD_B0_00",
    "J5": "DCDC_SENSE", "J6": "NVCC_SD0", "J7": "VSS", "J8": "VSS",
    "J9": "VDD_SOC_IN", "J10": "NVCC_GPIO", "J11": "GPIO_AD_B1_00", "J12": "GPIO_AD_B1_06",
    "J13": "GPIO_AD_B1_11", "J14": "GPIO_AD_B1_15",
    # Row K
    "K1": "GPIO_SD_B0_03", "K2": "VSS", "K3": "DCDC_PSWITCH", "K4": "DCDC_IN_Q",
    "K5": "NVCC_SD1", "K6": "TEST_MODE", "K7": "PMIC_ON_REQ", "K8": "VDD_USB_CAP",
    "K9": "NGND_KEL0", "K10": "GPIO_AD_B1_07", "K11": "GPIO_AD_B1_01", "K12": "GPIO_AD_B1_05",
    "K13": "VSS", "K14": "GPIO_AD_B0_12",
    # Row L
    "L1": "DCDC_IN", "L2": "DCDC_IN", "L3": "GPIO_SD_B1_06", "L4": "GPIO_SD_B1_07",
    "L5": "GPIO_SD_B1_00", "L6": "WAKEUP", "L7": "PMIC_STBY_REQ", "L8": "USB_OTG1_DP",
    "L9": "VSS", "L10": "GPIO_AD_B0_15", "L11": "GPIO_AD_B1_02", "L12": "GPIO_AD_B1_04",
    "L13": "GPIO_AD_B1_10", "L14": "GPIO_AD_B0_13",
    # Row M
    "M1": "DCDC_LP", "M2": "DCDC_LP", "M3": "GPIO_SD_B1_02", "M4": "GPIO_SD_B1_03",
    "M5": "GPIO_SD_B1_01", "M6": "ONOFF", "M7": "POR_B", "M8": "USB_OTG1_DN",
    "M9": "VDD_SNVS_IN", "M10": "VDD_SNVS_CAP", "M11": "GPIO_AD_B0_02", "M12": "GPIO_AD_B1_03",
    "M13": "GPIO_AD_B1_09", "M14": "GPIO_AD_B0_00",
    # Row N
    "N1": "DCDC_GND", "N2": "DCDC_GND", "N3": "GPIO_SD_B1_05", "N4": "GPIO_SD_B1_09",
    "N5": "VSS", "N6": "USB_OTG1_VBUS", "N7": "USB_OTG2_DN", "N8": "VSS",
    "N9": "RTC_XTALI", "N10": "GPANAIO", "N11": "XTALO", "N12": "USB_OTG1_CHD_B",
    "N13": "CCM_CLK1_P", "N14": "VDDA_ADC_3P3",
    # Row P
    "P1": "VSS", "P2": "GPIO_SD_B1_04", "P3": "GPIO_SD_B1_08", "P4": "GPIO_SD_B1_10",
    "P5": "GPIO_SD_B1_11", "P6": "USB_OTG2_VBUS", "P7": "USB_OTG2_DP", "P8": "VDD_HIGH_CAP",
    "P9": "RTC_XTALO", "P10": "NVCC_PLL", "P11": "XTALI", "P12": "VDD_HIGH_IN",
    "P13": "CCM_CLK1_N", "P14": "VSS",
}


def get_pin_type(signal_name: str) -> str:
    """Determine KiCad pin type from signal name."""
    # Ground pins
    if signal_name in ("VSS", "DCDC_GND", "NGND_KEL0"):
        return "power_in"

    # Power input pins
    if signal_name.startswith(("VDD_", "NVCC_", "VDDA_", "DCDC_IN", "DCDC_LP")):
        return "power_in"

    # Capacitor connections (passive)
    if signal_name.endswith("_CAP"):
        return "passive"

    # GPIO pins are bidirectional
    if signal_name.startswith("GPIO_"):
        return "bidirectional"

    # USB data pins are bidirectional
    if signal_name in ("USB_OTG1_DP", "USB_OTG1_DN", "USB_OTG2_DP", "USB_OTG2_DN"):
        return "bidirectional"

    # USB VBUS detection (passive/input)
    if signal_name in ("USB_OTG1_VBUS", "USB_OTG2_VBUS"):
        return "passive"

    # USB charger detect
    if signal_name == "USB_OTG1_CHD_B":
        return "output"

    # Output pins
    if signal_name in ("PMIC_ON_REQ", "PMIC_STBY_REQ"):
        return "output"

    # Crystal oscillator pins
    if signal_name in ("XTALI", "RTC_XTALI"):
        return "input"
    if signal_name in ("XTALO", "RTC_XTALO"):
        return "output"

    # Input pins
    if signal_name in ("POR_B", "TEST_MODE", "ONOFF"):
        return "input"

    # Clock inputs
    if signal_name in ("CCM_CLK1_P", "CCM_CLK1_N"):
        return "input"

    # WAKEUP can be used as GPIO
    if signal_name == "WAKEUP":
        return "bidirectional"

    # DCDC control pins
    if signal_name in ("DCDC_PSWITCH", "DCDC_SENSE"):
        return "passive"

    # General purpose analog I/O
    if signal_name == "GPANAIO":
        return "passive"

    # Default to unspecified
    return "unspecified"


def update_kicad_symbol(filepath: Path) -> None:
    """Update pin names and types in KiCad symbol file."""
    lib = SymbolLib.from_file(str(filepath))

    pins_updated = 0
    for symbol in lib.symbols:
        for unit in symbol.units:
            for pin in unit.pins:
                ball = pin.number
                if ball in BALL_MAP:
                    new_name = BALL_MAP[ball]
                    new_type = get_pin_type(new_name)

                    if pin.name != new_name or pin.electricalType != new_type:
                        print(f"  {ball}: {pin.name} ({pin.electricalType}) -> {new_name} ({new_type})")
                        pin.name = new_name
                        pin.electricalType = new_type
                        pins_updated += 1

    lib.to_file(str(filepath))
    print(f"\nUpdated {pins_updated} pins in {filepath}")


if __name__ == "__main__":
    symbol_path = Path("/Users/joshheyse/Documents/KiCad/9.0/staging/_staging.kicad_sym")
    update_kicad_symbol(symbol_path)
