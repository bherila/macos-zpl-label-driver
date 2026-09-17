from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
import sys
import tempfile
import time


MODULE_PATH = Path(__file__).resolve().parents[1] / "benchmark_offline.py"
SPEC = importlib.util.spec_from_file_location("benchmark_offline", MODULE_PATH)
assert SPEC and SPEC.loader
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class BenchmarkOfflineTests(unittest.TestCase):
    def test_timeout_stops_child_holding_pipes_after_parent_exit(self) -> None:
        # Killing only the parent is insufficient: it has already exited while
        # its child retains stdout and would otherwise publish a delayed marker.
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "child-survived"
            child = "import time; from pathlib import Path; time.sleep(1); Path(" + repr(str(marker)) + ").write_text('unexpected')"
            parent = "import subprocess,sys; subprocess.Popen([sys.executable,'-c'," + repr(child) + "])"
            started = time.monotonic()
            with self.assertRaisesRegex(RuntimeError, "finite timeout"):
                benchmark.bounded_run([sys.executable, "-c", parent], timeout=0.2)
            self.assertLess(time.monotonic() - started, 2)
            time.sleep(1.1)
            self.assertFalse(marker.exists())
        result = benchmark.bounded_run([sys.executable, "-c", "print('ok')"], timeout=5)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "ok"))
        for timeout in [0, -1, float("inf"), float("nan")]:
            with self.assertRaises(ValueError):
                benchmark.bounded_run([sys.executable, "-c", "pass"], timeout=timeout)

    def test_worker_memory_is_bounded_optional_and_never_manufactured_zero(self) -> None:
        self.assertIsNone(benchmark.worker_resident_bytes({}))
        self.assertIsNone(benchmark.worker_resident_bytes({"workerMaximumResidentBytes": None}))
        for value in [1, 12345678, 1 << 40]:
            self.assertEqual(benchmark.worker_resident_bytes({"workerMaximumResidentBytes": value}), value)
        for value in [0, -1, (1 << 40) + 1, True, "123", 1.5]:
            with self.assertRaises(ValueError):
                benchmark.worker_resident_bytes({"workerMaximumResidentBytes": value})

    def test_parses_macos_time_output(self) -> None:
        stderr = """
                0.12 real         0.02 user         0.01 sys
            14073856  maximum resident set size
        """
        self.assertEqual(benchmark.parse_time_output(stderr), (0.12, 14_073_856))
        with self.assertRaises(ValueError):
            benchmark.parse_time_output("0.12 elapsed")

    def test_nearest_rank_and_summary_are_explicit(self) -> None:
        values = [value / 100 for value in range(1, 21)]
        self.assertEqual(benchmark.nearest_rank(values, 0.95), 0.19)
        summary = benchmark.summarize(values, list(range(100, 120)), 1_000, 2_000)
        self.assertEqual(summary["runs"], 20)
        self.assertAlmostEqual(summary["medianMilliseconds"], 105)
        self.assertAlmostEqual(summary["p95Milliseconds"], 190)
        self.assertEqual(summary["maximumResidentBytes"], 119)
        self.assertAlmostEqual(summary["preparedBytesPerSecondAtP95"], 1_000 / 0.19)

    def test_invalid_percentile_inputs_fail(self) -> None:
        for values, percentile in [([], 0.95), ([1], 0), ([1], 1.1)]:
            with self.subTest(values=values, percentile=percentile):
                with self.assertRaises(ValueError):
                    benchmark.nearest_rank(values, percentile)


if __name__ == "__main__":
    unittest.main()
