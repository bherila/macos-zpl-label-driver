#!/usr/bin/env python3
"""Offline consistency checks for this planning baseline, not a runtime profile parser."""
from __future__ import annotations

import json
import sys
from fractions import Fraction
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def nearest_positive(value: Fraction) -> int:
    """Nearest integer for a positive rational; exact halves round away from zero."""
    if value <= 0:
        raise ValueError("Expected positive geometry")
    return (2 * value.numerator + value.denominator) // (2 * value.denominator)


def validate_target(data: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return ["Reference target must be a JSON object"]
    try:
        if data["schemaVersion"] != 1 or data["purpose"] != "planning-reference-not-runtime-profile":
            errors.append("Unexpected reference schema/purpose")
        p, h, media, model, oracle, consent = (
            data[k] for k in ("project", "hardware", "media", "modelReference", "geometryOracle", "permissions")
        )
        expected_project = {
            "repository": "bherila/macos-zpl-label-driver", "license": "MIT", "minimumMacOS": "26.0",
            "primaryArchitecture": "arm64", "signingMode": "local-adhoc", "signingIdentity": "-",
        }
        for key, expected in expected_project.items():
            if p[key] != expected:
                errors.append(f"Confirmed project input changed: {key}")
        for key in ("appleDeveloperAccountAvailable", "notarizationRequiredForActiveScope"):
            if p[key] is not False:
                errors.append(f"Active scope must remain account-free: {key}")
        expected_hardware = {"manufacturer": "Zebra", "model": "GC420d", "transport": "usb", "thermalMethod": "direct-thermal", "selectedFinishing": "tear-off"}
        for key, expected in expected_hardware.items():
            if h[key] != expected:
                errors.append(f"Confirmed hardware input changed: {key}")
        if h["cutterInstalled"] is not False or h["peelerEnabled"] is not False:
            errors.append("Cutter/peel behavior cannot be enabled for the baseline")
        # This seed deliberately contains no discovered identifiers or invented readings.
        for key in ("peelerInstalled", "firmware", "deviceURI", "usbVendorID", "usbProductID", "existingQueueName"):
            if h[key] is not None:
                errors.append(f"Unobserved/private value filled in planning seed: {key}")
        for key in ("trackingConfirmed", "gapMm", "pitchMm", "linerWidthMm"):
            if media[key] is not None:
                errors.append(f"Unobserved media value filled in planning seed: {key}")
        if media["form"] != "pre-cut" or media["printableRegionConfirmed"] is not False:
            errors.append("Media form or observation state changed")
        width_in, height_in = Fraction(media["widthInches"]), Fraction(media["heightInches"])
        if (width_in, height_in) != (Fraction(4), Fraction(6)):
            errors.append("Confirmed nominal 4x6 stock changed")
        pitch = model["dotsPerMillimeter"]
        dpmm = Fraction(pitch["numerator"], pitch["denominator"])
        if dpmm != 8 or Fraction(model["dotPitchMm"]) != Fraction(1, 8):
            errors.append("GC420d documented pitch must remain 8 dots/mm")
        if model["nominalDPI"] != 203 or model["printSpeedChoicesIps"] != [2, 3, 4]:
            errors.append("Documented nominal DPI/speed choices changed")
        if model["currentSpeedIps"] is not None or model["currentDarkness"] is not None:
            errors.append("Current device settings were not measured")
        if model["usbStatusPathVerified"] is not False or model["compressionVerified"] is not False:
            errors.append("Planning inputs cannot fabricate device evidence")
        head = Fraction(model["maximumPrintWidthMm"]) * dpmm
        if head != 832 or model["derivedMaximumPrintWidthDots"] != head:
            errors.append("Documented head-width derivation changed")
        width = nearest_positive(width_in * Fraction(127, 5) * dpmm)
        height = nearest_positive(height_in * Fraction(127, 5) * dpmm)
        stride = (width + 7) // 8
        expected = {"widthDots": width, "heightDots": height, "bytesPerRow": stride,
                    "packedBytes": stride * height, "lastByteWhitePaddingBits": stride * 8 - width}
        for key, value in expected.items():
            if type(oracle[key]) is not int or oracle[key] != value:
                errors.append(f"Geometry oracle mismatch: {key}")
        if oracle["rounding"] != "nearest-positive-half-away-from-zero":
            errors.append("Rounding policy changed without new evidence")
        cap = oracle["proposedDecodedBandByteCap"]
        if type(cap) is not int or not stride <= cap <= 99999:
            errors.append("Invalid decoded band policy")
        else:
            rows_per_band = cap // stride
            full, remainder = divmod(height, rows_per_band)
            bands = [rows_per_band] * full + ([remainder] if remainder else [])
            if oracle["bandRows"] != bands:
                errors.append("Band partition does not reconstruct the nominal face")
        if oracle["advertisedIntegerDPIIsNotPhysicalPitch"] is not True:
            errors.append("Nominal DPI and physical pitch must remain distinct")
        for key in ("printerIOAuthorized", "queueMutationAuthorized", "privilegedInstallAuthorized"):
            if consent[key] is not False:
                errors.append(f"Planning handoff is not operational consent: {key}")
        if type(consent["physicalLabelBudget"]) is not int or consent["physicalLabelBudget"] != 0:
            errors.append("No physical label budget has been granted in the handoff")
        if data["qualification"] != "unqualified":
            errors.append("Planning handoff is not device qualification")
    except (KeyError, TypeError, ValueError, ZeroDivisionError, OverflowError) as exc:
        errors.append(f"Invalid reference data: {type(exc).__name__}: {exc}")
    return errors


def main() -> int:
    try:
        data = json.loads((ROOT / "docs/reference-target.json").read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    errors = validate_target(data)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if not errors:
        print("Reference planning inputs and exact geometry passed; no device qualification implied.")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
