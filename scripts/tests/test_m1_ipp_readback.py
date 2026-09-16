from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.parse import quote

SOURCE = Path(__file__).resolve().parents[1] / "check_m1_ipp_readback.py"
SPEC = importlib.util.spec_from_file_location("m1_ipp_readback", SOURCE)
assert SPEC and SPEC.loader
readback = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(readback)


class M1IPPReadbackTests(unittest.TestCase):
    def test_job_selector_is_only_a_positive_cups_integer(self):
        for value in ["1", "207", "2147483647"]:
            self.assertEqual(readback.parse_job_id(value), value)
        for value in ["0", "-1", "01", "1\n", "1;print", "", "2147483648"]:
            with self.assertRaises(readback.Rejected):
                readback.parse_job_id(value)

    def test_remote_overrides_stop_before_any_client_call(self):
        for name in ["CUPS_SERVER", "IPP_PORT"]:
            with patch.dict(os.environ, {name: ""}), patch.object(readback, "bounded_command") as client:
                with self.assertRaisesRegex(readback.Rejected, "REMOTE_OVERRIDE_REJECTED"):
                    readback.verify(None)
                client.assert_not_called()

    def test_endpoint_requires_a_socket_not_a_regular_file_or_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "file"
            path.touch()
            link = Path(directory) / "link"
            link.symlink_to(path)
            for candidate in [str(path), str(link), "remote.example", "/socket\nnoise"]:
                with self.assertRaises(readback.Rejected):
                    readback.socket_uri(candidate)

    def test_nonroot_socket_is_rejected(self):
        metadata = type("Metadata", (), {"st_mode": stat.S_IFSOCK | 0o777, "st_uid": 12345})()
        with patch.object(readback.os, "lstat", return_value=metadata):
            with self.assertRaisesRegex(readback.Rejected, "LOCAL_SOCKET_INVALID"):
                readback.socket_uri("/synthetic/socket")

    def test_native_client_environment_is_controlled(self):
        self.assertEqual(readback.CLIENT_ENV, {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"})

    def test_root_daemon_parent_is_explicit_but_unsafe_ancestors_fail(self):
        socket_metadata = type("Metadata", (), {"st_mode": stat.S_IFSOCK | 0o666, "st_uid": 0})()
        for uid, gid, mode, accepted in [(0, 1, 0o775, True), (0, 0, 0o755, True),
                                         (12345, 1, 0o775, False), (0, 12345, 0o775, False),
                                         (0, 1, 0o777, False)]:
            parent = type("Metadata", (), {"st_mode": stat.S_IFDIR | mode, "st_uid": uid, "st_gid": gid})()
            with patch.object(readback.os, "lstat", return_value=socket_metadata), \
                    patch.object(readback.Path, "resolve", return_value=Path("/synthetic")), \
                    patch.object(readback.Path, "stat", return_value=parent):
                if accepted:
                    self.assertEqual(readback.socket_uri("/synthetic/socket"),
                                     f"ipp://%2Fsynthetic%2Fsocket/printers/{readback.QUEUE}")
                else:
                    with self.assertRaises(readback.Rejected):
                        readback.socket_uri("/synthetic/socket")

    def test_program_requests_are_readonly_and_fail_closed(self):
        import re
        allowed = {"Get-Printer-Attributes", "Get-Jobs", "Get-Job-Attributes"}
        for request in [readback.ABSENT_REQUEST, readback.HELD_REQUEST]:
            self.assertLess(len(request.encode()), 8192)
            self.assertTrue(set(re.findall(r"OPERATION (\S+)", request)) <= allowed)
            for forbidden in ["FILE ", "INCLUDE ", "REPEAT-", "DEFINE-", "IGNORE-ERRORS yes", "SKIP-IF"]:
                self.assertNotIn(forbidden, request)
            for private in ["job-name", "job-originating-user-name", "device-uri"]:
                self.assertNotIn(private, request)
        self.assertIn("EXPECT-ALL job-id", readback.HELD_REQUEST)
        self.assertIn("WITH-VALUE $jobid", readback.HELD_REQUEST)
        self.assertIn("EXPECT number-of-documents", readback.HELD_REQUEST)
        self.assertIn("EXPECT copies", readback.HELD_REQUEST)

    def test_changed_device_uri_stops_before_any_job_query(self):
        replies = [b"/synthetic/socket\n", b"scheduler is running\n",
                   f"device for {readback.QUEUE}: usb://SYNTHETIC\n".encode()]
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(readback, "socket_uri", return_value="ipp://%2Fsynthetic%2Fsocket/printers/LabelProbe_DISCARDS_JOBS"), \
                patch.object(readback, "bounded_command", side_effect=replies) as client:
            with self.assertRaisesRegex(readback.Rejected, "DISCARD_URI_MISMATCH"):
                readback.verify("207")
            self.assertEqual(client.call_count, 3)
            self.assertTrue(all(call.args[0][0] == "/usr/bin/lpstat" for call in client.call_args_list))

    def test_unsuccessful_namespace_query_is_not_absence(self):
        with self.assertRaisesRegex(readback.Rejected, "READBACK_REJECTED"):
            readback.bounded_command([sys.executable, "-c", "raise SystemExit(1)"], time.monotonic() + 3)

    def test_bounded_command_captures_without_forwarding_child_metadata(self):
        result = readback.bounded_command([sys.executable, "-c", "print('PRIVATE-TEST-MARKER')"],
                                          time.monotonic() + 3)
        self.assertEqual(result, b"PRIVATE-TEST-MARKER\n")

    def test_bounded_command_rejects_excess_output(self):
        with self.assertRaisesRegex(readback.Rejected, "READBACK_OUTPUT_LIMIT"):
            readback.bounded_command([sys.executable, "-c", "print('x'*100000)"],
                                     time.monotonic() + 3, maximum_bytes=64)

    def test_bounded_command_deadline_kills_and_reaps_only_owned_child(self):
        started = time.monotonic()
        with self.assertRaisesRegex(readback.Rejected, "READBACK_TIMEOUT"):
            readback.bounded_command([sys.executable, "-c", "import time; time.sleep(5)"], started + 0.2)
        self.assertLess(time.monotonic() - started, 2)

    def test_invalid_cli_does_not_echo_private_arguments(self):
        result = subprocess.run([sys.executable, str(SOURCE), "--private=PRIVATE-TEST-MARKER"],
                                capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["code"], "ARGUMENTS_INVALID")
        self.assertNotIn(b"PRIVATE-TEST-MARKER", result.stdout + result.stderr)

    @unittest.skipUnless(sys.platform == "darwin", "native macOS CUPS client route")
    def test_native_ipptool_uses_percent_escaped_unix_socket_host(self):
        # One finite HTTP 503 fixture, not an IPP server/decoder or scheduler.
        # It proves that the real native client connects to this owned Unix
        # socket rather than interpreting the encoded host as a TCP destination.
        self.assertTrue(Path("/usr/bin/ipptool").is_file())
        with tempfile.TemporaryDirectory(prefix="label-ipp-route-") as directory:
            path = str(Path(directory) / "socket")
            request = Path(directory) / "readonly.test"
            request.write_text(readback.ABSENT_REQUEST)
            observed = []
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                listener.bind(path)
                listener.listen(1)
                listener.settimeout(2)

                def serve():
                    try:
                        connection, _ = listener.accept()
                        with connection:
                            connection.settimeout(2)
                            header = bytearray()
                            while b"\r\n\r\n" not in header and len(header) < 8192:
                                chunk = connection.recv(1024)
                                if not chunk:
                                    break
                                header.extend(chunk)
                            observed.append(header.startswith(b"POST /printers/LabelProbe_DISCARDS_JOBS "))
                            connection.sendall(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                    except OSError:
                        observed.append(False)

                peer = threading.Thread(target=serve)
                peer.start()
                try:
                    uri = f"ipp://{quote(path, safe='')}/printers/{readback.QUEUE}"
                    with self.assertRaises(readback.Rejected):
                        readback.bounded_command(["/usr/bin/ipptool", "-T", "1", "-q", uri, str(request)],
                                                 time.monotonic() + 4)
                finally:
                    peer.join(timeout=3)
                self.assertFalse(peer.is_alive())
                self.assertEqual(observed, [True])
