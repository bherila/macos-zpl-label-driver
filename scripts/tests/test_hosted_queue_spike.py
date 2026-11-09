"""The hosted queue spike refuses to run anywhere but a GitHub-hosted macOS runner.

The spike installs a filter under /Library/Printers and creates a CUPS queue, so the
guard is its only safety property. Each case isolates one condition: a PATH shim makes
`uname -s` report Darwin, so a refusal cannot come from the Linux host instead of the
condition under test. Nothing here changes system state.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "hosted_queue_spike.sh"
REFUSAL = "refusing to run outside a GitHub-hosted macOS runner"


class HostedQueueSpikeGuardTests(unittest.TestCase):
    def run_spike(self, *, kernel: str, github_actions: str | None, runner_environment: str | None):
        with tempfile.TemporaryDirectory() as temporary:
            shim = Path(temporary) / "bin"
            shim.mkdir()
            uname = shim / "uname"
            uname.write_text(f"#!/bin/sh\necho {kernel}\n")
            uname.chmod(0o755)
            env = {"PATH": f"{shim}:/usr/bin:/bin", "LC_ALL": "C"}
            if github_actions is not None:
                env["GITHUB_ACTIONS"] = github_actions
            if runner_environment is not None:
                env["RUNNER_ENVIRONMENT"] = runner_environment
            output = Path(temporary) / "out"
            result = subprocess.run(
                ["bash", str(SCRIPT), str(output)],
                env=env, capture_output=True, text=True, timeout=30,
            )
            return result, output.exists()

    def assert_refused(self, result, created_output):
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(REFUSAL, result.stderr)
        self.assertFalse(created_output, "the guard must refuse before writing anything")

    def test_refuses_a_self_hosted_runner(self):
        self.assert_refused(*self.run_spike(kernel="Darwin", github_actions="true", runner_environment="self-hosted"))

    def test_refuses_outside_github_actions(self):
        self.assert_refused(*self.run_spike(kernel="Darwin", github_actions=None, runner_environment="github-hosted"))

    def test_refuses_a_hosted_runner_that_is_not_macos(self):
        self.assert_refused(*self.run_spike(kernel="Linux", github_actions="true", runner_environment="github-hosted"))


if __name__ == "__main__":
    unittest.main()
