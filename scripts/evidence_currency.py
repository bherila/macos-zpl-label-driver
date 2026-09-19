#!/usr/bin/env python3
"""Read-only acceptance-currency diagnostic. It reports; it never rewrites evidence.

The traceability report already computes whether each acceptance row has a current, digest-valid,
correctly levelled record. Nothing read that field on a push, so a record silently stopped vouching
for the tree the moment a source slice merged and the dip was invisible until someone looked.

This diagnostic turns that into an exit code. It never refreshes a digest, re-seals a record,
edits a checkbox or promotes a claim; every finding names a file a human has to change.

Exit codes:

  0  evaluated, no gating finding
  1  evaluated, at least one gating finding
  2  could not evaluate

There is no fourth outcome. Missing, unreadable or unbounded input is exit 2, never a quiet pass:
an unverifiable ledger is exactly the state in which a stale record would slip through. A recorded
source commit this repository does not hold is one of those states, and is never reported as
ordinary staleness. Gating findings are read from a row's records rather than from its single
summary verdict, which names one cause per row and would otherwise hide one defect behind another.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from traceability_report import (MANIFEST_PATH, OFFLINE_LEVELS, Deadline, build_report,
                                 manifest_entries, read_json, source_is_unchanged)

# A finding either fails the build or is recorded for a human. Nothing is dropped.
GATE, REPORT = 'gate', 'report'

EXIT_CLEAN, EXIT_FINDING, EXIT_CANNOT_EVALUATE = 0, 1, 2


class CannotEvaluate(Exception):
    """Raised for any input this diagnostic is unable to judge. Always exit 2."""


def _git(root: Path, *arguments: str, timeout: float = 10) -> str:
    try:
        return subprocess.check_output(['git', '-C', str(root), *arguments],
                                       text=True, timeout=timeout,
                                       stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise CannotEvaluate(f'git {" ".join(arguments)} failed: {type(exc).__name__}') from exc


def require_available_commit(root: Path, sha: str) -> None:
    """Raise CannotEvaluate unless `sha` names a commit this repository actually holds.

    `source_is_unchanged` answers one boolean, so a `merge-base --is-ancestor` that fails because
    the object is missing -- a shallow clone, a rewritten history, a ledger SHA that was never
    pushed, a corrupt object store -- is indistinguishable there from an honest "not an ancestor".
    Letting the first collapse into the second would file an operational failure as a report-only
    STALE-SOURCE and exit 0, against the promise that anything unevaluable exits 2. Ask git
    directly, before the answer is cached for every record bound to the same revision.
    """
    try:
        probe = subprocess.run(['git', '-C', str(root), 'cat-file', '-e', f'{sha}^{{commit}}'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.SubprocessError) as exc:
        raise CannotEvaluate(f'git cat-file for recorded source {sha[:12]} failed: '
                             f'{type(exc).__name__}') from exc
    if probe.returncode != 0:
        raise CannotEvaluate(f'recorded source commit {sha[:12]} is not a commit this repository '
                             f'holds; currency cannot be judged against absent history (a shallow '
                             f'clone, rewritten history or a SHA that was never pushed). This is '
                             f'not the same as a record that is merely stale')


def ledger_binding_findings(root: Path) -> list[dict]:
    """Records that cite nothing cannot bind anything, whatever their state says."""
    try:
        ledger = read_json(root / 'docs/ACCEPTANCE-EVIDENCE.json', root)
        records = ledger['records']
        if not isinstance(records, list):
            raise ValueError('records is not a list')
    # RecursionError is listed because it is what a size-bounded but deeply nested ledger raises
    # out of the JSON decoder. This read happens before the `build_report` wrapper below, so
    # without it the CLI printed a traceback and exited 1 -- a fourth outcome the contract denies.
    except (OSError, ValueError, KeyError, TypeError, RecursionError, UnicodeError) as exc:
        raise CannotEvaluate(f'unreadable acceptance ledger: {type(exc).__name__}: {exc}') from exc
    findings = []
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            raise CannotEvaluate(f'evidence record {index} is not an object')
        identifier = record.get('acceptanceID', f'record[{index}]')
        for field in ('implementation', 'evidence'):
            value = record.get(field)
            if not isinstance(value, list):
                raise CannotEvaluate(f'{identifier}: {field} is not a list')
            if not value:
                findings.append({'code': 'MISSING-BINDING', 'severity': GATE, 'id': identifier,
                                 'detail': f'record declares state {record.get("state")!r} with an '
                                           f'empty {field} list, so it binds no bytes'})
    return findings


def row_findings(report: dict, gate_stale: bool) -> list[dict]:
    """Every finding for every row.

    Gating defects are read off the passing records themselves, never off `verdict`. `verdict`
    deliberately names one cause per row -- the first unanswered question of the record that
    answers the most of them -- so a row holding a stale-but-valid record beside a current one
    with a wrong digest summarises as `stale-source` alone. That lossiness is right for a summary
    and wrong for a gate: the same design note that forbids the four dimension booleans from
    combining to qualify a row forbids the one-verdict summary from hiding a gating defect.
    The row-shaped codes below, none of which gates by default, still come from the verdict.
    """
    findings = []
    for row in report['acceptance']:
        status, identifier = row['evidenceStatus'], row['id']
        required = row['requiredEvidence']
        passing = [record for record in row['records'] if record['state'] == 'pass']
        if status['promotesBelowRequiredLevel']:
            offered = sorted({record['level'] for record in passing if record['level'] in OFFLINE_LEVELS})
            findings.append({'code': 'LEVEL-PROMOTION', 'severity': GATE, 'id': identifier,
                             'detail': f'requires {required} evidence but carries a passing '
                                       f'{"/".join(offered)} record; an offline or hosted-CI run '
                                       f'never promotes an {required} row'})
        if passing and not status['hasRequiredLevelRecord']:
            findings.append({'code': 'WRONG-EVIDENCE-LEVEL', 'severity': GATE, 'id': identifier,
                             'detail': f'requires {required}; no passing record is at that level'})
        invalid = [record for record in passing if not record['referencesValid']]
        if invalid:
            # Checked per record, so a second record that qualifies the row cannot bury it. The
            # ledger keeps one live record per acceptance ID -- a re-seal rewrites the record in
            # place rather than appending -- so a passing record whose cited bytes no longer match
            # is a defect, not superseded history.
            findings.append({'code': 'INVALID-REFERENCES', 'severity': GATE, 'id': identifier,
                             'detail': f'{len(invalid)} of {len(passing)} passing record(s) cite '
                                       f'bytes that no longer hash to the digest recorded, or cite '
                                       f'nothing at all; the ledger, not the tree, is wrong'})
        if row['hasCurrentDeclaredBlocker']:
            findings.append({'code': 'CURRENT-BLOCKER', 'severity': GATE, 'id': identifier,
                             'detail': 'a current record records fail or blocked, which vetoes '
                                       'readiness for this row'})
        if status['verdict'] == 'stale-source':
            findings.append({'code': 'STALE-SOURCE', 'severity': GATE if gate_stale else REPORT,
                             'id': identifier,
                             'detail': 'record is digest-valid and at the right level, but its '
                                       'evaluated source no longer describes HEAD; it needs a '
                                       're-seal slice against the merged result'})
        elif status['verdict'] == 'claimed-without-record':
            findings.append({'code': 'CLAIMED-WITHOUT-RECORD', 'severity': REPORT, 'id': identifier,
                             'detail': f'checkbox is checked and the ledger holds no record at all; '
                                       f'the {required} evidence this row prescribes is unrecorded'})
        elif status['verdict'] == 'no-passing-record':
            findings.append({'code': 'NO-PASSING-RECORD', 'severity': REPORT, 'id': identifier,
                             'detail': 'records exist but none declares pass'})
        elif status['verdict'] == 'record-without-checkbox':
            findings.append({'code': 'RECORD-WITHOUT-CHECKBOX', 'severity': REPORT, 'id': identifier,
                             'detail': 'a current, digest-valid, correctly levelled record exists '
                                       'while the milestone checkbox is unchecked'})
    return findings


def evaluate(root: Path, gate_stale: bool = False, budget: float | None = None) -> dict:
    """Return the report plus every finding, or raise CannotEvaluate. Reads only."""
    root = Path(root).resolve()
    deadline = Deadline() if budget is None else Deadline(budget)
    head = _git(root, 'rev-parse', 'HEAD')
    dirty = bool(_git(root, 'status', '--porcelain'))
    # The currency rule exempts a MANIFEST.sha256 refresh only while the manifest still describes the
    # tree. A manifest that cannot even be parsed makes that question unanswerable, so refuse here
    # rather than let the exemption be decided by a silent None deeper in.
    if not manifest_entries(root, head, deadline):
        raise CannotEvaluate(f'{MANIFEST_PATH} is absent, empty, malformed or unreadable at {head[:12]}; '
                             f'evidence currency cannot be judged against an unverifiable manifest')
    findings = ledger_binding_findings(root)
    matches: dict[str, bool] = {}

    def source_matches(evaluated: str, shared: Deadline) -> bool:
        if evaluated not in matches:
            if len(matches) >= 512:
                raise ValueError('Source revision budget exceeded')
            # Fail closed before caching. `source_is_unchanged` maps every failure it meets to
            # False, so the two cases it cannot tell apart are separated here instead.
            require_available_commit(root, evaluated)
            if shared.expired():
                raise CannotEvaluate(f'the report deadline expired before source currency for '
                                     f'{evaluated[:12]} could be judged')
            unchanged = source_is_unchanged(root, evaluated, head, shared)
            if not unchanged and shared.expired():
                raise CannotEvaluate(f'the report deadline expired while judging source currency '
                                     f'for {evaluated[:12]}; an unfinished comparison is not a '
                                     f'stale record')
            matches[evaluated] = unchanged
        return matches[evaluated]

    try:
        report = build_report(root, head, dirty, source_matches, deadline)
    except (ValueError, OSError, KeyError, TypeError, RecursionError, UnicodeError,
            subprocess.SubprocessError) as exc:
        raise CannotEvaluate(f'traceability report refused this input: {type(exc).__name__}: {exc}') from exc
    if _git(root, 'rev-parse', 'HEAD') != head or bool(_git(root, 'status', '--porcelain')) != dirty:
        raise CannotEvaluate('workspace changed while the diagnostic was running')
    if dirty:
        findings.append({'code': 'WORKSPACE-DIRTY', 'severity': REPORT, 'id': '-',
                         'detail': 'uncommitted changes are present, so no record can be current; '
                                   'the currency verdicts below describe the working tree'})
    findings.extend(row_findings(report, gate_stale))
    return {'sourceSHA': head, 'workspaceDirty': dirty, 'gateStale': gate_stale,
            'report': report, 'findings': findings,
            'gating': [item for item in findings if item['severity'] == GATE]}


def render(result: dict) -> str:
    report = result['report']
    lines = [f'Acceptance evidence currency at {result["sourceSHA"]}'
             f'{" (DIRTY WORKTREE)" if result["workspaceDirty"] else ""}', '']
    lines.append('  (a) checkbox  (b) digest-valid  (c) current source  (d) required level')
    lines.append(f'  {"ID":<9} {"need":<4}  a  b  c  d   verdict')
    def mark(value):
        return ' x ' if value else ' . '
    for row in report['acceptance']:
        status = row['evidenceStatus']
        if not row['records'] and not status['checkboxComplete']:
            continue
        lines.append(f'  {row["id"]:<9} {row["requiredEvidence"]:<4} '
                     + mark(status['checkboxComplete']) + mark(status['hasDigestValidRecord'])
                     + mark(status['hasCurrentSourceRecord']) + mark(status['hasRequiredLevelRecord'])
                     + '  ' + status['verdict'])
    counts, total = report['evidenceCounts'], len(report['acceptance'])
    lines += ['', f'Four separate counts over all {total} rows -- not one number:',
              f'  (a) checkbox checked in a milestone ACCEPTANCE.md ........ {counts["checkboxComplete"]:>4}',
              f'  (b) a passing record whose cited bytes still match ....... {counts["hasDigestValidRecord"]:>4}',
              f'  (c) a passing record whose source still describes HEAD ... {counts["hasCurrentSourceRecord"]:>4}',
              f'  (d) a passing record at the prescribed A/C/I/H/R level ... {counts["hasRequiredLevelRecord"]:>4}',
              f'  of which: checked with NO record at all .................. {counts["checkedWithNoRecord"]:>4}',
              f'  QUALIFIED (one single record answering all four) ......... {counts["qualified"]:>4}',
              '',
              'A reader who trusts the checkboxes sees (a). Only the last line is qualified.',
              '"Checked with no record" is its own category: not a stale record, none.',
              '', f'All {total} rows by verdict:']
    for name, count in report['evidenceSummary'].items():
        if count:
            lines.append(f'  {count:>4}  {name}')
    lines.append('')
    if result['findings']:
        lines.append('Findings:')
        for item in result['findings']:
            lines.append(f'  [{item["severity"]}] {item["code"]} {item["id"]}: {item["detail"]}')
    else:
        lines.append('No findings.')
    lines += ['', 'This diagnostic reads. It never refreshes a digest, re-seals a record, edits a',
              'checkbox or promotes a claim, and it qualifies no macOS, GUI, hardware or release row.']
    return '\n'.join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--format', choices=['text', 'json'], default='text')
    parser.add_argument('--gate-stale', action='store_true',
                        help='also fail on a stale-source record. Off by default because a source '
                             'slice necessarily makes every record stale until its evidence slice '
                             'lands, so gating it here would fail the very PR that is doing the work.')
    parser.add_argument('--budget', type=float, default=None,
                        help='wall-clock seconds for the whole evaluation (default 60)')
    arguments = parser.parse_args()
    try:
        result = evaluate(arguments.root, arguments.gate_stale, arguments.budget)
    except CannotEvaluate as exc:
        print(f'CANNOT-EVALUATE: {exc}', file=sys.stderr)
        print('No currency verdict was produced; this is a failure, not a skip.', file=sys.stderr)
        return EXIT_CANNOT_EVALUATE
    if arguments.format == 'json':
        print(json.dumps(result, indent=2))
    else:
        print(render(result))
    if result['gating']:
        print(f'{len(result["gating"])} gating finding(s).', file=sys.stderr)
        return EXIT_FINDING
    return EXIT_CLEAN


if __name__ == '__main__':
    raise SystemExit(main())
