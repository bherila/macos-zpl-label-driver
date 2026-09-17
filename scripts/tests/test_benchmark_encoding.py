from __future__ import annotations
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from benchmark_encoding import validate_report


class EncodingBenchmarkTests(unittest.TestCase):
    def report(self):
        return {"schemaVersion": 1, "scope": "offline-encoding-no-transport", "encoding": "ascii",
            "pattern": "white", "iterations": 1, "widthDots": 813, "heightDots": 1219,
            "packedBytes": 124338, "outputBytes": 1000, "encodingNanoseconds": [1000]}

    def test_exact_bounded_report_is_accepted(self):
        report = self.report()
        self.assertEqual(validate_report(report, "ascii", "white", 1), report)

    def test_identity_unknown_fields_and_boolean_numbers_are_rejected(self):
        for field, value in [("schemaVersion", True), ("iterations", True), ("widthDots", 812),
                             ("scope", "physical"), ("encoding", "plain"), ("extra", 1)]:
            report = self.report()
            report[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_report(report, "ascii", "white", 1)

    def test_invalid_output_and_timing_samples_are_rejected(self):
        for field, value in [("outputBytes", True), ("outputBytes", 0), ("outputBytes", 64*1024*1024+1),
                             ("encodingNanoseconds", []), ("encodingNanoseconds", [True]),
                             ("encodingNanoseconds", [0]), ("encodingNanoseconds", [float("nan")]),
                             ("encodingNanoseconds", [120_000_000_001])]:
            report = self.report()
            report[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate_report(report, "ascii", "white", 1)
