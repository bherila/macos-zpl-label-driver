#!/usr/bin/env python3
"""Finite user-space filter ABI tests. No scheduler, installation or device access."""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path


def verify(binary: Path) -> int:
    binary = binary.resolve()
    marker = "PRIVATE-ADDRESS-DO-NOT-LOG"
    env = dict(os.environ, CONTENT_TYPE="application/pdf")
    args = [
        str(binary), "1", marker, marker, "2",
        "ProbeSpeed='3' ProbeWorkflow=\"Letter\" Private='" + marker + "'",
    ]
    tests = 0

    def run(argv, data=None):
        result = subprocess.run(argv, input=data, capture_output=True, env=env, timeout=15)
        assert marker.encode() not in result.stderr
        return result

    def report(result):
        prefix = b"INFO: LABEL_CAPTURE_FILTER "
        assert result.returncode == 0 and result.stderr.startswith(prefix), result
        return json.loads(result.stderr[len(prefix):])

    data = b"%PDF-1.7\n" + marker.encode() + b"\n%%EOF\n"
    with tempfile.TemporaryDirectory(prefix="label-capture-filter-test-") as tmp:
        source = Path(tmp) / "input.pdf"
        source.write_bytes(data)
        result = run(args + [str(source)])
        record = report(result)
        assert result.stdout == data
        assert record["bytesObserved"] == len(data) and record["input"] == "file"
        assert record["knownOptions"] == {"ProbeSpeed": "3", "ProbeWorkflow": "Letter"}
        assert record["payloadRetained"] is False and record["physicalOutput"] is False
        tests += 1
        result = run(args, data)
        assert result.stdout == data and report(result)["input"] == "stdin"
        tests += 1
        link = Path(tmp) / "input-link.pdf"
        link.symlink_to(source)
        huge = Path(tmp) / "huge.pdf"
        with huge.open("wb") as handle:
            handle.truncate(64 * 1024 * 1024 + 1)
        for argv, incoming in [
            (args[:5] + ["ProbeSpeed=99"], data),
            (args + [str(link)], None),
            (args + [str(huge)], None),
            (args, b""),
        ]:
            result = run(argv, incoming)
            assert result.returncode != 0 and result.stdout == b""
            tests += 1

        # A scheduler cancellation can arrive while stdin is still open. The
        # filter must not wait for its ordinary input deadline or report a
        # successful pass-through. The process-level signal semantics are what
        # CUPS observes; this harness deliberately does not treat it as a
        # scheduler integration result.
        cancelled = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            time.sleep(0.1)
            cancelled.terminate()
            stdout, stderr = cancelled.communicate(timeout=3)
        finally:
            if cancelled.poll() is None:
                cancelled.kill()
                cancelled.wait(timeout=3)
        assert cancelled.returncode != 0 and stdout == b""
        assert marker.encode() not in stderr
        tests += 1

        # With no reader on stdout, SIGPIPE is ignored by the filter and the
        # write reports a bounded output failure. This protects the scheduler
        # from a false success when the next filter/backend has already gone
        # away, without retaining the private test payload in diagnostics.
        reader, writer = os.pipe()
        os.close(reader)
        broken = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=writer, stderr=subprocess.PIPE, env=env)
        os.close(writer)
        _, stderr = broken.communicate(data, timeout=3)
        assert broken.returncode != 0
        assert marker.encode() not in stderr
        tests += 1
    return tests


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    print(f"Inert capture-filter ABI/negative tests passed: {verify(parser.parse_args().binary)} cases")
