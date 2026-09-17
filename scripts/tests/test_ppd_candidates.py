from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PPDS = sorted((ROOT / "experiments" / "cups-probe").glob("*.ppd"))
SIZES = ("4x6.Fullbleed", "Letter.Fullbleed", "A4.Fullbleed")


class CandidatePPDTests(unittest.TestCase):
    def test_full_bleed_size_names_are_used_consistently(self):
        self.assertEqual(len(PPDS), 3)
        for path in PPDS:
            text = path.read_text(encoding="ascii")
            for size in SIZES:
                self.assertIn(f"*PageSize {size}/", text, path)
                self.assertIn(f"*PageRegion {size}/", text, path)
                self.assertIn(f"*ImageableArea {size}:", text, path)
                self.assertIn(f"*PaperDimension {size}:", text, path)
            self.assertNotIn("Label4x6", text, path)

    def test_default_page_names_exist_in_each_candidate(self):
        for path in PPDS:
            text = path.read_text(encoding="ascii")
            page_size = next(line.split(": ", 1)[1] for line in text.splitlines() if line.startswith("*DefaultPageSize:"))
            page_region = next(line.split(": ", 1)[1] for line in text.splitlines() if line.startswith("*DefaultPageRegion:"))
            self.assertIn(f"*PageSize {page_size}/", text, path)
            self.assertIn(f"*PageRegion {page_region}/", text, path)


if __name__ == "__main__":
    unittest.main()
