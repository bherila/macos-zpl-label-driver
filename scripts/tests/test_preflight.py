from __future__ import annotations

import sys
import re
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_repo import markdown_links, push_cancellation_errors
from ci_scope import classify, needs_swift


class PreflightTests(unittest.TestCase):
    def test_documentation_only(self):
        self.assertFalse(needs_swift(["README.md", "docs/ARCHITECTURE.md"]))

    def test_documentation_with_manifest(self):
        self.assertFalse(needs_swift(["MANIFEST.sha256", "README.md", "docs/PROGRESS.json"]))

    def test_manifest_never_hides_substantive_or_unknown_changes(self):
        self.assertTrue(needs_swift(["MANIFEST.sha256"]))
        for name in ["Packages/LabelCore/Package.swift", ".github/workflows/ci.yml", "Profiles/new.json"]:
            with self.subTest(name=name):
                self.assertTrue(needs_swift(["MANIFEST.sha256", "README.md", name]))

    def test_code_change(self):
        self.assertTrue(needs_swift(["README.md", "Packages/LabelCore/Package.swift"]))

    def test_workflow_change(self):
        self.assertTrue(needs_swift([".github/workflows/ci.yml"]))

    def test_ci_covers_stacked_pull_request_targets(self):
        workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text()
        trigger = workflow.split("  pull_request:", 1)[1].split("  push:", 1)[0]
        self.assertIsNone(re.search(r"branches(?:-ignore)?:", trigger))
        self.assertIn("branches: [main]", workflow.split("  push:", 1)[1])

    def test_a_workflow_may_not_cancel_superseded_pushes(self):
        # A push carries the merged tree, so cancelling it can leave that tree
        # never compiled while the required check still reports success.
        cancelling = "on:\n  push:\n    branches: [main]\nconcurrency:\n  cancel-in-progress: true\n"
        self.assertEqual(len(push_cancellation_errors("ci.yml", cancelling)), 1)
        self.assertIn("cancel-in-progress", push_cancellation_errors("ci.yml", cancelling)[0])

    def test_cancellation_scoped_to_pull_requests_is_accepted(self):
        scoped = ("on:\n  pull_request:\n  push:\n    branches: [main]\nconcurrency:\n"
                  "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}\n")
        self.assertEqual(push_cancellation_errors("ci.yml", scoped), [])

    def test_a_workflow_without_a_push_trigger_may_still_cancel(self):
        # compatibility.yml is workflow_dispatch only; superseding a manual run
        # there discards nothing a merge depended on.
        dispatch_only = "on:\n  workflow_dispatch:\nconcurrency:\n  cancel-in-progress: true\n"
        self.assertEqual(push_cancellation_errors("compatibility.yml", dispatch_only), [])

    def test_ci_does_not_cancel_its_own_main_pushes(self):
        workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text()
        # Assert the trigger too, so removing `push:` cannot make this pass vacuously.
        self.assertIsNotNone(re.search(r"(?m)^\s{2}push:\s*$", workflow))
        self.assertEqual(push_cancellation_errors("ci.yml", workflow), [])

    def test_unknown_and_empty_run_compilation(self):
        self.assertTrue(needs_swift([]))
        self.assertTrue(needs_swift(["Profiles/new.json"]))
        self.assertTrue(classify("", ""))
        self.assertTrue(classify("; echo unsafe", "a" * 40))

    def test_links_ignore_fenced_examples(self):
        sample = "[real](docs/test.md)\n```text\n[fake](missing.md)\n```\n"
        self.assertEqual(list(markdown_links(sample)), ["docs/test.md"])

    def test_image_link_is_checked(self):
        self.assertEqual(list(markdown_links("![a](image.png)")), ["image.png"])


if __name__ == "__main__":
    unittest.main()
