#!/usr/bin/env python3
"""Finite user-space ABI tests. No scheduler, installation, queues or device access."""
from __future__ import annotations
import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path


def verify(binary: Path) -> int:
    binary = binary.resolve()
    env = dict(os.environ, DEVICE_URI="labelprobe://discard", CONTENT_TYPE="application/pdf")
    marker = "PRIVATE-ADDRESS-DO-NOT-LOG"
    args = [str(binary), "1", marker, marker, "2", "ProbeSpeed=3 ProbeWorkflow=Letter Private='" + marker + "'"]
    tests = 0
    def run(argv, data=None, overrides=None):
        result = subprocess.run(argv,input=data,capture_output=True,env=dict(env,**(overrides or {})),timeout=15)
        assert marker.encode() not in result.stdout + result.stderr
        return result
    def report(result):
        assert result.returncode == 0 and result.stdout == b"", result
        prefix = b"INFO: LABEL_PROBE "
        assert result.stderr.startswith(prefix)
        return json.loads(result.stderr[len(prefix):])
    discovery = run([str(binary)])
    assert discovery.returncode == 0 and b"labelprobe://discard" in discovery.stdout
    tests += 1
    data = b"%PDF-1.7\n" + marker.encode() + b"\n%%EOF\n"
    with tempfile.TemporaryDirectory(prefix="label-probe-test-") as tmp:
        file = Path(tmp)/"input.pdf"; file.write_bytes(data)
        r = report(run(args + [str(file)]))
        assert r["bytesObserved"] == len(data) and r["copiesArgument"] == 2
        assert r["knownOptions"] == {"ProbeSpeed":"3","ProbeWorkflow":"Letter"}
        assert r["detectedSignature"] == "pdf-signature" and r["payloadRetained"] is False
        tests += 1
        r2 = report(run(args,data))
        assert r2["input"] == "stdin" and r2["bytesObserved"] == len(data)
        tests += 1
        for badargs, inp, overrides in [
            (args, data, {"DEVICE_URI":"usb://must-never-open"}),
            (args, b"", {}),
            (args[:4]+["0"]+args[5:], data, {}),
            (args[:5]+["ProbeSpeed=99"], data, {}),
            (args[:5]+["ProbeSpeed=2 ProbeSpeed=3"], data, {}),
            (args+[str(Path(tmp)/"missing")], None, {}),
            (args+[str(Path(tmp))], None, {}),
        ]:
            r = run(badargs,inp,overrides); assert r.returncode != 0 and not r.stdout
            tests += 1
        link=Path(tmp)/"link.pdf"; link.symlink_to(file)
        assert run(args+[str(link)]).returncode != 0; tests+=1
        # A raw stream is observed, never represented as valid PDF rendering.
        r=report(run(args,b"not-a-pdf")); assert r["detectedSignature"]=="unknown-signature"; tests+=1
        # Oversized regular input: sparse file, no memory-heavy payload generation.
        huge=Path(tmp)/"huge"
        with huge.open("wb") as f: f.truncate(64*1024*1024+1)
        assert run(args+[str(huge)]).returncode != 0; tests+=1
        p=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
        try:
            time.sleep(0.05); p.send_signal(signal.SIGTERM)
            out,err=p.communicate(timeout=3)
            assert p.returncode != 0 and not out and b"LABEL_PROBE" not in err
        finally:
            if p.poll() is None: p.kill(); p.wait()
        tests+=1
        # EOF withheld: fixed backend timeout must terminate instead of hanging.
        p=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
        try:
            p.wait(timeout=13)
            assert p.returncode != 0
        finally:
            if p.poll() is None: p.kill(); p.wait()
            for stream in (p.stdin,p.stdout,p.stderr): stream.close()
        tests+=1
    return tests

if __name__ == "__main__":
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("binary",type=Path)
    print(f"Inert probe ABI/negative tests passed: {verify(p.parse_args().binary)} cases")
