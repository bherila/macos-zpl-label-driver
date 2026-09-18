import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('traceability_report', Path(__file__).resolve().parents[1] / 'traceability_report.py')
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)


class TraceabilityReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'docs/milestones/synthetic').mkdir(parents=True)
        self.sha = 'a' * 40
        self.write('docs/milestones.json', [{'n': 3, 'slug': 'synthetic', 'criteria': [
            ['Validation', 'A', 'Synthetic automated requirement'], ['Device', 'H', 'Synthetic physical requirement']]}])
        (self.root / 'docs/milestones/synthetic/ACCEPTANCE.md').write_text('| [x] | M3-AC01 |\n| [x] | M3-AC02 |\n')
        self.write('docs/requirements.json', {'requirements': [{'id': 'F01', 'mandatory': True,
                                                             'acceptanceIDs': ['M3-AC01', 'M3-AC02']}]})
        (self.root / 'implementation.swift').write_text('synthetic implementation\n')
        (self.root / 'evidence.md').write_text('synthetic declared assessment\n')
        self.records = [self.record('M3-AC01', 'A'), self.record('M3-AC02', 'H')]
        self.ledger()

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value) + '\n')

    def reference(self, name):
        return {'path': name, 'sha256': hashlib.sha256((self.root / name).read_bytes()).hexdigest()}

    def record(self, identifier, level):
        return {'acceptanceID': identifier, 'level': level, 'state': 'pass', 'sourceSHA': self.sha,
                'implementation': [self.reference('implementation.swift')], 'evidence': [self.reference('evidence.md')]}

    def ledger(self):
        self.write('docs/ACCEPTANCE-EVIDENCE.json', {'schemaVersion': 1, 'records': self.records})

    def report(self, dirty=False):
        self.ledger()
        return reporter.build_report(self.root, self.sha, dirty)

    def test_exact_complete_declarations_are_only_ready_for_review(self):
        report = self.report()
        self.assertTrue(report['readyForMaintainerReview'])
        self.assertNotIn('releaseQualified', report)
        self.assertIn('not independent', report['evidenceMeaning'])
        self.assertEqual(2, len(report['acceptance']))

    def test_automated_pass_never_substitutes_for_physical_evidence(self):
        self.records[1]['level'] = 'A'
        self.assertEqual(['M3-AC02'], self.report()['requirements'][0]['pendingAcceptanceIDs'])

    def test_empty_blocked_failed_and_not_applicable_never_pass(self):
        for state in ['blocked', 'fail', 'not-run', 'not-applicable']:
            with self.subTest(state=state):
                self.records[1]['state'] = state
                self.assertFalse(self.report()['readyForMaintainerReview'])
        self.records = []
        self.assertEqual(['M3-AC01', 'M3-AC02'], self.report()['requirements'][0]['pendingAcceptanceIDs'])

    def test_empty_references_and_changed_file_hashes_do_not_pass(self):
        self.records[1]['evidence'] = []
        self.assertFalse(self.report()['readyForMaintainerReview'])
        self.records[1] = self.record('M3-AC02', 'H')
        (self.root / 'evidence.md').write_text('changed synthetic assessment\n')
        self.assertFalse(self.report()['readyForMaintainerReview'])

    def test_old_source_and_dirty_workspace_do_not_pass(self):
        self.assertFalse(self.report(dirty=True)['readyForMaintainerReview'])
        self.records[1]['sourceSHA'] = 'b' * 40
        self.assertFalse(self.report()['readyForMaintainerReview'])

    def test_unchecked_acceptance_remains_pending_with_valid_references(self):
        table = self.root / 'docs/milestones/synthetic/ACCEPTANCE.md'
        table.write_text(table.read_text().replace('[x] | M3-AC02', '[ ] | M3-AC02'))
        self.assertFalse(self.report()['readyForMaintainerReview'])

    def test_escape_symlink_and_missing_references_fail_closed(self):
        alias = self.root / 'alias.md'
        alias.symlink_to(self.root / 'evidence.md')
        for name in ['../evidence.md', str(self.root / 'evidence.md'), 'missing.md', 'alias.md']:
            with self.subTest(name=name):
                self.records[1]['evidence'][0]['path'] = name
                self.assertFalse(self.report()['readyForMaintainerReview'])

    def test_duplicate_unknown_records_and_missing_mappings_are_rejected(self):
        self.records.append(self.records[0].copy())
        with self.assertRaises(ValueError): self.report()
        self.records.pop()
        self.records[1]['acceptanceID'] = 'M9-AC99'
        with self.assertRaises(ValueError): self.report()
        self.records[1]['acceptanceID'] = 'M3-AC02'
        self.write('docs/requirements.json', {'requirements': [{'id': 'F01', 'mandatory': True, 'acceptanceIDs': []}]})
        with self.assertRaises(ValueError): self.report()

    def test_evidence_only_descendants_preserve_candidate_but_code_changes_do_not(self):
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        def commit():
            subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                            '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                            'commit', '-qm', 'Synthetic test checkpoint'], check=True)
            return subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'], text=True).strip()
        evaluated = commit()
        self.records[0]['sourceSHA'] = evaluated
        self.records[1]['sourceSHA'] = evaluated
        self.ledger()
        evidence_commit = commit()
        self.assertTrue(reporter.source_is_unchanged(self.root, evaluated, evidence_commit))
        report = reporter.build_report(self.root, evidence_commit,
            source_matches=lambda sha: reporter.source_is_unchanged(self.root, sha, evidence_commit))
        self.assertTrue(report['readyForMaintainerReview'])
        (self.root / 'implementation.swift').write_text('changed build input\n')
        changed_commit = commit()
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, changed_commit))
        self.assertFalse(reporter.source_is_unchanged(self.root, changed_commit, evaluated))

    def test_manifest_refresh_preserves_candidate_but_cannot_mask_source_change(self):
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        def commit():
            subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                            '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                            'commit', '-qm', 'Synthetic test checkpoint'], check=True)
            return subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'], text=True).strip()
        (self.root / 'MANIFEST.sha256').write_text('0' * 64 + '  implementation.swift\n')
        evaluated = commit()
        self.records[0]['sourceSHA'] = evaluated
        self.records[1]['sourceSHA'] = evaluated
        self.ledger()
        # Recording evidence refreshes the derived manifest; that alone must not invalidate records.
        (self.root / 'MANIFEST.sha256').write_text('1' * 64 + '  implementation.swift\n')
        manifest_commit = commit()
        self.assertTrue(reporter.source_is_unchanged(self.root, evaluated, manifest_commit))
        report = reporter.build_report(self.root, manifest_commit,
            source_matches=lambda sha: reporter.source_is_unchanged(self.root, sha, manifest_commit))
        self.assertTrue(report['readyForMaintainerReview'])
        # A real source change is still caught even when the manifest moves with it.
        (self.root / 'implementation.swift').write_text('changed build input\n')
        (self.root / 'MANIFEST.sha256').write_text('2' * 64 + '  implementation.swift\n')
        changed_commit = commit()
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, changed_commit))

    def test_current_failure_blocks_other_pass_levels(self):
        failure = self.record('M3-AC02', 'A')
        failure['state'] = 'fail'
        self.records.append(failure)
        self.assertFalse(self.report()['readyForMaintainerReview'])

    def test_directory_symlinks_cannot_supply_reference_or_metadata(self):
        (self.root / 'linked').symlink_to(self.root, target_is_directory=True)
        self.records[1]['evidence'][0]['path'] = 'linked/evidence.md'
        self.assertFalse(self.report()['readyForMaintainerReview'])
        docs = self.root / 'docs'
        docs.rename(self.root / 'real-docs')
        docs.symlink_to(self.root / 'real-docs', target_is_directory=True)
        with self.assertRaises((OSError, ValueError)):
            reporter.build_report(self.root, self.sha)

    def test_fifo_and_hardlinks_reject_before_reading(self):
        os.mkfifo(self.root / 'pipe')
        os.link(self.root / 'evidence.md', self.root / 'hardlink.md')
        for name in ['pipe', 'hardlink.md']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                reporter.repository_file(self.root, name)

    def test_reference_and_cumulative_byte_budgets_are_enforced(self):
        self.records[1]['evidence'] *= 17
        with self.assertRaises(ValueError): self.report()
        with self.assertRaises(ValueError):
            reporter.repository_file(self.root, 'implementation.swift', total=[64 * 1024 * 1024])

    def test_duplicate_json_keys_and_record_budget_are_rejected(self):
        path = self.root / 'docs/ACCEPTANCE-EVIDENCE.json'
        path.write_text('{"schemaVersion":1,"schemaVersion":1,"records":[]}\n')
        with self.assertRaises(ValueError): reporter.build_report(self.root, self.sha)
        self.records *= 257
        with self.assertRaises(ValueError): self.report()

    def test_qualifying_ci_checkouts_preserve_real_evidence_ancestry(self):
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        def commit():
            subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                            '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                            '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                            'commit', '-qm', 'Synthetic evidence checkpoint'], check=True)
            return subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'], text=True).strip()
        evaluated = commit()
        for record in self.records:
            record['sourceSHA'] = evaluated
        self.ledger()
        current = commit()
        repository = Path(__file__).resolve().parents[2]
        import re
        settings = []
        for workflow in ['ci.yml', 'compatibility.yml']:
            text = (repository / '.github/workflows' / workflow).read_text()
            for block in re.split(r'(?m)^\s+- uses: actions/checkout@', text)[1:]:
                found = re.search(r'(?m)^\s+fetch-depth: (\d+)\s*$', block)
                settings.append((workflow, int(found.group(1)) if found else 1))
        self.assertEqual(len(settings), 4)  # Preflight, native CI and both compatibility candidates.
        with tempfile.TemporaryDirectory() as checkouts:
            def clone(name, depth):
                destination = Path(checkouts) / name
                args = ['git', 'clone', '-q']
                if depth:
                    args += ['--depth', str(depth)]
                subprocess.run(args + [self.root.as_uri(), str(destination)], check=True, timeout=10)
                return destination
            shallow = clone('missing-ancestor', 1)
            self.assertFalse(reporter.source_is_unchanged(shallow, evaluated, current))
            incomplete = reporter.build_report(shallow, current,
                source_matches=lambda sha: reporter.source_is_unchanged(shallow, sha, current))
            self.assertFalse(incomplete['readyForMaintainerReview'])
            for index, (workflow, depth) in enumerate(settings):
                with self.subTest(workflow=workflow, checkout=index):
                    checkout = clone('configured-' + str(index), depth)
                    self.assertTrue(reporter.source_is_unchanged(checkout, evaluated, current))
                    report = reporter.build_report(checkout, current,
                        source_matches=lambda sha: reporter.source_is_unchanged(checkout, sha, current))
                    self.assertTrue(report['readyForMaintainerReview'])
