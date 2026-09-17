#!/usr/bin/env python3
"""Independent strict decoder for the experimental ASCII repeat-count subset.

Does not modify the original plain-hex oracle, simulate firmware, or enable printing.
Counts may compose, but may not cross rows. Only hex, counts, and row repeat are
accepted; fill markers and other compression families are intentionally rejected.
"""
from __future__ import annotations
import re
import json
from zpl_oracle import HEADER, MAX_INPUT, dimensions, check_padding, read_pbm, analytic_bitmap


def payload(data: bytes, stride: int, count: int) -> bytes:
    output = bytearray()
    row = bytearray()
    repeats = 0
    for value in data:
        if 71 <= value <= 89 or 103 <= value <= 122:
            repeats += value - 70 if value <= 89 else (value - 102) * 20
            if repeats > stride * 2 - len(row):
                raise ValueError("repeat exceeds row")
            continue
        if value == 58:
            if row or repeats or len(output) < stride or len(output) + stride > count:
                raise ValueError("invalid previous-row repeat")
            output.extend(output[-stride:])
            continue
        if value not in b"0123456789ABCDEF":
            raise ValueError("unsupported compressed symbol")
        row.extend(bytes([value]) * (repeats or 1))
        repeats = 0
        if len(row) == stride * 2:
            if len(output) + stride > count:
                raise ValueError("decoded field overflow")
            output.extend(bytes.fromhex(row.decode("ascii")))
            row.clear()
    if row or repeats or len(output) != count:
        raise ValueError("incomplete compressed field")
    return bytes(output)


def decode(data: bytes, width: int, height: int, band_limit: int = 99999) -> tuple[bytes, list[int]]:
    stride, total = dimensions(width, height)
    if not 1 <= band_limit <= 99999 or len(data) > MAX_INPUT:
        raise ValueError("input/band limit")
    if not data.startswith(b"^XA\n") or not data.endswith(b"^XZ\n"):
        raise ValueError("invalid envelope")
    output, rows = bytearray(), []
    pos, y = 4, 0
    while pos < len(data) - 4:
        match = HEADER.match(data, pos)
        if not match:
            raise ValueError("unsupported command")
        origin, transmitted, count, field_stride = map(int, match.groups())
        if origin != y or transmitted != count or field_stride != stride:
            raise ValueError("field metadata mismatch")
        if not 1 <= count <= band_limit or count % stride or y + count // stride > height:
            raise ValueError("invalid decoded band size")
        end = data.find(b"^FS\n", match.end())
        if end < 0:
            raise ValueError("missing field terminator")
        output.extend(payload(data[match.end():end], stride, count))
        rows.append(count // stride)
        y += rows[-1]
        pos = end + 4
    if pos != len(data) - 4 or len(output) != total or y != height:
        raise ValueError("incomplete image")
    check_padding(output, width, height)
    return bytes(output), rows


def verify_vectors(directory, manifest):
    for vector in manifest["vectors"]:
        name = vector["name"]
        if not re.fullmatch(r"[a-z0-9-]+", name):
            raise ValueError("invalid name")
        width, height, packed = read_pbm((directory / f"{name}.pbm").read_bytes())
        reconstructed, rows = decode((directory / f"{name}.acs.zpl").read_bytes(), width, height, vector["bandLimit"])
        if packed != reconstructed or packed != analytic_bitmap(width, height) or rows != vector["bandRows"]:
            raise ValueError("compression oracle mismatch")
    extra = json.loads((directory / "compression.json").read_text())
    patterns = {"white": 0, "black": 255, "nibble": 0x66, "checker": 0xA5}
    if len(extra) != 48 or len({v["name"] for v in extra}) != 48:
        raise ValueError("incomplete compression boundaries")
    for vector in extra:
        stride, pattern = vector["stride"], vector["pattern"]
        if type(stride) is not int or stride not in [1, 2, 3, 9, 10, 19, 20, 199, 200, 201, 400, 801] or pattern not in patterns:
            raise ValueError("invalid compression boundary")
        name = f"compression-{pattern}-{stride}"
        if vector["name"] != name:
            raise ValueError("invalid boundary name")
        packed, rows = decode((directory / f"{name}.acs.zpl").read_bytes(), stride * 8, 3, stride * 2)
        if packed != bytes([patterns[pattern]]) * stride * 3 or rows != [2, 1]:
            raise ValueError("boundary compression mismatch")
    return len(manifest["vectors"]) + len(extra)
