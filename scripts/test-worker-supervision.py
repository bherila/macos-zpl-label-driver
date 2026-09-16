#!/usr/bin/env python3
"""Finite native child-lifetime tests; no document, printer or privilege I/O."""
import os
import fcntl
import json
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
import uuid


def main():
    executable = str(Path(sys.argv[1]).resolve())
    if len(sys.argv) == 4 and sys.argv[2] == "--parent-harness":
        directory = Path(sys.argv[3])
        info = directory.stat()
        token = str(uuid.uuid4())
        record = {"schemaVersion": 1, "parentPID": os.getpid(), "ownerUID": os.geteuid(),
                  "device": info.st_dev, "inode": info.st_ino, "token": token}
        marker = os.open(directory / "ownership.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(marker, json.dumps(record, sort_keys=True, separators=(",", ":")).encode())
        fcntl.flock(marker, fcntl.LOCK_SH | fcntl.LOCK_NB)
        source = os.open(directory / "input.pdf", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(source, b"synthetic staged source")
        os.close(source)
        child = subprocess.Popen([executable, "5", str(directory), token], stdout=subprocess.PIPE)
        if not select.select([child.stdout], [], [], 2)[0] or child.stdout.readline() != b"ready\n":
            child.kill()
            child.wait(timeout=2)
            raise ValueError("fixture not ready")
        print(child.pid, flush=True)
        time.sleep(10)  # Finite even if the owning test fails.
        return

    result = subprocess.run([executable, "0.15"], capture_output=True, timeout=2)
    if result.returncode != 124 or result.stdout != b"ready\n":
        raise ValueError("independent deadline failed")
    parent = subprocess.Popen([sys.executable, __file__, executable, "--parent-harness", sys.argv[2]],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        if not select.select([parent.stdout], [], [], 3)[0]:
            raise ValueError("parent not ready")
        child_pid = int(parent.stdout.readline())
        parent.send_signal(signal.SIGKILL)
        parent.wait(timeout=2)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                os.kill(child_pid, 0)
            except ProcessLookupError:
                print("Native worker independent deadline and parent-death cases passed.")
                return
            time.sleep(0.02)
        # Never signal an orphan PID after identity uncertainty/PID reuse.
        # The fixture's own main-thread hold ends after ten seconds even if broken.
        raise ValueError("orphan did not terminate")
    finally:
        if parent.poll() is None:
            parent.kill()
            parent.wait(timeout=2)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError):
        print("Worker supervision regression failed safely.", file=sys.stderr)
        sys.exit(1)
