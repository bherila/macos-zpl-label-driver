#!/usr/bin/env python3
"""Assert built-artifact properties from captured macOS tool output.

`lipo -archs` exits 0 whether it reports `arm64`, `x86_64` or `arm64 x86_64`,
and `vtool -show-build` exits 0 whatever minimum it prints. A step that runs
either and prints the result asserts nothing: a human reading the log would
notice a wrong architecture, and nothing in CI would. This module turns those
captures into pass/fail decisions.

Every parsing and accept/reject rule lives here, in portable Python, so the
rules are unit-testable on a host that has no `lipo`, `vtool`, `codesign` or
Apple toolchain at all (scripts/tests/test_native_artifacts.py). The macOS-only
part of `scripts/ci-swift.sh` only captures tool output and hands it over; it
makes no decision of its own.

The expected values below are fixed constants, deliberately not read from
`MACOSX_DEPLOYMENT_TARGET` or from the tool output being judged. The
environment variable is the build's input; the load command is the evidence,
and evidence compared against its own input proves nothing.

Nothing here opens, enumerates, configures or writes to a device, and nothing
here promotes a passing check to a qualified acceptance criterion.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

EXPECTED_ARCHITECTURE = "arm64"
EXPECTED_MINIMUM_MACOS = "26.0"
EXPECTED_PLATFORM = "MACOS"
FORBIDDEN_ARCHITECTURES = ("i386", "x86_64", "x86_64h")

# `scripts/ci-swift.sh` appends this line to a capture whose tool exited
# non-zero. Without it an error message on stderr and a legitimate result are
# the same bytes to this module, and "can't figure out the architecture type"
# contains no architecture at all.
TOOL_FAILURE_MARKER = "CAPTURE-TOOL-FAILED"

SIGNED_DIRECTORY_MARKER = "Verified local-ad-hoc command-line products in: "
BUILT_APP_MARKER = "Built and verified local-ad-hoc app: "

EXPECTED_BUNDLE_METADATA = (
    ("CFBundleExecutable", "label-printer-setup"),
    ("LSMinimumSystemVersion", EXPECTED_MINIMUM_MACOS),
    ("LabelDriverSigningMode", "local-ad-hoc"),
)

_FIELD = re.compile(r"(?m)^([A-Za-z][A-Za-z0-9_.-]*)=(.*)$")
_CODE_DIRECTORY_FLAGS = re.compile(r"(?m)^CodeDirectory\b.*?\bflags=(\S+)")
_REAL_SIGNATURE = re.compile(r"(?m)^Signature size=")

_MISSING = object()


def _capture_problems(label: str, capture: str, tool: str) -> list[str]:
    """Preconditions every capture must meet before any rule is applied."""
    if TOOL_FAILURE_MARKER in capture:
        return [f"{label}: `{tool}` failed; its capture cannot establish anything"]
    if not capture.strip():
        return [f"{label}: `{tool}` produced an empty capture"]
    return []


def _version_tuple(text: str) -> tuple[int, int, int]:
    parts = text.strip().split(".")
    if not 1 <= len(parts) <= 3 or not all(part.isdigit() for part in parts):
        raise ValueError(f"unparsable version {text!r}")
    padded = parts + ["0"] * (3 - len(parts))
    return (int(padded[0]), int(padded[1]), int(padded[2]))


def architecture_errors(label: str, capture: str) -> list[str]:
    """Require a thin `arm64` executable: one slice, and no Intel slice."""
    errors = _capture_problems(label, capture, "lipo -archs")
    if errors:
        return errors
    lines = [line.strip() for line in capture.strip().splitlines() if line.strip()]
    if len(lines) != 1:
        return [f"{label}: expected one `lipo -archs` line, found {len(lines)}"]
    found = lines[0].split()
    intel = [name for name in FORBIDDEN_ARCHITECTURES if name in found]
    if intel:
        errors.append(
            f"{label}: Intel slice in a shipped executable: {' '.join(intel)}. "
            "The confirmed baseline is Apple Silicon only, and an Intel claim "
            "needs its own validation evidence, not a compiled slice."
        )
    if found != [EXPECTED_ARCHITECTURE]:
        errors.append(
            f"{label}: expected exactly `{EXPECTED_ARCHITECTURE}`, found `{lines[0]}`"
        )
    return errors


def _build_version_blocks(capture: str) -> list[dict[str, str]]:
    blocks: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for raw in capture.splitlines():
        parts = raw.split()
        if len(parts) == 2 and parts[0] == "cmd":
            current = {} if parts[1] == "LC_BUILD_VERSION" else None
            if current is not None:
                blocks.append(current)
            continue
        if current is not None and len(parts) == 2 and parts[0] not in current:
            current[parts[0]] = parts[1]
    return blocks


def minimum_os_errors(
    label: str, capture: str, expected: str = EXPECTED_MINIMUM_MACOS
) -> list[str]:
    """Require the built minimum macOS to be exactly the declared baseline.

    Equality, not `>=`: a minimum above the baseline silently drops hosts the
    project says it supports, and a minimum below it claims hosts nothing was
    built or tested against.
    """
    errors = _capture_problems(label, capture, "vtool -show-build")
    if errors:
        return errors
    if "LC_VERSION_MIN_MACOSX" in capture:
        errors.append(
            f"{label}: legacy LC_VERSION_MIN_MACOSX present; the baseline "
            "expects an LC_BUILD_VERSION load command"
        )
    blocks = _build_version_blocks(capture)
    if len(blocks) != 1:
        errors.append(
            f"{label}: expected exactly one LC_BUILD_VERSION load command, "
            f"found {len(blocks)}"
        )
        return errors
    block = blocks[0]
    platform = block.get("platform")
    if platform != EXPECTED_PLATFORM:
        errors.append(
            f"{label}: expected platform {EXPECTED_PLATFORM}, found "
            f"{platform if platform is not None else 'no platform field'}"
        )
    minos = block.get("minos")
    if minos is None:
        errors.append(f"{label}: LC_BUILD_VERSION carries no `minos` field")
        return errors
    try:
        found = _version_tuple(minos)
    except ValueError:
        errors.append(f"{label}: unparsable minimum macOS version {minos!r}")
        return errors
    if found != _version_tuple(expected):
        errors.append(
            f"{label}: built minimum macOS is {minos}, expected {expected}. "
            "MACOSX_DEPLOYMENT_TARGET being exported is not evidence; this "
            "load command is."
        )
    return errors


def _codesign_fields(capture: str) -> dict[str, list[str]]:
    fields: dict[str, list[str]] = {}
    for key, value in _FIELD.findall(capture):
        fields.setdefault(key, []).append(value)
    return fields


def signature_errors(label: str, capture: str) -> list[str]:
    """Require an ad-hoc signature with no Team Identifier and no authority."""
    errors = _capture_problems(label, capture, "codesign -dv")
    if errors:
        return errors
    fields = _codesign_fields(capture)
    signature = fields.get("Signature", [None])[0]
    if signature != "adhoc":
        if _REAL_SIGNATURE.search(capture):
            detail = "a certificate-backed signature (`Signature size=`)"
        elif signature is None:
            detail = "no `Signature=` field"
        else:
            detail = f"`Signature={signature}`"
        errors.append(f"{label}: expected `Signature=adhoc`; capture reports {detail}")
    team = fields.get("TeamIdentifier", [None])[0]
    if team != "not set":
        reported = "no `TeamIdentifier=` field" if team is None else f"`{team}`"
        errors.append(
            f"{label}: expected `TeamIdentifier=not set`; capture reports {reported}. "
            "The confirmed baseline signs without an Apple account or Team ID."
        )
    if "Authority" in fields:
        errors.append(
            f"{label}: certificate authority in certificate-free signing mode: "
            f"{fields['Authority'][0]}"
        )
    flags = _CODE_DIRECTORY_FLAGS.search(capture)
    if flags is not None and "adhoc" not in flags.group(1):
        errors.append(
            f"{label}: CodeDirectory flags {flags.group(1)} do not include adhoc"
        )
    return errors


def diagnostic_errors(label: str, capture: str) -> list[str]:
    """Require the inert diagnostic to report no printer I/O and a live SDK."""
    errors = _capture_problems(label, capture, "label-driver-diagnostics")
    if errors:
        return errors
    try:
        payload = json.loads(capture)
    except ValueError:
        return [f"{label}: diagnostic output is not a single JSON object"]
    if not isinstance(payload, dict):
        return [f"{label}: diagnostic output is not a JSON object"]
    for key in ("printerIOPerformed", "driverImplemented"):
        value = payload.get(key, _MISSING)
        if value is _MISSING:
            errors.append(f"{label}: diagnostic JSON has no `{key}` field")
        elif value is not False:
            # Identity, not truthiness: 0, "" and null are unknown states, and
            # an unknown state is not a reported false.
            errors.append(
                f"{label}: expected `{key}` to be exactly false, found "
                f"{json.dumps(value)}"
            )
    pixel = payload.get("coreGraphicsWhitePixel", _MISSING)
    if pixel is _MISSING:
        errors.append(f"{label}: diagnostic JSON has no `coreGraphicsWhitePixel` field")
    elif isinstance(pixel, bool) or not isinstance(pixel, int) or pixel != 255:
        errors.append(
            f"{label}: expected Core Graphics white pixel 255, found "
            f"{json.dumps(pixel)}"
        )
    return errors


def bundle_metadata_errors(label: str, capture: str) -> list[str]:
    """Require the sealed bundle to declare the baseline runtime and mode."""
    errors = _capture_problems(label, capture, "plutil -convert json")
    if errors:
        return errors
    try:
        payload = json.loads(capture)
    except ValueError:
        return [f"{label}: bundle metadata is not JSON"]
    if not isinstance(payload, dict):
        return [f"{label}: bundle metadata is not a JSON object"]
    for key, expected in EXPECTED_BUNDLE_METADATA:
        found = payload.get(key, _MISSING)
        if found is _MISSING:
            errors.append(f"{label}: bundle Info.plist has no `{key}` entry")
        elif found != expected:
            errors.append(
                f"{label}: bundle `{key}` is {json.dumps(found)}, expected "
                f"{json.dumps(expected)}"
            )
    return errors


def path_after_marker(
    label: str, capture: str, marker: str
) -> tuple[str | None, list[str]]:
    """Read one absolute path a build script reported on a marker line."""
    if TOOL_FAILURE_MARKER in capture:
        return None, [f"{label}: the script producing this log failed"]
    found = [
        line[len(marker):].rstrip()
        for line in capture.splitlines()
        if line.startswith(marker)
    ]
    if not found:
        return None, [f"{label}: no line beginning {marker.strip()!r} in the log"]
    if len(set(found)) != 1:
        return None, [
            f"{label}: {len(set(found))} different paths reported for "
            f"{marker.strip()!r}"
        ]
    path = found[0]
    if not path:
        return None, [f"{label}: empty path reported for {marker.strip()!r}"]
    if not path.startswith("/"):
        return None, [f"{label}: expected an absolute path, found {path!r}"]
    return path, []


CHECKS = {
    "architecture": (architecture_errors, f"{EXPECTED_ARCHITECTURE}-only executable"),
    "minimum-os": (minimum_os_errors, f"minimum macOS {EXPECTED_MINIMUM_MACOS}"),
    "signature": (signature_errors, "ad-hoc signature, no Team Identifier"),
    "diagnostic": (diagnostic_errors, "no printer I/O; Core Graphics smoke passed"),
    "bundle-metadata": (bundle_metadata_errors, "baseline bundle metadata"),
}

LOCATORS = {
    "signed-directory": SIGNED_DIRECTORY_MARKER,
    "built-app-path": BUILT_APP_MARKER,
}

USAGE = (
    "Usage: check_native_artifacts.py CHECK LABEL CAPTURE\n"
    f"       checks: {' '.join(sorted(CHECKS))}\n"
    "       check_native_artifacts.py LOCATOR CAPTURE\n"
    f"       locators: {' '.join(sorted(LOCATORS))}\n"
)


def _read(path: str) -> str:
    # Replacement characters cannot turn a rejected capture into an accepted
    # one: every rule above is a positive match against expected text.
    return Path(path).read_text(encoding="utf-8", errors="replace")


def main(argv: list[str]) -> int:
    if not argv:
        sys.stderr.write(USAGE)
        return 2
    name = argv[0]
    if name in LOCATORS:
        if len(argv) != 2:
            sys.stderr.write(USAGE)
            return 2
        try:
            capture = _read(argv[1])
        except OSError as error:
            sys.stderr.write(f"Cannot read capture {argv[1]}: {error}\n")
            return 2
        path, errors = path_after_marker(name, capture, LOCATORS[name])
        if errors:
            for error in errors:
                sys.stderr.write(f"ERROR: {error}\n")
            return 1
        sys.stdout.write(f"{path}\n")
        return 0
    if name not in CHECKS:
        sys.stderr.write(f"Unknown check: {name}\n")
        sys.stderr.write(USAGE)
        return 2
    if len(argv) != 3:
        sys.stderr.write(USAGE)
        return 2
    label = argv[1]
    try:
        capture = _read(argv[2])
    except OSError as error:
        sys.stderr.write(f"Cannot read capture {argv[2]}: {error}\n")
        return 2
    rule, description = CHECKS[name]
    errors = rule(label, capture)
    if errors:
        for error in errors:
            sys.stderr.write(f"ERROR: {error}\n")
        return 1
    sys.stdout.write(f"OK {name} {label}: {description}.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
