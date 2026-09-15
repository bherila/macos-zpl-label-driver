#!/usr/bin/env python3
"""Independent decoder for this project's uncompressed diagnostic subset ONLY.

Not a general ZPL interpreter, printer simulator, sanitizer or safe-print gateway.
Rejects unsupported commands instead of quietly accepting them.
"""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path

MAX_INPUT = 64 * 1024 * 1024
MAX_PACKED = 16 * 1024 * 1024
HEADER = re.compile(rb"\^FO0,([0-9]{1,5})\^GFA,([0-9]{1,5}),([0-9]{1,5}),([0-9]{1,5}),")


def dimensions(width: int, height: int) -> tuple[int, int]:
    if type(width) is not int or type(height) is not int or not (1 <= width <= 32000 and 1 <= height <= 32000):
        raise ValueError("dimensions outside oracle bounds")
    stride = (width + 7) // 8
    total = stride * height
    if total > MAX_PACKED:
        raise ValueError("packed bitmap exceeds oracle limit")
    return stride, total


def check_padding(data: bytes, width: int, height: int) -> None:
    stride, total = dimensions(width, height)
    if len(data) != total:
        raise ValueError("wrong decoded length")
    unused = (-width) % 8
    mask = (1 << unused) - 1
    if any(data[(y + 1) * stride - 1] & mask for y in range(height)):
        raise ValueError("nonzero padding")


def decode(data: bytes, width: int, height: int, band_limit: int = 99999) -> tuple[bytes, list[int]]:
    stride, total = dimensions(width, height)
    if not 1 <= band_limit <= 99999 or len(data) > MAX_INPUT:
        raise ValueError("input/band limit")
    if not data.startswith(b"^XA\n") or not data.endswith(b"^XZ\n"):
        raise ValueError("missing exact diagnostic envelope")
    pos, y = 4, 0
    decoded = bytearray()
    rows = []
    while pos < len(data) - 4:
        match = HEADER.match(data, pos)
        if not match:
            raise ValueError("unsupported or malformed command")
        origin, transmitted, count, field_stride = map(int, match.groups())
        if origin != y or field_stride != stride or transmitted != count:
            raise ValueError("origin/stride/count mismatch")
        if not 1 <= count <= band_limit or count % stride:
            raise ValueError("invalid band size")
        band_rows = count // stride
        if y + band_rows > height:
            raise ValueError("band exceeds image")
        start = match.end()
        stop = start + count * 2
        chunk = data[start:stop]
        if len(chunk) != count * 2 or re.fullmatch(rb"[0-9A-F]+", chunk) is None:
            raise ValueError("invalid hex payload")
        if data[stop:stop + 4] != b"^FS\n":
            raise ValueError("invalid field terminator")
        decoded.extend(bytes.fromhex(chunk.decode("ascii")))
        rows.append(band_rows)
        pos = stop + 4
        y += band_rows
    if pos != len(data) - 4 or y != height or len(decoded) != total:
        raise ValueError("missing rows or unexpected trailing data")
    check_padding(decoded, width, height)
    return bytes(decoded), rows


def read_pbm(data: bytes) -> tuple[int, int, bytes]:
    """Only the canonical P4 header emitted by our exact-preview function."""
    if len(data) > MAX_PACKED + 128:
        raise ValueError("PBM input too large")
    match = re.match(rb"P4\n([0-9]{1,5}) ([0-9]{1,5})\n", data)
    if not match:
        raise ValueError("unsupported PBM header")
    width, height = map(int, match.groups())
    payload = data[match.end():]
    check_padding(payload, width, height)
    return width, height, payload


def analytic_bitmap(width: int, height: int) -> bytes:
    """Second-language analytic pattern oracle, independent of Swift bit packing."""
    rows = []
    for y in range(height):
        bits = ['1' if x in (0, width - 1) or y in (0, height - 1)
                or (17 * x + 31 * y) % 113 < 11 else '0' for x in range(width)]
        bits += ['0'] * ((-width) % 8)
        rows.extend(int(''.join(bits[k:k + 8]), 2) for k in range(0, len(bits), 8))
    return bytes(rows)


def verify_vectors(directory: Path) -> int:
    manifest = json.loads((directory / "vectors.json").read_text())
    if manifest["schemaVersion"] != 1:
        raise ValueError("unknown vector schema")
    seen = set()
    for v in manifest["vectors"]:
        name = v["name"]
        if not re.fullmatch(r"[a-z0-9-]+", name) or name in seen:
            raise ValueError("invalid/duplicate vector name")
        seen.add(name)
        width, height, packed = read_pbm((directory / f"{name}.pbm").read_bytes())
        if (width, height) != (v["width"], v["height"]):
            raise ValueError("vector dimensions disagree")
        reconstructed, rows = decode((directory / f"{name}.zpl").read_bytes(), width, height, v["bandLimit"])
        if rows != v["bandRows"] or packed != reconstructed or packed != analytic_bitmap(width, height):
            raise ValueError("ZPL/PBM/analytic-oracle mismatch")
    if not seen:
        raise ValueError("empty vector corpus")
    return len(seen)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vector_directory", type=Path)
    args = parser.parse_args()
    print(f"Independent ZPL/PBM/analytic round-trips passed: {verify_vectors(args.vector_directory)} vectors")
