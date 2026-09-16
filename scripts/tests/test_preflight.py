from __future__ import annotations

import sys
import re
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_repo import markdown_links
from ci_scope import classify, needs_swift


class PreflightTests(unittest.TestCase):
    def test_documentation_only(self):
        self.assertFalse(needs_swift(["README.md", "docs/ARCHITECTURE.md"]))

    def test_code_change(self):
        self.assertTrue(needs_swift(["README.md", "Packages/LabelCore/Package.swift"]))

    def test_workflow_change(self):
        self.assertTrue(needs_swift([".github/workflows/ci.yml"]))

    def test_ci_covers_stacked_pull_request_targets(self):
        workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text()
        trigger = workflow.split("  pull_request:", 1)[1].split("  push:", 1)[0]
        self.assertIsNone(re.search(r"branches(?:-ignore)?:", trigger))
        self.assertIn("branches: [main]", workflow.split("  push:", 1)[1])

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
