#!/usr/bin/env python3
"""Read-only developer M1 verifier. Never installs, submits or changes a job."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import selectors
import stat
import subprocess
import tempfile
import time
from urllib.parse import quote

QUEUE = "LabelProbe_DISCARDS_JOBS"
CLIENT_ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"}
ABSENT_REQUEST = """{
 NAME "Absent experimental queue only"
 OPERATION Get-Printer-Attributes
 GROUP operation-attributes-tag
 ATTR charset attributes-charset utf-8
 ATTR language attributes-natural-language en
 ATTR uri printer-uri ipp://localhost/printers/LabelProbe_DISCARDS_JOBS
 ATTR keyword requested-attributes printer-name
 STATUS client-error-not-found
}
"""
HELD_REQUEST = """{
 NAME "Experimental queue remains stopped rejecting and unshared"
 OPERATION Get-Printer-Attributes
 GROUP operation-attributes-tag
 ATTR charset attributes-charset utf-8
 ATTR language attributes-natural-language en
 ATTR uri printer-uri ipp://localhost/printers/LabelProbe_DISCARDS_JOBS
 ATTR keyword requested-attributes printer-state,printer-is-accepting-jobs,printer-is-shared
 STATUS successful-ok
 EXPECT printer-state OF-TYPE enum COUNT 1 WITH-VALUE 5
 EXPECT printer-is-accepting-jobs OF-TYPE boolean COUNT 1 WITH-VALUE false
 EXPECT printer-is-shared OF-TYPE boolean COUNT 1 WITH-VALUE false
}
{
 NAME "Only the expected held job is outstanding"
 SKIP-PREVIOUS-ERROR yes
 OPERATION Get-Jobs
 GROUP operation-attributes-tag
 ATTR charset attributes-charset utf-8
 ATTR language attributes-natural-language en
 ATTR uri printer-uri ipp://localhost/printers/LabelProbe_DISCARDS_JOBS
 ATTR keyword which-jobs not-completed
 ATTR boolean my-jobs false
 ATTR keyword requested-attributes job-id,job-state,job-printer-uri
 STATUS successful-ok
 EXPECT-ALL job-id IN-GROUP job-attributes-tag OF-TYPE integer COUNT 1 WITH-VALUE $jobid
 EXPECT-ALL job-state IN-GROUP job-attributes-tag OF-TYPE enum COUNT 1 WITH-VALUE 4
 EXPECT-ALL job-printer-uri IN-GROUP job-attributes-tag OF-TYPE uri COUNT 1 WITH-RESOURCE /printers/LabelProbe_DISCARDS_JOBS
}
{
 NAME "Expected single-document one-copy held PDF attributes"
 SKIP-PREVIOUS-ERROR yes
 OPERATION Get-Job-Attributes
 GROUP operation-attributes-tag
 ATTR charset attributes-charset utf-8
 ATTR language attributes-natural-language en
 ATTR uri job-uri ipp://localhost/jobs/$jobid
 ATTR keyword requested-attributes job-id,job-state,job-printer-uri,number-of-documents,copies,document-format-supplied,job-hold-until
 STATUS successful-ok
 EXPECT job-id IN-GROUP job-attributes-tag OF-TYPE integer COUNT 1 WITH-VALUE $jobid
 EXPECT job-state IN-GROUP job-attributes-tag OF-TYPE enum COUNT 1 WITH-VALUE 4
 EXPECT job-printer-uri IN-GROUP job-attributes-tag OF-TYPE uri COUNT 1 WITH-RESOURCE /printers/LabelProbe_DISCARDS_JOBS
 EXPECT number-of-documents IN-GROUP job-attributes-tag OF-TYPE integer COUNT 1 WITH-VALUE 1
 EXPECT copies IN-GROUP job-attributes-tag OF-TYPE integer COUNT 1 WITH-VALUE 1
 EXPECT document-format-supplied IN-GROUP job-attributes-tag OF-TYPE mimeMediaType COUNT 1 WITH-VALUE application/pdf
 EXPECT job-hold-until IN-GROUP job-attributes-tag OF-TYPE keyword COUNT 1 WITH-VALUE indefinite
}
"""


class Rejected(Exception):
    pass


def parse_job_id(value: str) -> str:
    if not re.fullmatch(r"[1-9][0-9]{0,9}", value) or int(value) > 2_147_483_647:
        raise Rejected("ARGUMENTS_INVALID")
    return value


def socket_uri(path: str) -> str:
    if not path.startswith("/") or len(path) > 4096 or any(ord(c) < 32 for c in path):
        raise Rejected("LOCAL_SOCKET_INVALID")
    metadata = os.lstat(path)
    if not stat.S_ISSOCK(metadata.st_mode) or metadata.st_uid != 0:
        raise Rejected("LOCAL_SOCKET_INVALID")
    # The observed macOS /private/var/run is root:daemon (0:1), mode 775.
    # This is OS namespace inspection, not cryptographic server authentication.
    for parent in (Path(path).parent.resolve(), *Path(path).parent.resolve().parents):
        metadata = parent.stat()
        if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0
                or metadata.st_mode & 0o002
                or (metadata.st_mode & 0o020 and metadata.st_gid not in (0, 1))):
            raise Rejected("LOCAL_SOCKET_PARENT_INVALID")
    return f"ipp://{quote(path, safe='')}/printers/{QUEUE}"


def bounded_command(argv: list[str], deadline: float, maximum_bytes: int = 65_536) -> bytes:
    if time.monotonic() >= deadline:
        raise Rejected("READBACK_TIMEOUT")
    child = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             env=CLIENT_ENV, stdin=subprocess.DEVNULL)
    assert child.stdout is not None
    try:
        os.set_blocking(child.stdout.fileno(), False)
        output = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise Rejected("READBACK_TIMEOUT")
                if not selector.select(min(remaining, 0.1)):
                    continue
                chunk = os.read(child.stdout.fileno(), min(4096, maximum_bytes + 1 - len(output)))
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > maximum_bytes:
                    raise Rejected("READBACK_OUTPUT_LIMIT")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise Rejected("READBACK_TIMEOUT")
        try:
            status = child.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            raise Rejected("READBACK_TIMEOUT") from None
        if status != 0:
            raise Rejected("READBACK_REJECTED")
        return bytes(output)
    finally:
        try:
            if child.poll() is None:
                try:
                    child.kill()
                except ProcessLookupError:
                    pass
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    # Never fall back to Popen.__exit__'s unbounded wait or
                    # describe an unconfirmed termination as successful cleanup.
                    raise Rejected("READBACK_TERMINATION_UNCONFIRMED") from None
        finally:
            child.stdout.close()


def verify(job_id: str | None) -> None:
    if "CUPS_SERVER" in os.environ or "IPP_PORT" in os.environ:
        raise Rejected("REMOTE_OVERRIDE_REJECTED")
    if job_id is not None:
        job_id = parse_job_id(job_id)
    deadline = time.monotonic() + 20
    discovered = bounded_command(["/usr/bin/lpstat", "-H"], deadline)
    if not discovered.endswith(b"\n") or discovered.count(b"\n") != 1:
        raise Rejected("LOCAL_SOCKET_INVALID")
    observed = discovered[:-1].decode("utf-8")
    uri = socket_uri(observed)
    if bounded_command(["/usr/bin/lpstat", "-h", observed, "-r"], deadline) != b"scheduler is running\n":
        raise Rejected("SCHEDULER_UNREACHABLE")
    if job_id is not None:
        actual = bounded_command(["/usr/bin/lpstat", "-h", observed, "-v", QUEUE], deadline)
        if actual != f"device for {QUEUE}: file:///dev/null\n".encode():
            raise Rejected("DISCARD_URI_MISMATCH")
    # Immutable program literals only: no external instruction file, INCLUDE,
    # FILE, repeat directive or caller-provided operation/URI can be selected.
    with tempfile.TemporaryDirectory(prefix="label-m1-readback-") as directory:
        request = Path(directory) / "readonly.test"
        with request.open("x", encoding="utf-8") as stream:
            stream.write(ABSENT_REQUEST if job_id is None else HELD_REQUEST)
        argv = ["/usr/bin/ipptool", "-T", "5", "-q"]
        if job_id is not None:
            argv += ["-d", f"jobid={job_id}"]
        bounded_command([*argv, uri, str(request)], deadline)


class SafeParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise Rejected("ARGUMENTS_INVALID")


def main() -> int:
    try:
        parser = SafeParser(prog="check-m1-ipp-readback", description=__doc__)
        mode = parser.add_mutually_exclusive_group(required=True)
        mode.add_argument("--queue-absent", action="store_true")
        mode.add_argument("--held-job", metavar="JOB_ID")
        args = parser.parse_args()
        verify(args.held_job)
        print(json.dumps({"schemaVersion": 1, "result": "pass",
                          "scope": "queue-absent" if args.queue_absent else "held-job-readback",
                          "mutationsPerformed": False, "physicalOutput": False}, sort_keys=True))
        return 0
    except Rejected as error:
        print(json.dumps({"result": "fail", "code": str(error)}, sort_keys=True))
    except (OSError, UnicodeError, subprocess.TimeoutExpired):
        print(json.dumps({"result": "fail", "code": "READBACK_UNAVAILABLE"}, sort_keys=True))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
