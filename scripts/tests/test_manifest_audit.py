import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('manifest_audit', SCRIPTS / 'manifest_audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ManifestAuditTests(unittest.TestCase):
    """Measurement only. Nothing here adds an entry, refreshes a digest or decides manifest scope."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Packages/LabelCore/Sources/LabelCore').mkdir(parents=True)
        (self.root / 'docs/validation').mkdir(parents=True)
        self.covered = ['README.md', 'Packages/LabelCore/Sources/LabelCore/Layout.swift']
        self.uncovered = ['docs/validation/RECEIPT.md',
                          'Packages/LabelCore/Sources/LabelCore/Uncovered.swift']
        for name in self.covered + self.uncovered:
            (self.root / name).write_text(f'contents of {name}\n')
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        self.write_manifest(self.covered)
        self.commit()

    def write_manifest(self, names):
        lines = [f'{hashlib.sha256((self.root / n).read_bytes()).hexdigest()}  {n}' for n in names]
        (self.root / 'MANIFEST.sha256').write_text('\n'.join(lines) + '\n')

    def commit(self):
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                        '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                        '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                        'commit', '-qm', 'Synthetic checkpoint'], check=True)

    def codes(self, result):
        return sorted(item['code'] for item in result['findings'])

    def test_partial_coverage_is_measured_rather_than_assumed(self):
        result = audit.audit(self.root)
        self.assertEqual(5, result['trackedFiles'])  # four files plus the manifest itself
        self.assertEqual(2, result['manifestEntries'])
        self.assertEqual(2, result['coveredTrackedFiles'])
        # The manifest never lists itself; that omission is intended and is not counted as drift.
        self.assertEqual(sorted(self.uncovered), result['omittedPaths'])
        self.assertEqual(['UNCOVERED-PATHS'], self.codes(result))
        self.assertEqual({'Packages/LabelCore (swift)': 1, 'docs/validation': 1},
                         result['omittedByArea'])
        self.assertEqual({'<root>': 1, 'Packages/LabelCore (swift)': 1}, result['coveredByArea'])

    def test_full_coverage_leaves_no_finding(self):
        self.write_manifest(self.covered + self.uncovered)
        self.commit()
        result = audit.audit(self.root, enforce_covered=True, enforce_coverage=True)
        self.assertEqual(0, result['omittedTrackedFiles'])
        self.assertEqual([], result['findings'])

    def test_a_drifted_digest_is_detected_and_gates_only_on_request(self):
        (self.root / 'README.md').write_text('edited without refreshing the manifest\n')
        self.commit()
        result = audit.audit(self.root)
        self.assertEqual(['README.md'], result['staleDigests'])
        self.assertIn('STALE-DIGEST', self.codes(result))
        self.assertEqual([], result['gating'])
        self.assertEqual(1, len(audit.audit(self.root, enforce_covered=True)['gating']))

    def test_an_entry_for_a_path_that_is_gone_is_detected(self):
        (self.root / 'README.md').unlink()
        subprocess.run(['git', '-C', str(self.root), 'rm', '-q', '--cached', 'README.md'], check=True)
        self.commit()
        result = audit.audit(self.root)
        self.assertEqual(['README.md'], result['absentPaths'])
        self.assertEqual(['README.md'], result['untrackedEntries'])
        self.assertIn('ABSENT-PATH', self.codes(result))
        self.assertIn('UNTRACKED-ENTRY', self.codes(result))

    def test_an_entry_for_an_untracked_file_is_detected(self):
        (self.root / 'scratch.txt').write_text('not tracked\n')
        self.write_manifest(self.covered + ['scratch.txt'])
        self.commit()  # `git add -A` would track it, so exclude it explicitly first.
        subprocess.run(['git', '-C', str(self.root), 'rm', '-q', '--cached', 'scratch.txt'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                        '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                        '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                        'commit', '-qm', 'Untrack scratch'], check=True)
        result = audit.audit(self.root)
        self.assertEqual(['scratch.txt'], result['untrackedEntries'])
        self.assertEqual([], result['absentPaths'])

    def test_a_symlinked_entry_is_never_hashed_through(self):
        (self.root / 'alias.md').symlink_to(self.root / 'README.md')
        self.write_manifest(self.covered)
        body = (self.root / 'MANIFEST.sha256').read_text()
        digest = hashlib.sha256((self.root / 'README.md').read_bytes()).hexdigest()
        (self.root / 'MANIFEST.sha256').write_text(body + f'{digest}  alias.md\n')
        self.commit()
        result = audit.audit(self.root)
        self.assertIn('alias.md', result['absentPaths'])

    def test_malformed_manifests_cannot_be_measured(self):
        for body in ['', 'no digest here\n', 'x' * 63 + '  short.md\n',
                     'a' * 64 + ' onespace.md\n', 'a' * 64 + '  \n']:
            with self.subTest(body=body):
                (self.root / 'MANIFEST.sha256').write_text(body)
                with self.assertRaises(audit.CannotMeasure):
                    audit.audit(self.root)

    def test_a_repeated_path_cannot_be_measured(self):
        line = f'{hashlib.sha256((self.root / "README.md").read_bytes()).hexdigest()}  README.md'
        (self.root / 'MANIFEST.sha256').write_text(line + '\n' + line + '\n')
        with self.assertRaises(audit.CannotMeasure):
            audit.audit(self.root)

    def test_a_non_utf8_manifest_cannot_be_measured(self):
        (self.root / 'MANIFEST.sha256').write_bytes(b'\xff\xfe not utf-8\n')
        with self.assertRaises(audit.CannotMeasure):
            audit.audit(self.root)

    def test_an_absent_manifest_cannot_be_measured(self):
        (self.root / 'MANIFEST.sha256').unlink()
        with self.assertRaises(audit.CannotMeasure):
            audit.audit(self.root)

    def test_a_directory_without_git_cannot_be_measured(self):
        with tempfile.TemporaryDirectory() as bare:
            with self.assertRaises(audit.CannotMeasure):
                audit.audit(Path(bare))

    def test_the_audit_changes_no_byte_of_the_repository(self):
        def snapshot():
            digest = hashlib.sha256()
            for path in sorted(self.root.rglob('*')):
                if path.is_file() and '.git' not in path.relative_to(self.root).parts:
                    digest.update(str(path.relative_to(self.root)).encode())
                    digest.update(path.read_bytes())
            return digest.hexdigest()
        before = snapshot()
        audit.audit(self.root)
        audit.audit(self.root, enforce_covered=True, enforce_coverage=True)
        self.assertEqual(before, snapshot())

    def test_the_command_line_separates_clean_gating_and_unmeasurable(self):
        def run(*arguments):
            return subprocess.run([sys.executable, str(SCRIPTS / 'manifest_audit.py'),
                                   '--root', str(self.root), *arguments],
                                  capture_output=True, text=True, timeout=60)
        measured = run()
        self.assertEqual(audit.EXIT_CLEAN, measured.returncode, measured.stderr)
        self.assertIn('UNCOVERED-PATHS', measured.stdout)
        payload = json.loads(run('--format', 'json').stdout)
        self.assertEqual(2, payload['omittedTrackedFiles'])
        self.assertEqual(audit.EXIT_FINDING, run('--enforce-coverage').returncode)
        (self.root / 'MANIFEST.sha256').write_text('broken\n')
        refused = run()
        self.assertEqual(audit.EXIT_CANNOT_MEASURE, refused.returncode)
        self.assertIn('CANNOT-MEASURE', refused.stderr)
        self.assertIn('not a skip', refused.stderr)


if __name__ == '__main__':
    unittest.main()
