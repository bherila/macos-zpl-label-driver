"""Finite synthetic lab failure checks; no printer, source documents or network."""
from pathlib import Path
import subprocess
import tempfile


def verify(binary: Path) -> int:
    marker = "synthetic-private-identifier"
    with tempfile.TemporaryDirectory(prefix="label-lab-diagnostics-") as tmp:
        blocker = Path(tmp) / marker
        original = b"synthetic inert blocker"
        blocker.write_bytes(original)
        destinations = [blocker / "vectors", blocker]
        for destination in destinations:
            result = subprocess.run([str(binary), "--vectors-dir", str(destination)],
                capture_output=True, timeout=10)
            if result.returncode != 2 or result.stdout:
                raise RuntimeError("lab failure lost exit/output contract")
            if not result.stderr or marker.encode() in result.stderr or str(destination).encode() in result.stderr:
                raise RuntimeError("lab failure exposed caller destination or lacked diagnostics")
            if blocker.read_bytes() != original:
                raise RuntimeError("lab failure modified existing caller file")
        if list(Path(tmp).iterdir()) != [blocker]:
            raise RuntimeError("lab failure left unexpected output")
    return len(destinations)
