#!/usr/bin/env python3
"""Exercise the inert filter-to-discard-backend pipeline without CUPS or a device."""
from __future__ import annotations
import argparse
import json
import os
import subprocess
from pathlib import Path


def verify(filter_binary: Path, probe_binary: Path) -> int:
    marker = "PRIVATE-ADDRESS-DO-NOT-LOG"
    options = "ProbeSpeed=3 ProbeDarkness=15 ProbeWorkflow=Letter ProbeRotation=90 Private='" + marker + "'"
    args = ["1", marker, marker, "2", options]
    environment = dict(os.environ, DEVICE_URI="labelprobe://discard", CONTENT_TYPE="application/pdf")
    probe = subprocess.Popen([str(probe_binary.resolve()), *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    assert probe.stdin is not None
    capture = subprocess.Popen([str(filter_binary.resolve()), *args], stdin=subprocess.PIPE, stdout=probe.stdin, stderr=subprocess.PIPE, env=environment)
    probe.stdin.close()
    assert capture.stdin is not None
    data = b"%PDF-1.7\n" + marker.encode() + b"\n%%EOF\n"
    _, filter_stderr = capture.communicate(data, timeout=15)
    probe_stdout = probe.stdout.read() if probe.stdout else b""
    probe_stderr = probe.stderr.read() if probe.stderr else b""
    assert capture.returncode == 0 and probe.wait(timeout=15) == 0
    assert probe_stdout == b""
    assert marker.encode() not in filter_stderr + probe_stderr
    filter_prefix = b"INFO: LABEL_CAPTURE_FILTER "
    probe_prefix = b"INFO: LABEL_PROBE "
    assert filter_stderr.startswith(filter_prefix) and probe_stderr.startswith(probe_prefix)
    filter_record = json.loads(filter_stderr[len(filter_prefix):])
    probe_record = json.loads(probe_stderr[len(probe_prefix):])
    expected_options = {"ProbeSpeed": "3", "ProbeDarkness": "15", "ProbeWorkflow": "Letter", "ProbeRotation": "90"}
    assert filter_record["bytesObserved"] == len(data)
    assert probe_record["bytesObserved"] == len(data)
    assert filter_record["knownOptions"] == expected_options == probe_record["knownOptions"]
    assert probe_record["physicalOutput"] is False and filter_record["payloadRetained"] is False
    return 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("filter_binary", type=Path)
    parser.add_argument("probe_binary", type=Path)
    print(f"Inert filter-to-discard pipeline passed: {verify(**vars(parser.parse_args()))} case")
