#!/usr/bin/env python3
"""Finite synthetic encoding benchmark and portable CLI contract checks; no transport."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
from benchmark_offline import checked_output, environment, parse_time_output, nearest_rank

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = ("white", "checker", "analytic")
ENCODINGS = ("plain", "ascii")
FIELDS = {"schemaVersion", "scope", "encoding", "pattern", "iterations", "widthDots",
          "heightDots", "packedBytes", "outputBytes", "encodingNanoseconds"}


def validate_report(report, encoding, pattern, iterations):
    if not isinstance(report, dict) or set(report) != FIELDS:
        raise ValueError("unexpected encoding benchmark schema")
    expected = {"schemaVersion": 1, "scope": "offline-encoding-no-transport",
                "encoding": encoding, "pattern": pattern, "iterations": iterations,
                "widthDots": 813, "heightDots": 1219, "packedBytes": 124338}
    for key, value in expected.items():
        if type(report[key]) is not type(value) or report[key] != value:
            raise ValueError("encoding benchmark identity mismatch")
    if encoding not in ENCODINGS or pattern not in PATTERNS or type(iterations) is not int or not 1 <= iterations <= 100:
        raise ValueError("invalid finite benchmark identity")
    if type(report["outputBytes"]) is not int or not 0 < report["outputBytes"] <= 64 * 1024 * 1024:
        raise ValueError("invalid output budget")
    samples = report["encodingNanoseconds"]
    if not isinstance(samples, list) or len(samples) != iterations or any(
        type(value) is not int or not 0 < value <= 120_000_000_000 for value in samples
    ):
        raise ValueError("invalid bounded timing samples")
    return report


def verify_cli(executable):
    for encoding in ENCODINGS:
        for pattern in PATTERNS:
            result = subprocess.run([str(executable), "--benchmark-encoding", encoding, pattern, "1"],
                check=True, capture_output=True, text=True, timeout=30)
            validate_report(json.loads(result.stdout), encoding, pattern, 1)
    for args in [("plain", "white", "0"), ("ascii", "white", "101"),
                 ("other", "white", "1"), ("plain", "other", "1"),
                 ("ascii", "white", "NaN"), ("plain", "white")]:
        result = subprocess.run([str(executable), "--benchmark-encoding", *args],
            capture_output=True, text=True, timeout=10)
        if result.returncode != 2 or result.stdout:
            raise RuntimeError("invalid benchmark arguments emitted a result")
    return 12


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin" or platform.machine() != "arm64":
        parser.error("reference RSS measurement requires Apple Silicon macOS")
    if not 5 <= args.iterations <= 100:
        parser.error("iterations must be 5-100")
    if args.executable.is_symlink() or not args.executable.is_file() or not os.access(args.executable, os.X_OK):
        parser.error("executable must be an executable regular non-symlink file")
    cases = []
    for pattern in PATTERNS:
        for encoding in ENCODINGS:
            result = subprocess.run(["/usr/bin/time", "-l", str(args.executable),
                "--benchmark-encoding", encoding, pattern, str(args.iterations)],
                check=True, capture_output=True, text=True, timeout=30)
            report = validate_report(json.loads(result.stdout), encoding, pattern, args.iterations)
            process_seconds, rss = parse_time_output(result.stderr)
            seconds = [value / 1e9 for value in report["encodingNanoseconds"]]
            p95 = nearest_rank(seconds, 0.95)
            cases.append({**report, "p95EncodingMilliseconds": p95 * 1000,
                "packedBytesPerSecondAtP95": report["packedBytes"] / p95,
                "processSeconds": process_seconds, "maximumResidentBytes": rss})
    report = {"schemaVersion": 1, "scope": "offline-encoding-no-transport",
        "sourceHead": checked_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
        "sourceDirty": bool(checked_output(["git", "-C", str(ROOT), "status", "--porcelain"])),
        "executableSHA256": hashlib.sha256(args.executable.read_bytes()).hexdigest(),
        "environment": environment(), "cases": cases,
        "limitations": ["Use an explicitly built release executable; build mode is not inferred from a signature.",
            "Timings exclude bitmap generation, process startup and the untimed warm-up.",
            "RSS covers the whole process, including source, retained expected output and timed output; it is not allocation counting.",
            "No PDF rendering, scheduler, transport, mechanics or firmware qualification; no shared-runner threshold."]}
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        with args.output.open("x", encoding="utf-8") as destination:
            destination.write(encoded)
    else:
        sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
