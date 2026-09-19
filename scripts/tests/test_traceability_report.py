import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import time
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
            source_matches=lambda sha, deadline: reporter.source_is_unchanged(self.root, sha, evidence_commit, deadline))
        self.assertTrue(report['readyForMaintainerReview'])
        (self.root / 'implementation.swift').write_text('changed build input\n')
        changed_commit = commit()
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, changed_commit))
        self.assertFalse(reporter.source_is_unchanged(self.root, changed_commit, evaluated))

    def test_manifest_exemption_requires_a_manifest_that_still_describes_the_tree(self):
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        def commit():
            subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
            subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                            '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                            'commit', '-qm', 'Synthetic test checkpoint'], check=True)
            return subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'], text=True).strip()
        def write_manifest(*names):
            lines = []
            for name in names:
                body = (self.root / name).read_bytes()
                lines.append(f'{hashlib.sha256(body).hexdigest()}  {name}')
            (self.root / 'MANIFEST.sha256').write_text('\n'.join(lines) + '\n')
        write_manifest('implementation.swift')
        evaluated = commit()
        self.records[0]['sourceSHA'] = evaluated
        self.records[1]['sourceSHA'] = evaluated
        self.ledger()

        # A truthful refresh is bookkeeping: recording evidence must rewrite this file, so it
        # cannot be the thing that invalidates the records it describes.
        self.records[0]['state'] = 'pass'
        self.ledger()
        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json')
        refreshed = commit()
        self.assertTrue(reporter.source_is_unchanged(self.root, evaluated, refreshed))
        report = reporter.build_report(self.root, refreshed,
            source_matches=lambda sha, deadline: reporter.source_is_unchanged(self.root, sha, refreshed, deadline))
        self.assertTrue(report['readyForMaintainerReview'])

        # A wrong digest is corrupted integrity metadata, not bookkeeping, even though it is the
        # only changed path. It must not silently keep older evidence current.
        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json')
        (self.root / 'MANIFEST.sha256').write_text(
            '1' * 64 + '  implementation.swift\n'
            + (self.root / 'MANIFEST.sha256').read_text().splitlines()[1] + '\n')
        corrupted = commit()
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, corrupted))
        self.assertFalse(reporter.build_report(self.root, corrupted,
            source_matches=lambda sha, deadline: reporter.source_is_unchanged(self.root, sha, corrupted, deadline)
        )['readyForMaintainerReview'])

        # Dropping an entry shrinks integrity coverage. The remaining entries still verify, so this
        # is only caught by comparing the path set against the evaluated manifest.
        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json')
        subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
        (self.root / 'MANIFEST.sha256').write_text(
            '\n'.join((self.root / 'MANIFEST.sha256').read_text().splitlines()[1:]) + '\n')
        dropped = commit()
        self.assertFalse(reporter.manifest_describes_tree(self.root, dropped, evaluated))
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, dropped))

        # Widening coverage is a legitimate refresh and stays exempt.
        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json', 'evidence.md')
        widened = commit()
        self.assertTrue(reporter.source_is_unchanged(self.root, evaluated, widened))

        # A repeated path could request one blob many times, so it is rejected outright.
        body = (self.root / 'implementation.swift').read_bytes()
        line = f'{hashlib.sha256(body).hexdigest()}  implementation.swift'
        (self.root / 'MANIFEST.sha256').write_text(line + '\n' + line + '\n')
        duplicated = commit()
        self.assertIsNone(reporter.manifest_entries(self.root, duplicated))
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, duplicated))

        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json')
        commit()

        # An entry naming a path that does not exist at that commit is equally untrustworthy.
        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json')
        (self.root / 'MANIFEST.sha256').write_text(
            (self.root / 'MANIFEST.sha256').read_text() + '0' * 64 + '  absent.swift\n')
        missing = commit()
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, missing))

        # A real source change is still caught even when the manifest truthfully moves with it.
        (self.root / 'implementation.swift').write_text('changed build input\n')
        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json')
        changed_commit = commit()
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, changed_commit))

    def status(self, identifier, report=None):
        report = self.report() if report is None else report
        return next(row['evidenceStatus'] for row in report['acceptance'] if row['id'] == identifier)

    def test_evidence_status_separates_the_four_questions_a_row_conflates(self):
        # (a) checkbox, (b) digest-valid record, (c) current source, (d) prescribed level. A row that
        # answers only (a) and (b) must be visibly distinguishable from a qualified one.
        qualified = self.status('M3-AC01')
        self.assertEqual({'checkboxComplete': True, 'hasDigestValidRecord': True,
                          'hasCurrentSourceRecord': True, 'hasRequiredLevelRecord': True,
                          'promotesBelowRequiredLevel': False, 'qualified': True,
                          'verdict': 'qualified'}, qualified)

        # (c) alone fails: the record is still digest-valid and still at the right level.
        self.records[0]['sourceSHA'] = 'b' * 40
        stale = self.status('M3-AC01')
        self.assertEqual('stale-source', stale['verdict'])
        self.assertTrue(stale['checkboxComplete'] and stale['hasDigestValidRecord']
                        and stale['hasRequiredLevelRecord'])
        self.assertFalse(stale['hasCurrentSourceRecord'] or stale['qualified'])
        self.records[0]['sourceSHA'] = self.sha

        # (b) alone fails: current and correctly levelled, but the cited bytes moved.
        (self.root / 'evidence.md').write_text('changed synthetic assessment\n')
        invalid = self.status('M3-AC01')
        self.assertEqual('invalid-references', invalid['verdict'])
        self.assertTrue(invalid['hasCurrentSourceRecord'] and invalid['hasRequiredLevelRecord'])
        self.assertFalse(invalid['hasDigestValidRecord'] or invalid['qualified'])
        (self.root / 'evidence.md').write_text('synthetic declared assessment\n')
        self.records[0] = self.record('M3-AC01', 'A')

        # (d) alone fails, and an A record offered against an H row is flagged as a promotion.
        self.records[1] = self.record('M3-AC02', 'A')
        promoted = self.status('M3-AC02')
        self.assertEqual('wrong-evidence-level', promoted['verdict'])
        self.assertTrue(promoted['hasDigestValidRecord'] and promoted['hasCurrentSourceRecord'])
        self.assertTrue(promoted['promotesBelowRequiredLevel'])
        self.assertFalse(promoted['hasRequiredLevelRecord'] or promoted['qualified'])
        self.records[1] = self.record('M3-AC02', 'H')

        # (a) alone fails: a fully bound record whose checkbox is unchecked is not silently qualified.
        table = self.root / 'docs/milestones/synthetic/ACCEPTANCE.md'
        table.write_text(table.read_text().replace('[x] | M3-AC02', '[ ] | M3-AC02'))
        unchecked = self.status('M3-AC02')
        self.assertEqual('record-without-checkbox', unchecked['verdict'])
        self.assertFalse(unchecked['checkboxComplete'] or unchecked['qualified'])
        table.write_text(table.read_text().replace('[ ] | M3-AC02', '[x] | M3-AC02'))

    def test_a_checked_row_with_no_record_is_distinct_from_an_unclaimed_one(self):
        self.records = []
        self.assertEqual('claimed-without-record', self.status('M3-AC01')['verdict'])
        table = self.root / 'docs/milestones/synthetic/ACCEPTANCE.md'
        table.write_text(table.read_text().replace('[x] | M3-AC01', '[ ] | M3-AC01'))
        self.assertEqual('no-record', self.status('M3-AC01')['verdict'])

    def test_a_row_whose_only_records_are_not_pass_is_its_own_verdict(self):
        self.records[0]['state'] = 'not-run'
        self.assertEqual('no-passing-record', self.status('M3-AC01')['verdict'])
        self.records[0]['state'] = 'blocked'
        self.assertEqual('current-blocker', self.status('M3-AC01')['verdict'])

    def test_the_four_dimension_counts_are_reported_as_four_separate_figures(self):
        # Measured on main at c3bbc5c after #111 merged: 13 checked, 2 digest-valid, 0 current,
        # 0 qualified, and 11 of the 13 with no record at all. One number cannot say that.
        self.records = []
        counts = self.report()['evidenceCounts']
        self.assertEqual({'checkboxComplete': 2, 'hasDigestValidRecord': 0,
                          'hasCurrentSourceRecord': 0, 'hasRequiredLevelRecord': 0,
                          'checkedWithNoRecord': 2, 'qualified': 0}, counts)

        # A stale record moves (b) and (d) without moving (c) or `qualified`, and stops counting
        # towards `checkedWithNoRecord`, which is a distinct category from a stale record.
        self.records = [self.record('M3-AC01', 'A'), self.record('M3-AC02', 'H')]
        self.records[0]['sourceSHA'] = 'b' * 40
        counts = self.report()['evidenceCounts']
        self.assertEqual(2, counts['hasDigestValidRecord'])
        self.assertEqual(1, counts['hasCurrentSourceRecord'])
        self.assertEqual(2, counts['hasRequiredLevelRecord'])
        self.assertEqual(0, counts['checkedWithNoRecord'])
        self.assertEqual(1, counts['qualified'])

    def test_the_summary_counts_every_row_exactly_once(self):
        report = self.report()
        self.assertEqual(len(report['acceptance']), sum(report['evidenceSummary'].values()))
        self.assertEqual(2, report['evidenceSummary']['qualified'])
        self.assertEqual(set(reporter.VERDICTS), set(report['evidenceSummary']))

    def test_dimension_booleans_never_qualify_a_row_by_themselves(self):
        # Three separate records could each answer one question. `qualified` still requires one
        # single record to answer all four, which is the conflation this guards against.
        stale = self.record('M3-AC01', 'A')
        stale['sourceSHA'] = 'b' * 40
        wrong_level = self.record('M3-AC01', 'C')
        self.records = [stale, wrong_level, self.record('M3-AC02', 'H')]
        status = self.status('M3-AC01')
        self.assertTrue(status['hasDigestValidRecord'])
        self.assertTrue(status['hasCurrentSourceRecord'])   # answered by the C record
        self.assertTrue(status['hasRequiredLevelRecord'])   # answered by the stale A record
        self.assertFalse(status['qualified'])
        self.assertEqual('stale-source', status['verdict'])

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
                source_matches=lambda sha, deadline: reporter.source_is_unchanged(shallow, sha, current, deadline))
            self.assertFalse(incomplete['readyForMaintainerReview'])
            for index, (workflow, depth) in enumerate(settings):
                with self.subTest(workflow=workflow, checkout=index):
                    checkout = clone('configured-' + str(index), depth)
                    self.assertTrue(reporter.source_is_unchanged(checkout, evaluated, current))
                    report = reporter.build_report(checkout, current,
                        source_matches=lambda sha, deadline: reporter.source_is_unchanged(checkout, sha, current, deadline))
                    self.assertTrue(report['readyForMaintainerReview'])

    def test_manifest_verification_is_bounded_by_the_shared_report_budget(self):
        # A valid manifest may hold MAXIMUM_MANIFEST_ENTRIES entries, and each evidence record bound
        # to a distinct ancestor walks its own. Independent per-entry timeouts bounded that only at
        # entries x revisions x 30s, so a manifest-only change could time out CI instead of
        # producing the bounded rejection the exemption is supposed to fail closed with.
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        def commit():
            subprocess.run(['git', '-C', str(self.root), 'add', '-A'], check=True)
            subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                            '-c', 'user.email=agent@example.test', '-c', 'commit.gpgsign=false',
                            '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                            'commit', '-qm', 'Synthetic test checkpoint'], check=True)
            return subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'], text=True).strip()
        def write_manifest(*names):
            lines = [f'{hashlib.sha256((self.root / name).read_bytes()).hexdigest()}  {name}' for name in names]
            (self.root / 'MANIFEST.sha256').write_text('\n'.join(lines) + '\n')
        write_manifest('implementation.swift')
        evaluated = commit()
        self.records[0]['sourceSHA'] = evaluated
        self.records[1]['sourceSHA'] = evaluated
        self.ledger()
        write_manifest('implementation.swift', 'docs/ACCEPTANCE-EVIDENCE.json')
        refreshed = commit()

        # The same tree and manifest that verify under a live budget...
        self.assertTrue(reporter.manifest_describes_tree(self.root, refreshed, evaluated, reporter.Deadline()))
        self.assertTrue(reporter.source_is_unchanged(self.root, evaluated, refreshed, reporter.Deadline()))

        # ...fail closed once the shared budget is spent, rather than hashing on past it.
        spent = reporter.Deadline(seconds=0)
        self.assertTrue(spent.expired())
        started = time.monotonic()
        self.assertFalse(reporter.manifest_describes_tree(self.root, refreshed, evaluated, spent))
        self.assertFalse(reporter.source_is_unchanged(self.root, evaluated, refreshed, spent))
        self.assertLess(time.monotonic() - started, 10)
        self.assertIsNone(reporter.manifest_entries(self.root, refreshed, spent))

        # The per-entry hash loop is the specific thing this bounds, so prove it there rather than
        # only at the cheaper checks that precede it. This manifest needs five budget draws: one
        # per manifest_entries call, one for the batch-check, then one per hashed entry.
        class BudgetSpentAfter(reporter.Deadline):
            """Grants a real budget for the first `draws` requests, then reports it spent."""
            def __init__(self, draws):
                super().__init__()
                self.draws, self.taken = draws, 0
            def timeout(self, ceiling):
                if self.taken >= self.draws:
                    return None
                self.taken += 1
                return super().timeout(ceiling)
            def expired(self):
                return self.taken >= self.draws

        enough = BudgetSpentAfter(5)
        self.assertTrue(reporter.manifest_describes_tree(self.root, refreshed, evaluated, enough))
        self.assertEqual(5, enough.taken)
        # One draw short is one entry left unhashed, which must deny the exemption, not assume it.
        self.assertFalse(reporter.manifest_describes_tree(self.root, refreshed, evaluated, BudgetSpentAfter(4)))

    def test_per_entry_timeouts_never_exceed_what_is_left_of_the_report(self):
        # The ceiling is the per-call cap; the budget is what is actually left. The smaller wins, so
        # no single subprocess can outlive the report that started it.
        self.assertLessEqual(reporter.Deadline(seconds=2).timeout(30), 2)
        self.assertLessEqual(reporter.Deadline(seconds=90).timeout(30), 30)
        self.assertIsNone(reporter.Deadline(seconds=0).timeout(30))
        self.assertIsNone(reporter.Deadline(seconds=-5).timeout(30))

    def test_report_budget_covers_time_spent_inside_source_matches(self):
        # check_budget() previously measured only the gaps between its own calls. A source_matches
        # that consumed the whole budget internally was not itself the thing that tripped it.
        observed = []
        def source_matches(evaluated, deadline):
            observed.append(deadline)
            return True
        shared = reporter.Deadline(seconds=60)
        self.records[0]['sourceSHA'] = 'b' * 40
        self.ledger()
        reporter.build_report(self.root, self.sha, source_matches=source_matches, deadline=shared)
        self.assertTrue(observed, 'source_matches was never consulted')
        for supplied in observed:
            self.assertIs(shared, supplied)

        spent = reporter.Deadline(seconds=0)
        with self.assertRaises(ValueError):
            reporter.build_report(self.root, self.sha, source_matches=source_matches, deadline=spent)
