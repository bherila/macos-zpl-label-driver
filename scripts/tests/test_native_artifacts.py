"""Rules for judging captured macOS tool output, proved on a host without them.

`lipo`, `vtool`, `codesign` and `plutil` do not exist on the Linux host where
these rules are written, so every case below drives the checker against a
realistic captured *string* rather than a live tool. The rejecting cases carry
the weight: a checker that only recognises the good capture is the same defect
as a CI step that prints `lipo -archs` and asserts nothing.

Nothing here builds, signs, installs or contacts a device.
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
SCRIPT = SCRIPTS / "check_native_artifacts.py"
_spec = importlib.util.spec_from_file_location("check_native_artifacts", SCRIPT)
checker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(checker)


# --- Captured tool output -------------------------------------------------
#
# Shapes taken from the tools' documented output and from the hosted `macos-26`
# anchor run recorded in docs/validation/M0-ACCEPTANCE-LEDGER-2026-09-18.md
# (`minos 26.0`, `Signature=adhoc`, `TeamIdentifier=not set`).

ARM64_ONLY = "arm64\n"
UNIVERSAL = "arm64 x86_64\n"
INTEL_ONLY = "x86_64\n"
LIPO_FAILED = (
    "fatal error: /usr/bin/lipo: can't figure out the architecture type of: "
    "/Users/runner/work/driver/driver/.build/release/label-driver\n"
    "CAPTURE-TOOL-FAILED status=1\n"
)


def vtool_capture(minos: str, platform: str = "MACOS") -> str:
    return (
        "/Users/runner/work/driver/driver/Packages/LabelMac/.build/"
        "arm64-apple-macosx/release/label-driver:\n"
        "Load command 9\n"
        "      cmd LC_BUILD_VERSION\n"
        "  cmdsize 32\n"
        f" platform {platform}\n"
        f"    minos {minos}\n"
        "      sdk 26.0\n"
        "   ntools 1\n"
        "     tool LD\n"
        "  version 1234.5\n"
    )


VTOOL_LEGACY = (
    "/Users/runner/work/driver/driver/.build/release/label-driver:\n"
    "Load command 8\n"
    "      cmd LC_VERSION_MIN_MACOSX\n"
    "  cmdsize 16\n"
    "  version 15.0\n"
    "      sdk 15.0\n"
)

VTOOL_UNIVERSAL = vtool_capture("26.0") + vtool_capture("26.0").split(":\n", 1)[1]

CODESIGN_ADHOC = (
    "Executable=/Users/runner/work/driver/driver/artifacts/local-adhoc.Ab12Cd/"
    "label-driver-diagnostics\n"
    "Identifier=label-driver-diagnostics\n"
    "Format=Mach-O thin (arm64)\n"
    "CodeDirectory v=20400 size=1129 flags=0x2(adhoc) hashes=27+7 location=embedded\n"
    "Hash type=sha256 size=32\n"
    "CandidateCDHash sha256=3f1a9c0e7b2d4a6f8c1e0b5d9a7f3c2e1d0b8a64\n"
    "Hash choices=sha256\n"
    "CMSDigestType=2\n"
    "CDHash=3f1a9c0e7b2d4a6f8c1e0b5d9a7f3c2e1d0b8a64\n"
    "Signature=adhoc\n"
    "Info.plist=not bound\n"
    "TeamIdentifier=not set\n"
    "Sealed Resources=none\n"
    "Internal requirements count=0 size=12\n"
)

CODESIGN_DEVELOPER_ID = (
    "Executable=/Users/runner/work/driver/driver/artifacts/setup-app.Zz99/"
    "Label Printer Driver Setup.app/Contents/MacOS/label-printer-setup\n"
    "Identifier=net.bherila.label-printer-driver.setup\n"
    "Format=app bundle with Mach-O thin (arm64)\n"
    "CodeDirectory v=20500 size=2048 flags=0x10000(runtime) hashes=55+7 "
    "location=embedded\n"
    "Signature size=9012\n"
    "Authority=Developer ID Application: Example Org (AB12CD34EF)\n"
    "Authority=Developer ID Certification Authority\n"
    "Authority=Apple Root CA\n"
    "Timestamp=Sep 18, 2026 at 11:04:12\n"
    "Info.plist entries=12\n"
    "TeamIdentifier=AB12CD34EF\n"
    "Sealed Resources version=2 rules=13 files=0\n"
    "Internal requirements count=1 size=180\n"
)

CODESIGN_UNSIGNED = (
    "/Users/runner/work/driver/driver/.build/release/label-driver: code object "
    "is not signed at all\n"
    "CAPTURE-TOOL-FAILED status=1\n"
)

DIAGNOSTIC_OK = (
    '{"coreGraphicsWhitePixel":255,"driverImplemented":false,'
    '"printerIOPerformed":false,"stage":"scaffold"}\n'
)

BUNDLE_OK = (
    '{"CFBundleExecutable":"label-printer-setup","CFBundleIdentifier":'
    '"net.bherila.label-printer-driver.setup","LSMinimumSystemVersion":"26.0",'
    '"LabelDriverSigningMode":"local-ad-hoc","NSHighResolutionCapable":true}\n'
)

SIGN_LOG = (
    "Executable=/x/artifacts/local-adhoc.Ab12Cd/label-driver\n"
    "Signature=adhoc\n"
    "Verified local-ad-hoc command-line products in: "
    "/Users/runner/work/driver/driver/artifacts/local-adhoc.Ab12Cd\n"
    "This does not validate installed spooler/helper or Gatekeeper admission.\n"
)

APP_LOG = (
    "Built and verified local-ad-hoc app: /Users/runner/work/driver/driver/"
    "artifacts/setup-app.Zz99/Label Printer Driver Setup.app\n"
    "Built from source revision: 9fe4d4840a7a\n"
    "This does not establish Gatekeeper, installation, scheduler, or printer "
    "acceptance.\n"
)


class ArchitectureRuleTests(unittest.TestCase):
    def test_thin_arm64_capture_is_accepted(self):
        self.assertEqual(checker.architecture_errors("label-driver", ARM64_ONLY), [])

    def test_universal_capture_is_rejected_as_an_intel_slice(self):
        errors = checker.architecture_errors("label-driver", UNIVERSAL)
        self.assertTrue(any("Intel slice" in error for error in errors), errors)
        self.assertTrue(any("x86_64" in error for error in errors), errors)

    def test_intel_only_capture_is_rejected(self):
        errors = checker.architecture_errors("label-driver", INTEL_ONLY)
        self.assertTrue(any("Intel slice" in error for error in errors), errors)

    def test_unrelated_single_architecture_is_rejected_without_an_intel_claim(self):
        """A non-Intel wrong answer must still fail, and for the right reason."""
        errors = checker.architecture_errors("label-driver", "arm64e\n")
        self.assertTrue(any("expected exactly `arm64`" in e for e in errors), errors)
        self.assertFalse(any("Intel slice" in error for error in errors), errors)

    def test_failed_tool_capture_is_rejected(self):
        errors = checker.architecture_errors("label-driver", LIPO_FAILED)
        self.assertEqual(
            errors, ["label-driver: `lipo -archs` failed; its capture cannot "
                     "establish anything"])

    def test_empty_and_whitespace_captures_are_rejected(self):
        for capture in ("", "   \n\n"):
            with self.subTest(capture=repr(capture)):
                errors = checker.architecture_errors("label-driver", capture)
                self.assertTrue(any("empty capture" in e for e in errors), errors)

    def test_multiple_lines_are_rejected(self):
        errors = checker.architecture_errors("label-driver", "arm64\narm64\n")
        self.assertTrue(any("found 2" in error for error in errors), errors)


class MinimumOSRuleTests(unittest.TestCase):
    def test_baseline_minimum_is_accepted(self):
        self.assertEqual(checker.minimum_os_errors("label-driver",
                                                   vtool_capture("26.0")), [])

    def test_three_component_spelling_of_the_baseline_is_accepted(self):
        self.assertEqual(checker.minimum_os_errors("label-driver",
                                                   vtool_capture("26.0.0")), [])

    def test_a_minimum_below_the_baseline_is_rejected(self):
        errors = checker.minimum_os_errors("label-driver", vtool_capture("15.0"))
        self.assertTrue(any("minimum macOS is 15.0" in e for e in errors), errors)

    def test_a_minimum_above_the_baseline_is_rejected(self):
        """Bracketed from both sides: 27.0 drops supported hosts silently."""
        errors = checker.minimum_os_errors("label-driver", vtool_capture("27.0"))
        self.assertTrue(any("minimum macOS is 27.0" in e for e in errors), errors)

    def test_nearest_rejected_neighbours_of_the_baseline(self):
        for minos in ("25.9", "26.1", "26.0.1"):
            with self.subTest(minos=minos):
                errors = checker.minimum_os_errors("label-driver",
                                                   vtool_capture(minos))
                self.assertTrue(
                    any(f"minimum macOS is {minos}" in e for e in errors), errors)

    def test_non_macos_platform_is_rejected(self):
        errors = checker.minimum_os_errors(
            "label-driver", vtool_capture("26.0", platform="MACCATALYST"))
        self.assertTrue(any("expected platform MACOS" in e for e in errors), errors)

    def test_legacy_version_min_load_command_is_rejected(self):
        errors = checker.minimum_os_errors("label-driver", VTOOL_LEGACY)
        self.assertTrue(
            any("LC_VERSION_MIN_MACOSX" in error for error in errors), errors)
        self.assertTrue(
            any("exactly one LC_BUILD_VERSION" in e for e in errors), errors)

    def test_two_build_version_load_commands_are_rejected(self):
        errors = checker.minimum_os_errors("label-driver", VTOOL_UNIVERSAL)
        self.assertTrue(any("found 2" in error for error in errors), errors)

    def test_unparsable_minimum_is_rejected(self):
        errors = checker.minimum_os_errors(
            "label-driver", vtool_capture("twenty-six"))
        self.assertTrue(any("unparsable" in error for error in errors), errors)

    def test_missing_minos_field_is_rejected(self):
        capture = vtool_capture("26.0").replace("    minos 26.0\n", "")
        errors = checker.minimum_os_errors("label-driver", capture)
        self.assertTrue(any("no `minos` field" in error for error in errors), errors)

    def test_failed_and_empty_captures_are_rejected(self):
        self.assertTrue(checker.minimum_os_errors("label-driver", LIPO_FAILED))
        self.assertTrue(checker.minimum_os_errors("label-driver", "\n"))

    def test_the_expected_constant_is_the_repository_baseline(self):
        """The constant is pinned, not read back from the capture under test."""
        self.assertEqual(checker.EXPECTED_MINIMUM_MACOS, "26.0")


class SignatureRuleTests(unittest.TestCase):
    def test_adhoc_capture_is_accepted(self):
        self.assertEqual(checker.signature_errors("diagnostic", CODESIGN_ADHOC), [])

    def test_developer_id_capture_is_rejected_on_every_rule(self):
        errors = checker.signature_errors("setup-app", CODESIGN_DEVELOPER_ID)
        self.assertTrue(any("certificate-backed signature" in e for e in errors),
                        errors)
        self.assertTrue(any("AB12CD34EF" in error for error in errors), errors)
        self.assertTrue(any("certificate authority" in e for e in errors), errors)
        self.assertTrue(any("0x10000(runtime)" in e for e in errors), errors)

    def test_a_team_identifier_alone_is_rejected(self):
        """Ad-hoc plus a Team ID must fail for the Team ID, not for something else."""
        capture = CODESIGN_ADHOC.replace("TeamIdentifier=not set",
                                         "TeamIdentifier=AB12CD34EF")
        errors = checker.signature_errors("diagnostic", capture)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("`TeamIdentifier=not set`", errors[0])
        self.assertIn("AB12CD34EF", errors[0])

    def test_an_authority_alone_is_rejected(self):
        capture = CODESIGN_ADHOC.replace(
            "Info.plist=not bound\n",
            "Authority=Developer ID Application: Example Org (AB12CD34EF)\n")
        errors = checker.signature_errors("diagnostic", capture)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("certificate authority", errors[0])

    def test_a_missing_signature_field_is_rejected(self):
        capture = CODESIGN_ADHOC.replace("Signature=adhoc\n", "")
        errors = checker.signature_errors("diagnostic", capture)
        self.assertTrue(any("no `Signature=` field" in e for e in errors), errors)

    def test_unsigned_capture_is_rejected(self):
        errors = checker.signature_errors("label-driver", CODESIGN_UNSIGNED)
        self.assertEqual(
            errors,
            ["label-driver: `codesign -dv` failed; its capture cannot establish "
             "anything"])

    def test_empty_capture_is_rejected(self):
        errors = checker.signature_errors("label-driver", "")
        self.assertTrue(any("empty capture" in error for error in errors), errors)

    def test_linker_signed_adhoc_flags_are_accepted(self):
        capture = CODESIGN_ADHOC.replace("flags=0x2(adhoc)",
                                         "flags=0x20002(adhoc,linker-signed)")
        self.assertEqual(checker.signature_errors("worker", capture), [])


class DiagnosticRuleTests(unittest.TestCase):
    def test_inert_diagnostic_capture_is_accepted(self):
        self.assertEqual(checker.diagnostic_errors("diagnostic", DIAGNOSTIC_OK), [])

    def test_reported_printer_io_is_rejected(self):
        capture = DIAGNOSTIC_OK.replace('"printerIOPerformed":false',
                                        '"printerIOPerformed":true')
        errors = checker.diagnostic_errors("diagnostic", capture)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("printerIOPerformed", errors[0])
        self.assertIn("exactly false", errors[0])

    def test_zero_is_not_a_reported_false(self):
        """An unknown or numeric state is not the same claim as false."""
        for substitute in ("0", "null", '""'):
            with self.subTest(substitute=substitute):
                capture = DIAGNOSTIC_OK.replace('"printerIOPerformed":false',
                                                f'"printerIOPerformed":{substitute}')
                errors = checker.diagnostic_errors("diagnostic", capture)
                self.assertTrue(
                    any("exactly false" in error for error in errors), errors)

    def test_missing_fields_are_rejected(self):
        capture = '{"coreGraphicsWhitePixel":255,"stage":"scaffold"}\n'
        errors = checker.diagnostic_errors("diagnostic", capture)
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(any("printerIOPerformed" in e for e in errors), errors)
        self.assertTrue(any("driverImplemented" in e for e in errors), errors)

    def test_wrong_core_graphics_pixel_is_rejected(self):
        for substitute in ("0", "254", "true"):
            with self.subTest(substitute=substitute):
                capture = DIAGNOSTIC_OK.replace('"coreGraphicsWhitePixel":255',
                                                f'"coreGraphicsWhitePixel":{substitute}')
                errors = checker.diagnostic_errors("diagnostic", capture)
                self.assertTrue(
                    any("white pixel 255" in error for error in errors), errors)

    def test_non_json_capture_is_rejected(self):
        capture = "Building for production...\nBuild complete! (0.5s)\n"
        errors = checker.diagnostic_errors("diagnostic", capture)
        self.assertEqual(
            errors, ["diagnostic: diagnostic output is not a single JSON object"])

    def test_json_that_is_not_an_object_is_rejected(self):
        errors = checker.diagnostic_errors("diagnostic", "[255]\n")
        self.assertTrue(any("not a JSON object" in e for e in errors), errors)

    def test_failed_and_empty_captures_are_rejected(self):
        self.assertTrue(checker.diagnostic_errors("diagnostic",
                                                  "boom\nCAPTURE-TOOL-FAILED status=1\n"))
        self.assertTrue(checker.diagnostic_errors("diagnostic", ""))


class BundleMetadataRuleTests(unittest.TestCase):
    def test_baseline_bundle_metadata_is_accepted(self):
        self.assertEqual(checker.bundle_metadata_errors("app", BUNDLE_OK), [])

    def test_a_lower_declared_minimum_system_version_is_rejected(self):
        capture = BUNDLE_OK.replace('"LSMinimumSystemVersion":"26.0"',
                                    '"LSMinimumSystemVersion":"15.0"')
        errors = checker.bundle_metadata_errors("app", capture)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("LSMinimumSystemVersion", errors[0])

    def test_a_developer_id_signing_mode_claim_is_rejected(self):
        capture = BUNDLE_OK.replace('"LabelDriverSigningMode":"local-ad-hoc"',
                                    '"LabelDriverSigningMode":"developer-id"')
        errors = checker.bundle_metadata_errors("app", capture)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("LabelDriverSigningMode", errors[0])

    def test_missing_entries_are_rejected(self):
        errors = checker.bundle_metadata_errors("app", '{"CFBundleName":"x"}\n')
        self.assertEqual(len(errors), 3, errors)

    def test_non_json_and_empty_captures_are_rejected(self):
        self.assertTrue(checker.bundle_metadata_errors("app", "<?xml version=?>\n"))
        self.assertTrue(checker.bundle_metadata_errors("app", ""))


class PathMarkerTests(unittest.TestCase):
    def test_signed_directory_is_read_from_the_log(self):
        path, errors = checker.path_after_marker(
            "signed-directory", SIGN_LOG, checker.SIGNED_DIRECTORY_MARKER)
        self.assertEqual(errors, [])
        self.assertEqual(
            path, "/Users/runner/work/driver/driver/artifacts/local-adhoc.Ab12Cd")

    def test_app_path_with_spaces_is_read_whole(self):
        path, errors = checker.path_after_marker(
            "built-app-path", APP_LOG, checker.BUILT_APP_MARKER)
        self.assertEqual(errors, [])
        self.assertTrue(path.endswith("Label Printer Driver Setup.app"), path)

    def test_a_missing_marker_is_rejected(self):
        path, errors = checker.path_after_marker(
            "built-app-path", SIGN_LOG, checker.BUILT_APP_MARKER)
        self.assertIsNone(path)
        self.assertTrue(any("no line beginning" in e for e in errors), errors)

    def test_two_different_paths_are_rejected(self):
        capture = APP_LOG + APP_LOG.replace("Zz99", "Yy88")
        path, errors = checker.path_after_marker(
            "built-app-path", capture, checker.BUILT_APP_MARKER)
        self.assertIsNone(path)
        self.assertTrue(any("2 different paths" in e for e in errors), errors)

    def test_a_repeated_identical_path_is_accepted(self):
        path, errors = checker.path_after_marker(
            "built-app-path", APP_LOG + APP_LOG, checker.BUILT_APP_MARKER)
        self.assertEqual(errors, [])
        self.assertTrue(path.endswith("Label Printer Driver Setup.app"), path)

    def test_a_relative_path_is_rejected(self):
        capture = checker.BUILT_APP_MARKER + "artifacts/setup-app.Zz99/App.app\n"
        path, errors = checker.path_after_marker(
            "built-app-path", capture, checker.BUILT_APP_MARKER)
        self.assertIsNone(path)
        self.assertTrue(any("absolute path" in error for error in errors), errors)

    def test_an_empty_path_is_rejected(self):
        path, errors = checker.path_after_marker(
            "built-app-path", checker.BUILT_APP_MARKER + "\n",
            checker.BUILT_APP_MARKER)
        self.assertIsNone(path)
        self.assertTrue(any("empty path" in error for error in errors), errors)


class CommandLineTests(unittest.TestCase):
    """The documented contract: exit 0 pass, 1 assertion failure, 2 cannot judge."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def capture_file(self, name: str, text: str) -> Path:
        path = self.root / name
        path.write_text(text, encoding="utf-8")
        return path

    def run_checker(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(SCRIPT), *args],
                              capture_output=True, text=True, timeout=60)

    def test_passing_check_exits_zero(self):
        capture = self.capture_file("lipo.txt", ARM64_ONLY)
        result = self.run_checker("architecture", "label-driver", str(capture))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OK architecture label-driver", result.stdout)

    def test_failing_check_exits_one_and_names_the_artifact(self):
        capture = self.capture_file("lipo.txt", UNIVERSAL)
        result = self.run_checker("architecture", "label-driver", str(capture))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("ERROR: label-driver", result.stderr)
        self.assertIn("Intel slice", result.stderr)

    def test_minimum_os_failure_exits_one(self):
        capture = self.capture_file("vtool.txt", vtool_capture("15.0"))
        result = self.run_checker("minimum-os", "label-driver", str(capture))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("minimum macOS is 15.0", result.stderr)

    def test_signature_failure_exits_one(self):
        capture = self.capture_file("codesign.txt", CODESIGN_DEVELOPER_ID)
        result = self.run_checker("signature", "setup-app", str(capture))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("TeamIdentifier", result.stderr)

    def test_locator_prints_only_the_path(self):
        capture = self.capture_file("app.log", APP_LOG)
        result = self.run_checker("built-app-path", str(capture))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "/Users/runner/work/driver/driver/artifacts/setup-app.Zz99/"
            "Label Printer Driver Setup.app\n")

    def test_locator_failure_exits_one(self):
        capture = self.capture_file("app.log", SIGN_LOG)
        result = self.run_checker("built-app-path", str(capture))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(result.stdout, "")

    def test_missing_capture_file_exits_two(self):
        result = self.run_checker("architecture", "label-driver",
                                  str(self.root / "absent.txt"))
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("Cannot read capture", result.stderr)

    def test_unknown_check_exits_two(self):
        result = self.run_checker("entitlements", "x", str(self.root))
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("Unknown check", result.stderr)

    def test_wrong_argument_count_exits_two(self):
        capture = self.capture_file("lipo.txt", ARM64_ONLY)
        for args in ((), ("architecture", str(capture)),
                     ("built-app-path", "a", "b")):
            with self.subTest(args=args):
                result = self.run_checker(*args)
                self.assertEqual(result.returncode, 2, result.stdout)


class CoveredArtifactsTests(unittest.TestCase):
    """The CI script must actually apply these rules to the built products."""

    def setUp(self):
        self.ci_swift = (SCRIPTS / "ci-swift.sh").read_text(encoding="utf-8")

    def test_ci_script_invokes_the_checker_for_every_check(self):
        for name in checker.CHECKS:
            with self.subTest(check=name):
                self.assertIn(f"check_native_artifacts.py {name}", self.ci_swift)

    def test_ci_script_no_longer_prints_an_unasserted_architecture(self):
        """`lipo -archs` outside a capture exits 0 on any architecture."""
        for line in self.ci_swift.splitlines():
            stripped = line.strip()
            if stripped.startswith("lipo ") or stripped.startswith("file "):
                self.fail(f"unasserted architecture print in ci-swift.sh: {stripped}")

    def test_ci_script_marks_failed_tool_captures(self):
        self.assertIn(checker.TOOL_FAILURE_MARKER, self.ci_swift)


if __name__ == "__main__":
    unittest.main()
