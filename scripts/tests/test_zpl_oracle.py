import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from zpl_oracle import decode, read_pbm, analytic_bitmap

class OracleTests(unittest.TestCase):
    golden = b"^XA\n^FO0,0^GFA,2,2,2,A580^FS\n^XZ\n"
    def test_fixed_vector(self):
        self.assertEqual(decode(self.golden, 9, 1), (b"\xa5\x80", [1]))
    def test_wrong_counts(self):
        for bad in [self.golden.replace(b"2,2,2", b"4,2,2"), self.golden.replace(b"2,2,2", b"2,2,1")]:
            with self.assertRaises(ValueError): decode(bad, 9, 1)
    def test_nonzero_padding(self):
        with self.assertRaises(ValueError): decode(self.golden.replace(b"A580", b"A581"), 9, 1)
    def test_wrong_origin(self):
        with self.assertRaises(ValueError): decode(self.golden.replace(b"^FO0,0", b"^FO0,1"), 9, 1)
    def test_unknown_command_rejected(self):
        with self.assertRaises(ValueError): decode(self.golden.replace(b"^XZ", b"^PQ9^XZ"), 9, 1)
    def test_missing_rows(self):
        with self.assertRaises(ValueError): decode(self.golden, 9, 2)
    def test_bad_hex(self):
        with self.assertRaises(ValueError): decode(self.golden.replace(b"A580", b"GGGG"), 9, 1)
    def test_trailing_content(self):
        with self.assertRaises(ValueError): decode(self.golden + b"\n", 9, 1)
    def test_no_second_envelope(self):
        with self.assertRaises(ValueError): decode(self.golden + self.golden, 9, 1)
    def test_band_cap(self):
        with self.assertRaises(ValueError): decode(self.golden, 9, 1, 1)
    def test_dimensions(self):
        for w,h in [(0,1),(-1,1),(32001,1),(True,1),(32000,32000)]:
            with self.assertRaises(ValueError): decode(self.golden,w,h)
    def test_pbm(self):
        self.assertEqual(read_pbm(b"P4\n9 1\n\xa5\x80"),(9,1,b"\xa5\x80"))
        with self.assertRaises(ValueError): read_pbm(b"P4\n9 1\n\xa5\x81")
    def test_analytic_border(self):
        self.assertEqual(analytic_bitmap(9,1), b"\xff\x80")
