"""Temporary M0-AC06 negative probe; remove after observing required-check failure."""
import unittest


class IntentionalCIProbe(unittest.TestCase):
    def test_required_check_must_not_accept_a_failed_test(self):
        self.fail("INTENTIONAL_M0_AC06_NEGATIVE_PROBE: never merge this failing head")
