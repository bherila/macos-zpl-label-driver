import hashlib
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('refresh_manifest', SCRIPTS / 'refresh_manifest.py')
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


class RefreshManifestTests(unittest.TestCase):
    """The writing half of ADR 0004. Widening is permitted; shrinking never is."""

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

    def entries(self):
        text = (self.root / 'MANIFEST.sha256').read_text()
        return {line.split('  ', 1)[1]: line.split('  ', 1)[0]
                for line in text.splitlines() if line}

    def test_a_drifted_digest_is_refreshed_in_place(self):
        (self.root / 'README.md').write_text('changed after the manifest was written\n')
        self.commit()
        result = refresh.refresh(self.root, backfill=False)
        self.assertEqual(result['changed'], ['README.md'])
        self.assertEqual(result['added'], [])
        expected = hashlib.sha256((self.root / 'README.md').read_bytes()).hexdigest()
        self.assertIn(f'{expected}  README.md\n', result['body'])

    def test_a_refresh_never_removes_an_entry_it_did_not_add(self):
        # Shrinking coverage is corrupted integrity metadata, not bookkeeping.
        before = set(self.entries())
        result = refresh.refresh(self.root, backfill=False)
        after = {line.split('  ', 1)[1] for line in result['body'].splitlines() if line}
        self.assertEqual(before, after)

    def test_backfill_widens_to_every_tracked_file_but_never_the_manifest(self):
        result = refresh.refresh(self.root, backfill=True)
        covered = {line.split('  ', 1)[1] for line in result['body'].splitlines() if line}
        self.assertEqual(covered, set(self.covered) | set(self.uncovered))
        self.assertNotIn('MANIFEST.sha256', covered, 'the manifest never describes itself')
        self.assertEqual(sorted(result['added']), sorted(self.uncovered))

    def test_an_unreadable_entry_keeps_its_recorded_digest_and_is_refused(self):
        recorded = self.entries()['README.md']
        (self.root / 'README.md').unlink()
        result = refresh.refresh(self.root, backfill=False)
        self.assertIn(f'{recorded}  README.md\n', result['body'],
                      'an absent file must not be rewritten to a placeholder digest')
        self.assertIn('README.md', [name for name, _ in result['refused']])

    def test_output_is_byte_sorted_and_stable_across_runs(self):
        first = refresh.refresh(self.root, backfill=True)['body']
        (self.root / 'MANIFEST.sha256').write_text(first)
        self.commit()
        second = refresh.refresh(self.root, backfill=True)['body']
        self.assertEqual(first, second, 'a second refresh must be a no-op')
        names = [line.split('  ', 1)[1] for line in first.splitlines() if line]
        self.assertEqual(names, sorted(names))

    def test_more_entries_than_a_valid_manifest_may_hold_is_refused(self):
        original = refresh.MAXIMUM_ENTRIES
        refresh.MAXIMUM_ENTRIES = 1
        try:
            with self.assertRaises(refresh.CannotMeasure):
                refresh.refresh(self.root, backfill=True)
        finally:
            refresh.MAXIMUM_ENTRIES = original

    def test_check_reports_without_writing(self):
        (self.root / 'README.md').write_text('drifted\n')
        self.commit()
        before = (self.root / 'MANIFEST.sha256').read_bytes()
        refresh.refresh(self.root, backfill=False)
        self.assertEqual((self.root / 'MANIFEST.sha256').read_bytes(), before,
                         'refresh() itself must not write; only main() does')


if __name__ == '__main__':
    unittest.main()
