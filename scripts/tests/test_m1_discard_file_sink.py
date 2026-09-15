from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "m1-discard-file-sink.sh"
PPD = ROOT / "experiments" / "cups-probe" / "labelprobe-native.ppd"
FILTER = "/Library/Printers/LabelPrinterDriver/M1/labelcapture-filter"


class M1DiscardFileSinkTests(unittest.TestCase):
    def test_plan_is_non_mutating_and_names_only_the_inert_sink(self) -> None:
        result = subprocess.run(["bash", str(SCRIPT), "--plan"], capture_output=True, text=True, check=True)
        self.assertIn("LabelProbe_DISCARDS_JOBS", result.stdout)
        self.assertIn("file:///dev/null", result.stdout)
        self.assertNotIn("sudo", result.stdout)

    def test_candidate_filter_declarations_materialize_to_the_fixed_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "capture.ppd"
            command = [
                "/usr/bin/awk", "-v", f"installed_filter={FILTER}",
                '/^\\*cupsFilter2: / { sub(/ -"$/, " " installed_filter "\\\"") } { print }',
                str(PPD),
            ]
            with output.open("w", encoding="utf-8") as handle:
                subprocess.run(command, stdout=handle, check=True)
            cupstestppd = shutil.which("cupstestppd")
            if cupstestppd:
                subprocess.run([cupstestppd, "-q", "-W", "filters", str(output)], check=True)
            text = output.read_text(encoding="latin-1")
            self.assertIn(f'*cupsFilter2: "application/pdf application/vnd.labelprobe 0 {FILTER}"', text)
            self.assertIn(f'*cupsFilter2: "application/vnd.cups-pdf application/vnd.labelprobe 0 {FILTER}"', text)
            self.assertNotIn('application/pdf application/vnd.labelprobe 0 -"', text)

    def test_transaction_has_no_server_configuration_or_default_printer_mutation(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("file:///dev/null", text)
        self.assertIn("lpadmin -p \"$queue\" -v \"$uri\"", text)
        self.assertIn("lpadmin -x \"$queue\"", text)
        self.assertIn("cleanup_owned_artifacts", text)
        self.assertIn("|| fail_after_apply 'generated experiment PPD failed strict validation after staging'", text)
        self.assertIn("|| fail_after_apply 'queue URI readback failed'", text)
        self.assertNotIn("ServerBin", text)
        self.assertNotIn("cupsd", text)
        self.assertNotIn("launchctl", text)
        self.assertNotIn("lpadmin -d", text)


if __name__ == "__main__":
    unittest.main()
