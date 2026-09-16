#!/usr/bin/env python3
"""Finite user-space filter ABI tests. No scheduler, installation or device access."""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import tempfile
import threading
import time
from pathlib import Path


def verify(binary: Path) -> int:
    binary = binary.resolve()
    marker = "PRIVATE-ADDRESS-DO-NOT-LOG"
    env = dict(
        os.environ,
        CONTENT_TYPE="application/pdf",
        FINAL_CONTENT_TYPE="application/vnd.labelprobe",
    )
    args = [
        str(binary), "1", marker, marker, "2",
        "ProbeSpeed='3' ProbeWorkflow=\"Letter\" Private='" + marker + "'",
    ]
    tests = 0

    def run(argv, data=None):
        result = subprocess.run(argv, input=data, capture_output=True, env=env, timeout=15)
        assert marker.encode() not in result.stderr
        if result.returncode != 0:
            assert b"LABEL_CAPTURE_FILTER" not in result.stderr
        return result

    def report(result):
        prefix = b"WARNING: LABEL_CAPTURE_FILTER "
        assert result.returncode == 0 and result.stderr.startswith(prefix), result
        assert len(result.stderr) < 4096 and result.stderr.count(b"\n") == 1
        record = json.loads(result.stderr[len(prefix):])
        assert set(record) == {
            "schemaVersion", "jobID", "auditReason", "mode", "bytesObserved",
            "input", "copiesArgument", "knownOptions", "contentType",
            "finalContentType", "payloadRetained", "physicalOutput",
        }
        assert record["schemaVersion"] == 2 and record["jobID"] == 1
        assert record["auditReason"] == "discard-only-experiment-not-physical-printing"
        return record

    data = b"%PDF-1.7\n" + marker.encode() + b"\n%%EOF\n"
    with tempfile.TemporaryDirectory(prefix="label-capture-filter-test-") as tmp:
        source = Path(tmp) / "input.pdf"
        source.write_bytes(data)
        result = run(args + [str(source)])
        record = report(result)
        assert result.stdout == data
        assert record["bytesObserved"] == len(data) and record["input"] == "file"
        assert record["knownOptions"] == {"ProbeSpeed": "3", "ProbeWorkflow": "Letter"}
        assert record["finalContentType"] == "application/vnd.labelprobe"
        assert record["payloadRetained"] is False and record["physicalOutput"] is False
        tests += 1
        result = run(args, data)
        assert result.stdout == data and report(result)["input"] == "stdin"
        tests += 1
        # The exact finite administrator experiment's complete observation
        # tokens must survive the real option parser and one safe warning.
        experiment = args[:4] + ["1", "PageSize=4x6.Fullbleed ProbeSpeed=3 ProbeDarkness=15 ProbeWorkflow=Native ProbeRotation=90"]
        result = run(experiment, data)
        record = report(result)
        assert result.stdout == data and record["copiesArgument"] == 1
        assert record["contentType"] == "application/pdf"
        assert record["finalContentType"] == "application/vnd.labelprobe"
        assert record["knownOptions"] == {
            "ProbeSpeed": "3", "ProbeDarkness": "15",
            "ProbeWorkflow": "Native", "ProbeRotation": "90",
        }
        tests += 1
        link = Path(tmp) / "input-link.pdf"
        # CUPS' null file destination gives the last filter direct /dev/null
        # stdout, not a pipe to a backend. Darwin poll rejects this descriptor.
        # Exercise both documented input modes with a hard subprocess limit.
        with open(os.devnull, "wb") as discard:
            for argv, incoming, mode in [
                (experiment + [str(source)], None, "file"),
                (experiment, data, "stdin"),
            ]:
                result = subprocess.run(argv, input=incoming, stdout=discard,
                                        stderr=subprocess.PIPE, env=env, timeout=15)
                record = report(result)
                assert record["input"] == mode and record["bytesObserved"] == len(data)
                assert record["physicalOutput"] is False
                assert marker.encode() not in result.stderr
                tests += 1
        link.symlink_to(source)
        huge = Path(tmp) / "huge.pdf"
        with huge.open("wb") as handle:
            handle.truncate(64 * 1024 * 1024 + 1)
        for argv, incoming in [
            ([args[0], "0", *args[2:]], data),
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

        # Begin with a completely full output pipe. A consumer starts after one
        # 250 ms poll interval, so the filter must continue polling until its
        # actual deadline instead of treating one quiet interval as failure.
        reader, writer = os.pipe()
        os.set_blocking(writer, False)
        prefix = bytearray()
        try:
            while True:
                chunk = b"X" * 4096
                prefix.extend(chunk[: os.write(writer, chunk)])
        except BlockingIOError:
            pass
        os.set_blocking(writer, True)
        observed = bytearray()

        def delayed_consumer() -> None:
            time.sleep(0.5)
            while chunk := os.read(reader, 8192):
                observed.extend(chunk)

        consumer = threading.Thread(target=delayed_consumer)
        consumer.start()
        delayed = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=writer, stderr=subprocess.PIPE, env=env)
        os.close(writer)
        _, stderr = delayed.communicate(data, timeout=3)
        consumer.join(timeout=3)
        os.close(reader)
        assert not consumer.is_alive()
        assert delayed.returncode == 0
        report(subprocess.CompletedProcess(args, delayed.returncode, b"", stderr))
        assert bytes(observed) == bytes(prefix) + data
        tests += 1

        # A permanently stalled consumer must end at the real ten-second
        # resource deadline; the nonblocking write may never outlive it.
        reader, writer = os.pipe()
        os.set_blocking(writer, False)
        try:
            while True:
                os.write(writer, b"X" * 4096)
        except BlockingIOError:
            pass
        os.set_blocking(writer, True)
        stalled = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=writer, stderr=subprocess.PIPE, env=env)
        os.close(writer)
        started = time.monotonic()
        _, stderr = stalled.communicate(data, timeout=12)
        elapsed = time.monotonic() - started
        os.close(reader)
        assert stalled.returncode != 0 and 9.0 <= elapsed < 12.0
        assert marker.encode() not in stderr
        tests += 1
    return tests


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    print(f"Inert capture-filter ABI/negative tests passed: {verify(parser.parse_args().binary)} cases")
