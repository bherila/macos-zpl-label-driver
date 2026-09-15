#!/usr/bin/env python3
"""Reproducible offline release benchmark; never opens a queue or transport."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE = ROOT / "Fixtures/generated/native-vector.pdf"
DEFAULT_TICKET = ROOT / "Examples/offline-ticket-v1.json"
DEFAULT_EXECUTABLE = (
    ROOT / "Packages/LabelMac/.build/arm64-apple-macosx/release/label-driver"
)
REAL_PATTERN = re.compile(r"^\s*([0-9]+(?:\.[0-9]+)?)\s+real\b", re.MULTILINE)
RSS_PATTERN = re.compile(r"^\s*(\d+)\s+maximum resident set size\b", re.MULTILINE)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_time_output(stderr: str) -> tuple[float, int]:
    real_match = REAL_PATTERN.search(stderr)
    rss_match = RSS_PATTERN.search(stderr)
    if not real_match or not rss_match:
        raise ValueError("unrecognized /usr/bin/time -l output")
    return float(real_match.group(1)), int(rss_match.group(1))


def nearest_rank(values: list[float], percentile: float) -> float:
    if not values or not 0 < percentile <= 1:
        raise ValueError("invalid percentile input")
    ordered = sorted(values)
    return ordered[math.ceil(percentile * len(ordered)) - 1]


def summarize(seconds: list[float], rss_bytes: list[int], prepared_bytes: int, pixels: int) -> dict[str, Any]:
    p50 = statistics.median(seconds)
    p95 = nearest_rank(seconds, 0.95)
    return {
        "runs": len(seconds),
        "minimumMilliseconds": min(seconds) * 1000,
        "medianMilliseconds": p50 * 1000,
        "p95Milliseconds": p95 * 1000,
        "maximumMilliseconds": max(seconds) * 1000,
        "maximumResidentBytes": max(rss_bytes),
        "preparedBytesPerSecondAtP95": prepared_bytes / p95,
        "pixelsPerSecondAtP95": pixels / p95,
    }


def checked_output(arguments: list[str]) -> str:
    return subprocess.run(arguments, check=True, capture_output=True, text=True).stdout.strip()


def relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return path.name


def run_once(executable: Path, fixture: Path, ticket: Path) -> tuple[dict[str, Any], float, int]:
    started = time.perf_counter()
    result = subprocess.run(
        [
            "/usr/bin/time",
            "-l",
            str(executable),
            "validate",
            str(fixture),
            "--job-ticket",
            str(ticket),
            "--json",
        ],
        capture_output=True,
        text=True,
    )
    elapsed = time.perf_counter() - started
    if result.returncode != 0:
        raise RuntimeError(f"benchmark conversion failed with exit {result.returncode}: {result.stderr.strip()}")
    payload = json.loads(result.stdout)
    if payload.get("status") != "prepared" or payload.get("printerIOPerformed") is not False:
        raise RuntimeError("benchmark command did not produce an offline prepared result")
    _, rss = parse_time_output(result.stderr)
    return payload, elapsed, rss


def environment() -> dict[str, Any]:
    os_version = checked_output(["/usr/bin/sw_vers", "-productVersion"])
    os_build = checked_output(["/usr/bin/sw_vers", "-buildVersion"])
    model = checked_output(["/usr/sbin/sysctl", "-n", "hw.model"])
    xcode = checked_output(["/usr/bin/xcodebuild", "-version"]).splitlines()
    swift = checked_output(["/usr/bin/xcrun", "swift", "--version"]).splitlines()[0]
    return {
        "referenceMachine": f"Apple Silicon {model}",
        "architecture": platform.machine(),
        "macOSVersion": os_version,
        "macOSBuild": os_build,
        "xcode": " / ".join(xcode),
        "swift": swift,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=20, help="warm timed runs (5-100; default 20)")
    parser.add_argument("--fixture", type=Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--ticket", type=Path, default=DEFAULT_TICKET)
    parser.add_argument("--executable", type=Path, default=DEFAULT_EXECUTABLE)
    parser.add_argument("--output", type=Path, help="exclusive JSON output path; stdout when omitted")
    arguments = parser.parse_args()

    if sys.platform != "darwin" or platform.machine() != "arm64":
        parser.error("the reference benchmark requires Apple Silicon macOS")
    if not 5 <= arguments.runs <= 100:
        parser.error("--runs must be between 5 and 100")
    for label, path in (
        ("fixture", arguments.fixture),
        ("ticket", arguments.ticket),
        ("executable", arguments.executable),
    ):
        if not path.is_file() or path.is_symlink():
            parser.error(f"{label} must be a regular non-symlink file")
    if not os.access(arguments.executable, os.X_OK):
        parser.error("executable is not executable")

    git_head = checked_output(["/usr/bin/git", "-C", str(ROOT), "rev-parse", "HEAD"])
    git_dirty = bool(checked_output(["/usr/bin/git", "-C", str(ROOT), "status", "--porcelain"]))
    cold_payload, cold_seconds, cold_rss = run_once(
        arguments.executable, arguments.fixture, arguments.ticket
    )
    warm_seconds: list[float] = []
    warm_rss: list[int] = []
    expected = {
        key: cold_payload[key]
        for key in ("widthDots", "heightDots", "zplBytes", "formatScope")
    }
    for _ in range(arguments.runs):
        payload, seconds, rss = run_once(arguments.executable, arguments.fixture, arguments.ticket)
        actual = {key: payload[key] for key in expected}
        if actual != expected:
            raise RuntimeError("prepared result changed between benchmark runs")
        warm_seconds.append(seconds)
        warm_rss.append(rss)

    pixels = int(expected["widthDots"]) * int(expected["heightDots"])
    prepared_bytes = int(expected["zplBytes"])
    report = {
        "schemaVersion": 1,
        "scope": "offline-release-render-and-encode-no-transport",
        "coldDefinition": "first timed invocation after an untimed release build; filesystem caches are not purged",
        "warmDefinition": "subsequent separate CLI invocations using identical fixture and ticket bytes",
        "measurementTool": "Python monotonic wall clock around /usr/bin/time -l and label-driver validate; RSS is the command value reported by macOS",
        "gitHead": git_head,
        "gitDirty": git_dirty,
        "environment": environment(),
        "inputs": {
            "fixture": relative(arguments.fixture),
            "fixtureSHA256": sha256(arguments.fixture),
            "ticket": relative(arguments.ticket),
            "ticketSHA256": sha256(arguments.ticket),
            "executable": relative(arguments.executable),
            "executableSHA256": sha256(arguments.executable),
        },
        "prepared": {
            "widthDots": expected["widthDots"],
            "heightDots": expected["heightDots"],
            "pixels": pixels,
            "zplBytes": prepared_bytes,
            "formatScope": expected["formatScope"],
        },
        "cold": {
            "milliseconds": cold_seconds * 1000,
            "maximumResidentBytes": cold_rss,
        },
        "warm": summarize(warm_seconds, warm_rss, prepared_bytes, pixels),
        "rawWarm": [
            {"milliseconds": seconds * 1000, "maximumResidentBytes": rss}
            for seconds, rss in zip(warm_seconds, warm_rss, strict=True)
        ],
        "limitations": [
            "No scheduler, USB transport, printer mechanics, first-label time, or sustained physical rate is measured.",
            "This local baseline is not a shared-runner performance threshold.",
        ],
    }
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        with arguments.output.open("x", encoding="utf-8") as destination:
            destination.write(encoded)
    else:
        sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
