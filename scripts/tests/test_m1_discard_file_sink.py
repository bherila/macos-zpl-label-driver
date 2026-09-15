from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "m1-discard-file-sink.sh"
PPD = ROOT / "experiments" / "cups-probe" / "labelprobe-native.ppd"
FILTER = "/Library/Printers/LabelPrinterDriver-M1/labelcapture-filter"
PPD_HASHES = {
    "labelprobe-native.ppd": "1ef382b536c71d38a8b6d02efbab8944959c538d107c084ede6519da1e8bffdb",
    "labelprobe-letter.ppd": "e58416fb84554546cf8f86c3f446be9e06f8c3d3f1f46f64cc40c9cd31e00d8a",
    "labelprobe-a4.ppd": "13ce96f08150b7a932ba3527296275aca0e1bb6092aaa6bf54a212bfd265df63",
}


class M1DiscardFileSinkTests(unittest.TestCase):
    def run_recovery_harness(self, body: str) -> subprocess.CompletedProcess[str]:
        harness = f"""
set -euo pipefail
export M1_TRANSACTION_SOURCE_ONLY=1
source {str(SCRIPT)!r}
scheduler=/private/var/run/cupsd
events=''
record() {{ events="${{events}}$1"; }}
protected_root_state() {{ return 0; }}
ownership_record_matches() {{ return 0; }}
queue_state() {{ return 1; }}
queue_uri_matches() {{ return 0; }}
remove_queue() {{ record Q; return 0; }}
filter_state() {{ return 0; }}
remove_filter() {{ record F; return 0; }}
filter_is_absent() {{ return 0; }}
remove_ownership() {{ record O; return 0; }}
remove_root() {{ record R; return 0; }}
report_residual_state() {{ record X; }}
{body}
"""
        return subprocess.run(["bash", "-c", harness], capture_output=True, text=True)

    def run_install_fault_harness(self, fault: str) -> subprocess.CompletedProcess[str]:
        harness = f"""
set -euo pipefail
export M1_TRANSACTION_SOURCE_ONLY=1
source {str(SCRIPT)!r}
scheduler=/private/var/run/cupsd
approved_sha={'a' * 64!r}
root_present=0
intent_present=0
filter_present=0
queue_present=0
events=''
record() {{ events="${{events}}$1"; }}
create_root() {{ root_present=1; record A; }}
install_intent() {{ intent_present=1; record I; }}
ownership_record_matches() {{ [[ $root_present == 1 && $intent_present == 1 ]]; }}
empty_reserved_root_matches() {{ [[ $root_present == 1 && $intent_present == 0 && $filter_present == 0 ]]; }}
install_filter() {{ filter_present=1; record F; }}
validate_installed_filter() {{ [[ $filter_present == 1 ]]; }}
validate_installed_ppd() {{ return 0; }}
ensure_queue_absent() {{ [[ $queue_present == 0 ]]; }}
create_queue() {{ queue_present=1; record Q; }}
disable_queue() {{ record D; }}
reject_queue() {{ record J; }}
queue_uri_matches() {{ [[ $queue_present == 1 ]]; }}
queue_is_default() {{ return 1; }}
queue_is_disabled() {{ [[ $queue_present == 1 ]]; }}
queue_is_rejecting() {{ [[ $queue_present == 1 ]]; }}
transaction_checkpoint() {{ [[ $1 != {fault!r} ]]; }}
protected_root_state() {{ [[ $root_present == 1 ]] && return 0; return 1; }}
queue_state() {{ [[ $queue_present == 1 ]] && return 0; return 1; }}
remove_queue() {{ queue_present=0; record q; }}
filter_state() {{ [[ $filter_present == 1 ]] && return 0; return 1; }}
remove_filter() {{ filter_present=0; record f; }}
filter_is_absent() {{ [[ $filter_present == 0 ]]; }}
remove_ownership() {{ intent_present=0; record o; }}
remove_root() {{ root_present=0; record r; }}
report_residual_state() {{ record X; }}
if install_transaction snapshot generated intent; then
  exit 90
fi
cleanup_owned_artifacts || true
printf '%s|%s%s%s%s\n' "$events" "$root_present" "$intent_present" "$filter_present" "$queue_present"
"""
        return subprocess.run(["bash", "-c", harness], capture_output=True, text=True)

    def test_plan_is_non_mutating_and_names_only_the_inert_sink(self) -> None:
        result = subprocess.run(["bash", str(SCRIPT), "--plan"], capture_output=True, text=True, check=True)
        self.assertIn("LabelProbe_DISCARDS_JOBS", result.stdout)
        self.assertIn("file:///dev/null", result.stdout)
        self.assertNotIn("sudo", result.stdout)
        self.assertIn("--validate-filter FILTER_BINARY", SCRIPT.read_text(encoding="utf-8"))

    def test_scheduler_preflight_rejects_client_endpoint_overrides(self) -> None:
        env = dict(os.environ, CUPS_SERVER="remote.example")
        result = subprocess.run(
            ["bash", str(SCRIPT), "--scheduler-preflight"], capture_output=True, text=True, env=env
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing CUPS_SERVER or IPP_PORT overrides", result.stderr)

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

    def test_privileged_experiment_pins_supplied_candidate_bytes(self) -> None:
        script_text = SCRIPT.read_text(encoding="utf-8")
        for name, expected_hash in PPD_HASHES.items():
            candidate = ROOT / "experiments" / "cups-probe" / name
            actual_hash = hashlib.sha256(candidate.read_bytes()).hexdigest()
            self.assertEqual(expected_hash, actual_hash)
            self.assertIn(expected_hash, script_text)
        self.assertIn("exactly two cupsFilter2 declarations", script_text)
        self.assertIn("must not contain a legacy cupsFilter declaration", script_text)

    def test_read_only_validation_accepts_each_exact_candidate_and_rejects_mutation(self) -> None:
        for name in PPD_HASHES:
            candidate = ROOT / "experiments" / "cups-probe" / name
            subprocess.run(["bash", str(SCRIPT), "--validate-ppd", str(candidate)], check=True, capture_output=True)
        with tempfile.TemporaryDirectory() as directory:
            modified = Path(directory) / "modified.ppd"
            modified.write_bytes(PPD.read_bytes() + b"\n*% unexpected mutation\n")
            result = subprocess.run(
                ["bash", str(SCRIPT), "--validate-ppd", str(modified)], capture_output=True, text=True
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("do not match a supplied experiment candidate", result.stderr)

    def test_invalid_filter_cleans_private_snapshot_before_sudo(self) -> None:
        if sys.platform != "darwin":
            self.skipTest("the M1 transaction is intentionally Tahoe-only")
        temporary_root = Path("/private/tmp")
        before = set(temporary_root.glob("label-driver-m1.*"))
        with tempfile.TemporaryDirectory() as directory:
            invalid_filter = Path(directory) / "not-mach-o"
            invalid_filter.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            invalid_filter.chmod(0o755)
            result = subprocess.run(
                ["bash", str(SCRIPT), "--apply", str(invalid_filter), str(PPD)],
                capture_output=True,
                text=True,
            )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("filter snapshot is not local-ad-hoc ARM", result.stderr)
        self.assertEqual(before, set(temporary_root.glob("label-driver-m1.*")))

    def test_transaction_has_no_server_configuration_or_default_printer_mutation(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("file:///dev/null", text)
        self.assertIn('controlled_lpadmin -p "$queue" -v "$uri"', text)
        self.assertIn('controlled_lpadmin -x "$queue"', text)
        self.assertIn("cleanup_owned_artifacts", text)
        self.assertIn("retained altered queue and all recovery artifacts", text)
        self.assertIn("retained unexpected protected ownership state during recovery", text)
        self.assertIn("ownership_record_matches", text)
        self.assertIn("is_supplied_ppd_sha", text)
        self.assertIn("verify_local_adhoc_arm64", text)
        self.assertIn("Signature=adhoc", text)
        self.assertIn("minos 26\\.0", text)
        self.assertIn("filterSHA256", text)
        self.assertIn("sourcePPDSHA256", text)
        self.assertIn('test -L "$filter"', text)
        self.assertIn("END { print NR }", text)
        self.assertIn('local snapshot="$temporary/labelcapture-filter"', text)
        self.assertIn('local ppd_snapshot="$temporary/candidate.ppd"', text)
        self.assertIn("temporary=''", text)
        self.assertIn("trap finish_process EXIT", text)
        self.assertIn("/private/tmp/label-driver-m1.??????", text)
        self.assertNotIn("local temporary", text)
        self.assertNotIn("LabelPrinterDriver/M1", text)
        self.assertIn('install_filter "$snapshot"', text)
        self.assertIn('/bin/mkdir -m 0755 "$root"', text)
        self.assertNotIn('/bin/mkdir -p "$root"', text)
        self.assertIn('validate_ppd "$ppd_snapshot"', text)
        self.assertIn('render_ppd "$ppd_snapshot" "$generated"', text)
        self.assertIn('validate_installed_filter || return 1', text)
        self.assertIn('validate_installed_ppd "$generated" || return 1', text)
        self.assertIn('queue_uri_matches || return 1', text)
        self.assertIn('! queue_is_default || return 1', text)
        self.assertIn("die 'protected transaction failed; recovery was attempted'", text)
        self.assertIn('/usr/bin/lpstat -h "$scheduler"', text)
        self.assertIn('/usr/sbin/lpadmin -h "$scheduler"', text)
        self.assertIn("CUPS_SERVER", text)
        self.assertIn("IPP_PORT", text)
        self.assertIn("schemaVersion=2", text)
        self.assertIn("state=apply-intent", text)
        self.assertIn("scheduler=$scheduler", text)
        self.assertIn("sudo -n", text)
        self.assertNotIn("ServerBin", text)
        self.assertNotRegex(text, r"/usr/sbin/cupsd(?:\s|$)")
        self.assertNotIn("launchctl", text)
        self.assertNotIn("lpadmin -d", text)

    def test_recovery_removes_queue_before_filter_and_record(self) -> None:
        result = self.run_recovery_harness("""
calls=0
queue_state() { calls=$((calls + 1)); if [[ $calls == 1 ]]; then return 0; fi; return 1; }
cleanup_owned_artifacts
printf '%s\n' "$events"
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "QFOR")

    def test_recovery_retains_everything_on_changed_uri(self) -> None:
        result = self.run_recovery_harness("""
queue_state() { return 0; }
queue_uri_matches() { return 1; }
cleanup_owned_artifacts || true
printf '%s\n' "$events"
""")
        self.assertEqual(result.stdout.strip(), "X")

    def test_recovery_retains_filter_and_record_when_queue_delete_fails(self) -> None:
        result = self.run_recovery_harness("""
queue_state() { return 0; }
remove_queue() { record Q; return 1; }
cleanup_owned_artifacts || true
printf '%s\n' "$events"
""")
        self.assertEqual(result.stdout.strip(), "QX")

    def test_recovery_retains_everything_when_scheduler_or_auth_is_unavailable(self) -> None:
        scheduler_failure = self.run_recovery_harness("""
queue_state() { return 2; }
cleanup_owned_artifacts || true
printf '%s\n' "$events"
""")
        self.assertEqual(scheduler_failure.stdout.strip(), "X")
        expired_auth = self.run_recovery_harness("""
protected_root_state() { return 2; }
cleanup_owned_artifacts || true
printf '%s\n' "$events"
""")
        self.assertEqual(expired_auth.stdout.strip(), "X")

    def test_recovery_retains_record_for_altered_filter_or_uncertain_post_delete_query(self) -> None:
        altered = self.run_recovery_harness("""
filter_state() { return 2; }
cleanup_owned_artifacts || true
printf '%s\n' "$events"
""")
        self.assertEqual(altered.stdout.strip(), "X")
        uncertain = self.run_recovery_harness("""
calls=0
queue_state() { calls=$((calls + 1)); if [[ $calls == 1 ]]; then return 0; fi; return 2; }
cleanup_owned_artifacts || true
printf '%s\n' "$events"
""")
        self.assertEqual(uncertain.stdout.strip(), "QX")

    def test_recovery_handles_partial_state_with_no_filter(self) -> None:
        result = self.run_recovery_harness("""
filter_state() { return 1; }
cleanup_owned_artifacts
printf '%s\n' "$events"
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "OR")

    def test_faults_after_journaled_mutations_recover_in_queue_first_order(self) -> None:
        expected = {
            "intent-installed": "AIor|0000",
            "filter-installed": "AIFfor|0000",
            "queue-created": "AIFQqfor|0000",
            "queue-disabled": "AIFQDqfor|0000",
            "queue-rejected": "AIFQDJqfor|0000",
        }
        for fault, state in expected.items():
            with self.subTest(fault=fault):
                result = self.run_install_fault_harness(fault)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), state)

    def test_fault_before_intent_removes_only_the_known_empty_reserved_root(self) -> None:
        result = self.run_install_fault_harness("root-created")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Ar|0000")

    def test_preflight_distinguishes_existing_queue_query_failure_and_existing_root(self) -> None:
        for state, expected in [(0, "refusing to replace an existing"), (2, "could not prove")]:
            with self.subTest(queue_state=state):
                result = self.run_recovery_harness(f"""
queue_state() {{ return {state}; }}
ensure_not_existing
""")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)
        result = self.run_recovery_harness("""
queue_state() { return 1; }
unprivileged_root_absent() { return 1; }
ensure_not_existing
""")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to replace an existing experiment root", result.stderr)

    def test_term_enters_the_same_queue_first_recovery_path(self) -> None:
        harness = f"""
set -euo pipefail
export M1_TRANSACTION_SOURCE_ONLY=1
source {str(SCRIPT)!r}
scheduler=/private/var/run/cupsd
temporary=''
transaction_active=1
calls=0
protected_root_state() {{ return 0; }}
ownership_record_matches() {{ return 0; }}
queue_state() {{ calls=$((calls + 1)); [[ $calls == 1 ]] && return 0; return 1; }}
queue_uri_matches() {{ return 0; }}
remove_queue() {{ printf 'Q'; }}
filter_state() {{ return 0; }}
remove_filter() {{ printf 'F'; }}
filter_is_absent() {{ return 0; }}
remove_ownership() {{ printf 'O'; }}
remove_root() {{ printf 'R'; }}
trap finish_process EXIT
trap 'interrupt_process TERM' TERM
kill -TERM $$
"""
        result = subprocess.run(["bash", "-c", harness], capture_output=True, text=True)
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertEqual(result.stdout, "QFOR")


if __name__ == "__main__":
    unittest.main()
