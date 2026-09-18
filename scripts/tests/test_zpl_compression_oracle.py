import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from zpl_compression_oracle import payload, decode


class CompressionOracleTests(unittest.TestCase):
    def test_documented_counts_compose_in_either_order(self):
        self.assertEqual(payload(b"M60", 4, 4), bytes.fromhex("66666660"))
        self.assertEqual(payload(b"hB", 20, 20), bytes([0xBB]) * 20)
        for encoded in [b"MvB0", b"vMB0"]:
            self.assertEqual(payload(encoded, 164, 164), bytes([0xBB]) * 163 + b"\xB0")
        self.assertEqual(payload(b"zg0", 210, 210), bytes(210))

    def test_repeated_row_and_literal_fallback(self):
        self.assertEqual(payload(b"FF80:J0", 2, 6), b"\xFF\x80\xFF\x80\0\0")

    def test_malformed_and_expansion_limits(self):
        for encoded in [b":", b"G:", b"0:", b"z0", b"G", b"00:", b"000", b"!", b",", b"gg0", b"a0", b"^XZ", b"00 "]:
            with self.subTest(encoded=encoded), self.assertRaises(ValueError):
                payload(encoded, 1, 1)

    def test_band_history_and_padding_cannot_escape(self):
        good = b"^XA\n^FO0,0^GFA,2,2,2,FF80^FS\n^FO0,1^GFA,2,2,2,FF80^FS\n^XZ\n"
        self.assertEqual(decode(good, 9, 2)[0], b"\xFF\x80" * 2)
        for bad in [good.replace(b",FF80^FS\n^XZ", b",:^FS\n^XZ"), good.replace(b"FF80", b"FF81"), good.replace(b"^FO0,1", b"^FO0,0"), good + b"0"]:
            with self.assertRaises(ValueError):
                decode(bad, 9, 2)
