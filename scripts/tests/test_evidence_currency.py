import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


currency = _load('evidence_currency')
reporter = _load('traceability_report')


class SyntheticEvidenceRepository(unittest.TestCase):
    """One synthetic repository with two criteria, one A and one H, and a truthful manifest."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'docs/milestones/synthetic').mkdir(parents=True)
        (self.root / 'docs/validation').mkdir(parents=True)
        self.write_json('docs/milestones.json', [{'n': 3, 'slug': 'synthetic', 'criteria': [
            ['Validation', 'A', 'Synthetic automated requirement'],
            ['Device', 'H', 'Synthetic physical requirement']]}])
        (self.root / 'docs/milestones/synthetic/ACCEPTANCE.md').write_text(
            '| [x] | M3-AC01 |\n| [x] | M3-AC02 |\n')
        self.write_json('docs/requirements.json', {'requirements': [
            {'id': 'F01', 'mandatory': True, 'acceptanceIDs': ['M3-AC01', 'M3-AC02']}]})
        (self.root / 'implementation.swift').write_text('synthetic implementation\n')
        # A second source file no record cites, so a change to it isolates staleness from a
        # changed cited digest. Changing a cited file breaks both at once and hides the difference.
        (self.root / 'unrelated.swift').write_text('synthetic neighbour\n')
        (self.root / 'docs/validation/evidence.md').write_text('synthetic declared assessment\n')
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        self.records = [self.record('M3-AC01', 'A'), self.record('M3-AC02', 'H')]
        self.evaluated = self.commit()
        self.rebind(self.evaluated)

    # -- fixture helpers -------------------------------------------------

    def write_json(self, name, value):
        (self.root / name).write_text(json.dumps(value) + '\n')

    def reference(self, name):
        return {'path': name, 'sha256': hashlib.sha256((self.root / name).read_bytes()).hexdigest()}

    def record(self, identifier, level, state='pass'):
        return {'acceptanceID': identifier, 'level': level, 'state': state, 'sourceSHA': 'a' * 40,
                'implementation': [self.reference('implementation.swift')],
                'evidence': [self.reference('docs/validation/evidence.md')]}

    def write_ledger(self):
        self.write_json('docs/ACCEPTANCE-EVIDENCE.json',
                        {'schemaVersion': 1, 'records': self.records})

    def write_manifest(self):
        """Cover every tracked file except the manifest itself, the way the repository does."""
        self.write_ledger()
        names = []
        for path in sorted(self.root.rglob('*')):
            if path.is_file() and '.git' not in path.relative_to(self.root).parts:
                name = str(path.relative_to(self.root))
                if name != 'MANIFEST.sha256':
                    names.append(name)
        lines = [f'{hashlib.sha256((self.root / n).read_bytes()).hexdigest()}  {n}' for n in names]
        (self.root / 'MANIFEST.sha256').write_text('\n'.join(lines) + '\n')

    def commit(self, message='Synthetic checkpoint'):
        self.write_manifest()
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                        '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                        '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                        'commit', '-qm', message], check=True)
        return subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'],
                                       text=True).strip()

    def rebind(self, sha):
        """Point every record at `sha` and commit that ledger, as an evidence slice does."""
        for record in self.records:
            record['sourceSHA'] = sha
        return self.commit('Synthetic evidence slice')

    # -- convenience -----------------------------------------------------

    def evaluate(self, **kwargs):
        return currency.evaluate(self.root, **kwargs)

    def verdicts(self, result):
        return {row['id']: row['evidenceStatus']['verdict'] for row in result['report']['acceptance']}

    def codes(self, result, severity=None):
        return sorted(item['code'] for item in result['findings']
                      if severity is None or item['severity'] == severity)

    def tree_digest(self):
        digest = hashlib.sha256()
        for path in sorted(self.root.rglob('*')):
            if path.is_file() and '.git' not in path.relative_to(self.root).parts:
                digest.update(str(path.relative_to(self.root)).encode())
                digest.update(path.read_bytes())
        return digest.hexdigest()


class EvidenceCurrencyTests(SyntheticEvidenceRepository):
    def test_bound_records_are_qualified_and_the_diagnostic_is_clean(self):
        result = self.evaluate()
        self.assertEqual({'M3-AC01': 'qualified', 'M3-AC02': 'qualified'}, self.verdicts(result))
        self.assertEqual([], result['gating'])

    def test_evidence_only_commit_does_not_invalidate_a_record(self):
        # Validation Markdown, the ledger and a truthful manifest refresh are bookkeeping. Recording
        # evidence must be able to happen without the act of recording it invalidating the record.
        (self.root / 'docs/validation/evidence.md').write_text('synthetic declared assessment\n\nAddendum.\n')
        self.records[0]['evidence'] = [self.reference('docs/validation/evidence.md')]
        self.records[1]['evidence'] = [self.reference('docs/validation/evidence.md')]
        self.commit('Evidence-only follow-up')
        result = self.evaluate()
        self.assertEqual({'M3-AC01': 'qualified', 'M3-AC02': 'qualified'}, self.verdicts(result))
        self.assertNotIn('STALE-SOURCE', self.codes(result))
        self.assertEqual([], result['gating'])

    def test_a_source_change_makes_every_record_stale(self):
        (self.root / 'unrelated.swift').write_text('changed build input\n')
        self.commit('Source slice')
        result = self.evaluate()
        self.assertEqual({'M3-AC01': 'stale-source', 'M3-AC02': 'stale-source'}, self.verdicts(result))
        self.assertIn('STALE-SOURCE', self.codes(result, severity=currency.REPORT))
        # Reported by default so a source PR is not failed for doing its own job...
        self.assertEqual([], result['gating'])
        # ...and gating on request, which is what a main-push gate would turn on.
        gated = self.evaluate(gate_stale=True)
        self.assertEqual(['STALE-SOURCE', 'STALE-SOURCE'], self.codes(gated, severity=currency.GATE))

    def test_a_stale_record_still_reports_its_digest_and_level_as_answered(self):
        (self.root / 'unrelated.swift').write_text('changed build input\n')
        self.commit('Source slice')
        row = next(r for r in self.evaluate()['report']['acceptance'] if r['id'] == 'M3-AC01')
        status = row['evidenceStatus']
        self.assertTrue(status['checkboxComplete'])
        self.assertTrue(status['hasDigestValidRecord'])
        self.assertTrue(status['hasRequiredLevelRecord'])
        self.assertFalse(status['hasCurrentSourceRecord'])
        self.assertFalse(status['qualified'])

    def test_changed_evidence_bytes_are_invalid_references_not_staleness(self):
        # docs/validation Markdown is exempt from the currency rule, so the record stays current
        # while the bytes it cites stop matching. That is the ledger being wrong, and it gates.
        (self.root / 'docs/validation/evidence.md').write_text('rewritten without re-sealing\n')
        self.commit('Evidence rewritten, digest not refreshed')
        result = self.evaluate()
        self.assertEqual({'M3-AC01': 'invalid-references', 'M3-AC02': 'invalid-references'},
                         self.verdicts(result))
        self.assertEqual(['INVALID-REFERENCES', 'INVALID-REFERENCES'],
                         self.codes(result, severity=currency.GATE))

    def test_an_automated_record_never_promotes_a_physical_row(self):
        self.records[1] = self.record('M3-AC02', 'A')
        self.rebind(self.evaluate()['sourceSHA'])
        result = self.evaluate()
        self.assertEqual('wrong-evidence-level', self.verdicts(result)['M3-AC02'])
        self.assertIn('LEVEL-PROMOTION', self.codes(result, severity=currency.GATE))
        self.assertIn('WRONG-EVIDENCE-LEVEL', self.codes(result, severity=currency.GATE))

    def test_a_checked_box_with_no_record_is_visible_and_not_counted_as_qualified(self):
        self.records = [self.record('M3-AC01', 'A')]
        self.rebind(self.evaluate()['sourceSHA'])
        result = self.evaluate()
        self.assertEqual('claimed-without-record', self.verdicts(result)['M3-AC02'])
        self.assertIn('CLAIMED-WITHOUT-RECORD', self.codes(result, severity=currency.REPORT))
        self.assertFalse(result['report']['readyForMaintainerReview'])

    def test_a_current_blocker_vetoes_the_row(self):
        blocked = self.record('M3-AC01', 'A', state='blocked')
        blocked['level'] = 'C'  # A distinct (id, level, sha) selector; the state is what matters.
        self.records.append(blocked)
        self.rebind(self.evaluate()['sourceSHA'])
        result = self.evaluate()
        self.assertEqual('current-blocker', self.verdicts(result)['M3-AC01'])
        self.assertIn('CURRENT-BLOCKER', self.codes(result, severity=currency.GATE))

    # -- fail-closed -----------------------------------------------------

    def test_a_missing_binding_gates_rather_than_passing_quietly(self):
        self.records[0]['implementation'] = []
        self.rebind(self.evaluate()['sourceSHA'])
        result = self.evaluate()
        # A record that cites nothing also has no valid references, so both findings are correct.
        self.assertIn('MISSING-BINDING', self.codes(result, severity=currency.GATE))

    def test_an_unreadable_manifest_cannot_be_evaluated(self):
        for body in ['not a manifest line\n', '', 'x' * 64 + ' onespace\n']:
            with self.subTest(body=body):
                (self.root / 'MANIFEST.sha256').write_text(body)
                subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
                subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                                '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                                '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                                'commit', '-qm', 'Broken manifest'], check=True)
                with self.assertRaises(currency.CannotEvaluate):
                    self.evaluate()

    def test_an_absent_manifest_cannot_be_evaluated(self):
        (self.root / 'MANIFEST.sha256').unlink()
        subprocess.run(['git', '-C', str(self.root), 'rm', '-q', '--cached', 'MANIFEST.sha256'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                        '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                        '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                        'commit', '-qm', 'Manifest removed'], check=True)
        with self.assertRaises(currency.CannotEvaluate):
            self.evaluate()

    def test_an_exhausted_deadline_cannot_be_evaluated(self):
        with self.assertRaises(currency.CannotEvaluate):
            self.evaluate(budget=0)
        with self.assertRaises(currency.CannotEvaluate):
            self.evaluate(budget=-5)

    def test_a_corrupt_ledger_cannot_be_evaluated(self):
        (self.root / 'docs/ACCEPTANCE-EVIDENCE.json').write_text('{"schemaVersion": 1, "records": {}}\n')
        with self.assertRaises(currency.CannotEvaluate):
            self.evaluate()
        (self.root / 'docs/ACCEPTANCE-EVIDENCE.json').write_text('not json\n')
        with self.assertRaises(currency.CannotEvaluate):
            self.evaluate()

    def test_a_directory_without_git_cannot_be_evaluated(self):
        with tempfile.TemporaryDirectory() as bare:
            with self.assertRaises(currency.CannotEvaluate):
                currency.evaluate(Path(bare))

    def test_a_dirty_worktree_is_reported_and_leaves_nothing_current(self):
        (self.root / 'implementation.swift').write_text('uncommitted edit\n')
        result = self.evaluate()
        self.assertTrue(result['workspaceDirty'])
        self.assertIn('WORKSPACE-DIRTY', self.codes(result, severity=currency.REPORT))
        self.assertEqual({'M3-AC01', 'M3-AC02'},
                         {row['id'] for row in result['report']['acceptance']
                          if not row['evidenceStatus']['hasCurrentSourceRecord']})

    # -- read-only -------------------------------------------------------

    def test_the_diagnostic_changes_no_byte_of_the_repository(self):
        before = self.tree_digest()
        (self.root / 'unrelated.swift').write_text('changed build input\n')
        self.commit('Source slice')
        after_commit = self.tree_digest()
        self.assertNotEqual(before, after_commit)
        for gate in (False, True):
            self.evaluate(gate_stale=gate)
        self.assertEqual(after_commit, self.tree_digest())

    def test_the_command_line_separates_clean_gating_and_unevaluable(self):
        def run(*arguments):
            return subprocess.run([sys.executable, str(SCRIPTS / 'evidence_currency.py'),
                                   '--root', str(self.root), *arguments],
                                  capture_output=True, text=True, timeout=120)
        clean = run()
        self.assertEqual(currency.EXIT_CLEAN, clean.returncode, clean.stderr)
        self.assertIn('qualified', clean.stdout)
        payload = json.loads(run('--format', 'json').stdout)
        self.assertEqual(payload['report']['evidenceSummary']['qualified'], 2)

        self.records[0]['implementation'] = []
        self.rebind(payload['sourceSHA'])
        gating = run()
        self.assertEqual(currency.EXIT_FINDING, gating.returncode)
        self.assertIn('MISSING-BINDING', gating.stdout)

        (self.root / 'MANIFEST.sha256').write_text('broken\n')
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                        '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                        '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                        'commit', '-qm', 'Broken manifest'], check=True)
        refused = run()
        self.assertEqual(currency.EXIT_CANNOT_EVALUATE, refused.returncode)
        self.assertIn('CANNOT-EVALUATE', refused.stderr)
        self.assertIn('not a skip', refused.stderr)


if __name__ == '__main__':
    unittest.main()
