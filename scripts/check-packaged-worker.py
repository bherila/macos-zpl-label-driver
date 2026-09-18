#!/usr/bin/env python3
"""Finite synthetic execution/equality check, not GUI or install acceptance."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def render(executable: Path):
    if executable.is_symlink() or not executable.is_file():
        raise ValueError("worker executable unavailable")
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="label-packaged-worker.") as scratch:
        directory = Path(scratch)
        (directory / "input.pdf").write_bytes((root / "Fixtures/generated/native-vector.pdf").read_bytes())
        ticket = {"schemaVersion": 1, "pageNumber": 1,
                  "physicalSize": {"widthMillimeters": 10, "heightMillimeters": 10},
                  "resolution": {"xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1},
                  "conversion": {"mode": "textAndBarcodeThreshold", "cutoff": 128}}
        (directory / "ticket.json").write_text(json.dumps(ticket), encoding="utf-8")
        for name in ("input.pdf", "ticket.json"):
            (directory / name).chmod(0o600)
        subprocess.run([str(executable.resolve()), "--job-directory", scratch], check=True,
                       timeout=10, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        result = json.loads((directory / "result.json").read_bytes())
        preview = (directory / "preview.pbm").read_bytes()
        zpl = (directory / "prepared.zpl").read_bytes()
        if (result.get("schemaVersion"), result.get("widthDots"), result.get("heightDots")) != (1, 10, 10):
            raise ValueError("unexpected worker canvas")
        if not preview.startswith(b"P4\n10 10\n") or len(preview) != len(b"P4\n10 10\n") + 20:
            raise ValueError("unexpected packed preview")
        if result.get("previewBytes") != len(preview) or result.get("zplBytes") != len(zpl):
            raise ValueError("unexpected worker byte counts")
        return preview, zpl


def main():
    if len(sys.argv) != 3:
        raise ValueError("expected packaged and reference worker executables")
    if render(Path(sys.argv[1])) != render(Path(sys.argv[2])):
        raise ValueError("packaged output differs from reference worker")
    print("Packaged worker synthetic PBM/ZPL equals release worker. No printer accessed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("Packaged worker validation failed safely.", file=sys.stderr)
        sys.exit(1)
