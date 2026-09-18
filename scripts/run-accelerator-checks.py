#!/usr/bin/env python3
"""Offline regression suite. Does not install, print, access GitHub, or require secrets."""
from __future__ import annotations
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from zpl_oracle import verify_vectors
from zpl_compression_oracle import verify_vectors as verify_compressed_vectors
from benchmark_encoding import verify_cli as verify_encoding_benchmark
from check_probe import verify as verify_probe
from check_capture_filter import verify as verify_capture_filter
from check_capture_pipeline import verify as verify_capture_pipeline

ROOT=Path(__file__).resolve().parents[1]
def run(args,timeout=300):
    subprocess.run(args,cwd=ROOT,check=True,timeout=timeout)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--configuration", choices=["debug","release"],default="debug")
    a=p.parse_args()
    run([sys.executable,"scripts/check_repo.py"])
    run([sys.executable,"scripts/check_fixture_manifest.py"])
    run([sys.executable,"-m","unittest","discover","-s","scripts/tests"])
    run(["swift","test","--package-path","Packages/LabelCore","--configuration",a.configuration])
    # Explicit build avoids depending on whether swift test builds every executable.
    run(["swift","build","--package-path","Packages/LabelCore","--configuration",a.configuration])
    binary=Path(subprocess.check_output(["swift","build","--package-path","Packages/LabelCore",
         "--configuration",a.configuration,"--show-bin-path"],cwd=ROOT,text=True,timeout=60).strip())
    with tempfile.TemporaryDirectory(prefix="label-driver-offline-") as tmp:
        vectors=Path(tmp)/"vectors"
        run([str(binary/"label-core-lab"),"--vectors-dir",str(vectors)],timeout=30)
        print(f"Cross-language ZPL/PBM/analytic round-trips: {verify_vectors(vectors)}",flush=True)
        manifest = json.loads((vectors / "vectors.json").read_text())
        print(f"Independent ASCII compression round-trips: {verify_compressed_vectors(vectors, manifest)}",flush=True)
        # The lab must not clobber an existing directory.
        r=subprocess.run([str(binary/"label-core-lab"),"--vectors-dir",str(vectors)],
                         cwd=ROOT,capture_output=True,timeout=10)
        if r.returncode == 0: raise RuntimeError("lab unexpectedly overwrote existing destination")
    print(f"Finite encoding benchmark CLI cases: {verify_encoding_benchmark(binary/'label-core-lab')}",flush=True)
    print(f"Inert CUPS ABI cases: {verify_probe(binary/'labelprobe')}",flush=True)
    print(f"Inert CUPS filter ABI cases: {verify_capture_filter(binary/'labelcapture-filter')}",flush=True)
    print(f"Inert filter-to-discard pipeline cases: {verify_capture_pipeline(binary/'labelcapture-filter',binary/'labelprobe')}",flush=True)
    print("PASS: offline accelerator suite. macOS/scheduler/hardware qualification is separate.")
if __name__=="__main__": main()
