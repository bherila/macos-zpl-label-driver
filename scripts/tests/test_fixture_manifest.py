import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from check_fixture_manifest import validate

class FixtureManifestTests(unittest.TestCase):
    def test_committed_fixture_integrity(self):
        self.assertEqual(validate(),(19,29,3))
