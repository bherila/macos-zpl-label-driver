#!/usr/bin/env python3
"""Fail-open-to-testing change classifier. Never skip compilation on uncertain input."""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import PurePosixPath


def needs_swift(paths: list[str]) -> bool:
    if not paths:
        return True
    for name in paths:
        path = PurePosixPath(name)
        is_documentation = path.suffix == ".md" or name in {"LICENSE", "docs/PROGRESS.json", "docs/milestones.json", "docs/requirements.json"}
        if not is_documentation:
            return True
    return False


def classify(base: str, head: str) -> bool:
    if not re.fullmatch(r"[0-9a-f]{40}", base) or not re.fullmatch(r"[0-9a-f]{40}", head):
        return True
    if base == "0" * 40:
        return True
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "-z", base, head, "--"],
            check=True, capture_output=True, timeout=30,
        )
        paths = [entry.decode("utf-8", errors="strict") for entry in result.stdout.split(b"\0") if entry]
        return needs_swift(paths)
    except (subprocess.SubprocessError, UnicodeError, OSError):
        return True


def main() -> int:
    needed = classify(os.environ.get("BASE_SHA", ""), os.environ.get("HEAD_SHA", ""))
    line = f"swift_changed={'true' if needed else 'false'}\n"
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(line)
    print(line, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
