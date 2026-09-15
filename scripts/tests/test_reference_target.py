from __future__ import annotations

import copy
import json
import sys
import unittest
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_reference_target import ROOT, nearest_positive, validate_target


class ReferenceTargetTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT / "docs/reference-target.json").read_text())

    def test_reference_is_consistent(self):
        self.assertEqual(validate_target(self.data), [])

    def test_exact_dot_rounding(self):
        self.assertEqual(nearest_positive(Fraction(8128, 10)), 813)
        self.assertEqual(nearest_positive(Fraction(12192, 10)), 1219)
        self.assertEqual(nearest_positive(Fraction(5, 2)), 3)
        with self.assertRaises(ValueError):
            nearest_positive(Fraction(0))

    def test_nominal_integer_dpi_is_not_gc420d_geometry(self):
        self.data["geometryOracle"]["widthDots"] = 812
        self.data["geometryOracle"]["heightDots"] = 1218
        self.assertTrue(validate_target(self.data))

    def test_band_seam_mismatch_rejected(self):
        self.data["geometryOracle"]["bandRows"] = [321, 321, 321, 255]
        self.assertTrue(validate_target(self.data))

    def test_padding_mismatch_rejected(self):
        self.data["geometryOracle"]["lastByteWhitePaddingBits"] = 0
        self.assertTrue(validate_target(self.data))

    def test_older_os_or_account_requirement_rejected(self):
        for key, value in [("minimumMacOS", "13.0"), ("signingMode", "developer-id"), ("appleDeveloperAccountAvailable", True)]:
            with self.subTest(key=key):
                changed = copy.deepcopy(self.data)
                changed["project"][key] = value
                self.assertTrue(validate_target(changed))

    def test_wrong_model_transport_or_transfer_rejected(self):
        for key, value in [("model", "GC420t"), ("transport", "tcp"), ("thermalMethod", "thermal-transfer")]:
            with self.subTest(key=key):
                changed = copy.deepcopy(self.data)
                changed["hardware"][key] = value
                self.assertTrue(validate_target(changed))

    def test_accessories_cannot_be_enabled(self):
        for key in ("cutterInstalled", "peelerEnabled"):
            with self.subTest(key=key):
                changed = copy.deepcopy(self.data)
                changed["hardware"][key] = True
                self.assertTrue(validate_target(changed))

    def test_missing_gap_is_not_zero(self):
        self.data["media"]["gapMm"] = 0
        self.assertTrue(validate_target(self.data))

    def test_unknown_speed_is_not_zero(self):
        self.data["modelReference"]["currentSpeedIps"] = 0
        self.assertTrue(validate_target(self.data))

    def test_handoff_grants_no_physical_budget(self):
        self.data["permissions"]["physicalLabelBudget"] = 3
        self.assertTrue(validate_target(self.data))

    def test_claimed_qualification_rejected(self):
        self.data["qualification"] = "qualified"
        self.assertTrue(validate_target(self.data))

    def test_malformed_reference_data_fails_cleanly(self):
        for data in [None, [], {}, {"schemaVersion": 1}, {"schemaVersion": 1, "purpose": "planning-reference-not-runtime-profile", "project": None}]:
            with self.subTest(data=data):
                self.assertTrue(validate_target(data))

    def test_invalid_pitch_fails_cleanly(self):
        self.data["modelReference"]["dotsPerMillimeter"]["denominator"] = 0
        self.assertTrue(validate_target(self.data))


if __name__ == "__main__":
    unittest.main()
