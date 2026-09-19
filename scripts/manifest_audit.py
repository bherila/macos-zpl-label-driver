#!/usr/bin/env python3
"""Read-only measurement of what `MANIFEST.sha256` actually covers. Issue #87 measurement tooling.

The manifest is now load-bearing: `source_is_unchanged` exempts a manifest-only commit from
invalidating acceptance evidence, but only while the manifest still describes the tree and has not
shrunk its coverage. Nothing measured what that coverage is, so "the manifest verifies" and "the
manifest verifies the files you care about" were indistinguishable.

This tool measures and reports. It never writes the manifest, adds an entry or refreshes a digest;
whether the manifest should cover the whole tree is a maintainer decision recorded in
docs/adr/0004-manifest-integrity-scope.md, not something to settle by bulk-adding entries.

Exit codes:

  0  measured, nothing gating
  1  measured, gating finding (only reachable with --enforce-covered / --enforce-coverage)
  2  could not measure

Unreadable, malformed or unbounded input is exit 2, never a quiet pass.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

MANIFEST_PATH = 'MANIFEST.sha256'
DIGEST = re.compile(r'[0-9a-f]{64}\Z')
MAXIMUM_FILE_BYTES = 2 * 1024 * 1024
MAXIMUM_ENTRIES = 4096
MAXIMUM_TOTAL_BYTES = 64 * 1024 * 1024

EXIT_CLEAN, EXIT_FINDING, EXIT_CANNOT_MEASURE = 0, 1, 2


class CannotMeasure(Exception):
    """Raised for input this tool cannot judge. Always exit 2."""


def tracked_files(root: Path) -> list[str]:
    try:
        raw = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z'],
                                      timeout=30, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as exc:
        raise CannotMeasure(f'git ls-files failed: {type(exc).__name__}') from exc
    try:
        return sorted(name for name in raw.decode('utf-8').split('\0') if name)
    except UnicodeError as exc:
        raise CannotMeasure('git ls-files produced non-UTF-8 paths') from exc


def parse_manifest(root: Path) -> dict[str, str]:
    path = root / MANIFEST_PATH
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise CannotMeasure(f'cannot read {MANIFEST_PATH}: {exc}') from exc
    if len(raw) > MAXIMUM_FILE_BYTES:
        raise CannotMeasure(f'{MANIFEST_PATH} exceeds {MAXIMUM_FILE_BYTES} bytes')
    try:
        text = raw.decode('utf-8')
    except UnicodeError as exc:
        raise CannotMeasure(f'{MANIFEST_PATH} is not UTF-8') from exc
    entries: dict[str, str] = {}
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        digest, separator, name = line.partition('  ')
        if not separator or not DIGEST.fullmatch(digest) or not name or '\0' in name:
            raise CannotMeasure(f'{MANIFEST_PATH}:{number} is not "<sha256>  <path>"')
        if name in entries:
            raise CannotMeasure(f'{MANIFEST_PATH}:{number} repeats path {name}')
        entries[name] = digest
        if len(entries) > MAXIMUM_ENTRIES:
            raise CannotMeasure(f'{MANIFEST_PATH} exceeds {MAXIMUM_ENTRIES} entries')
    if not entries:
        raise CannotMeasure(f'{MANIFEST_PATH} holds no entries')
    return entries


def area(name: str) -> str:
    parts = name.split('/')
    if name.startswith('Packages/'):
        return '/'.join(parts[:2]) + (' (swift)' if name.endswith('.swift') else ' (other)')
    for prefix in ('docs/validation', 'docs/milestones', 'scripts/tests', 'Fixtures', '.github'):
        if name.startswith(prefix):
            return prefix
    if len(parts) > 1:
        return parts[0]
    return '<root>'


def audit(root: Path, enforce_covered: bool = False, enforce_coverage: bool = False) -> dict:
    root = Path(root).resolve()
    tracked = tracked_files(root)
    entries = parse_manifest(root)
    tracked_set = set(tracked)
    findings: list[dict] = []
    stale, absent, untracked, oversized = [], [], [], []
    total = 0
    for name in sorted(entries):
        if name not in tracked_set:
            untracked.append(name)
        target = root / name
        if target.is_symlink() or not target.is_file():
            absent.append(name)
            continue
        size = target.stat().st_size
        if size > MAXIMUM_FILE_BYTES:
            oversized.append(name)
            continue
        total += size
        if total > MAXIMUM_TOTAL_BYTES:
            raise CannotMeasure('manifest-covered bytes exceed the read budget')
        try:
            body = target.read_bytes()
        except OSError as exc:
            raise CannotMeasure(f'cannot read covered file {name}: {exc}') from exc
        if hashlib.sha256(body).hexdigest() != entries[name]:
            stale.append(name)
    # MANIFEST.sha256 never lists itself; that is the one intended omission, not drift.
    omitted = sorted(tracked_set - set(entries) - {MANIFEST_PATH})
    severity_covered = 'gate' if enforce_covered else 'report'
    for name in stale:
        findings.append({'code': 'STALE-DIGEST', 'severity': severity_covered, 'path': name,
                         'detail': 'covered file no longer hashes to its recorded digest'})
    for name in absent:
        findings.append({'code': 'ABSENT-PATH', 'severity': severity_covered, 'path': name,
                         'detail': 'entry names a path that is not a regular file here'})
    for name in untracked:
        findings.append({'code': 'UNTRACKED-ENTRY', 'severity': severity_covered, 'path': name,
                         'detail': 'entry names a path git does not track'})
    for name in oversized:
        findings.append({'code': 'OVERSIZED-ENTRY', 'severity': severity_covered, 'path': name,
                         'detail': f'covered file exceeds the {MAXIMUM_FILE_BYTES}-byte read budget '
                                   f'and was not hashed'})
    if omitted:
        findings.append({'code': 'UNCOVERED-PATHS',
                         'severity': 'gate' if enforce_coverage else 'report', 'path': '-',
                         'detail': f'{len(omitted)} tracked files carry no digest; the manifest '
                                   f'says nothing about them'})
    return {'trackedFiles': len(tracked), 'manifestEntries': len(entries),
            'coveredTrackedFiles': len(set(entries) & tracked_set),
            'omittedTrackedFiles': len(omitted),
            'staleDigests': stale, 'absentPaths': absent, 'untrackedEntries': untracked,
            'oversizedEntries': oversized, 'omittedPaths': omitted,
            'coveredByArea': dict(sorted(collections.Counter(area(n) for n in entries).items())),
            'omittedByArea': dict(sorted(collections.Counter(area(n) for n in omitted).items())),
            'findings': findings,
            'gating': [item for item in findings if item['severity'] == 'gate']}


def render(result: dict) -> str:
    lines = [f'MANIFEST.sha256 coverage: {result["coveredTrackedFiles"]} of '
             f'{result["trackedFiles"]} tracked files '
             f'({result["manifestEntries"]} entries, {result["omittedTrackedFiles"]} omitted)', '']
    lines.append(f'  {"area":<32} covered  omitted')
    for name in sorted(set(result['coveredByArea']) | set(result['omittedByArea'])):
        lines.append(f'  {name:<32} {result["coveredByArea"].get(name, 0):>7}  '
                     f'{result["omittedByArea"].get(name, 0):>7}')
    lines += ['', f'  stale digests: {len(result["staleDigests"])}',
              f'  absent paths: {len(result["absentPaths"])}',
              f'  untracked entries: {len(result["untrackedEntries"])}',
              f'  oversized entries: {len(result["oversizedEntries"])}', '']
    if result['findings']:
        lines.append('Findings:')
        for item in result['findings']:
            lines.append(f'  [{item["severity"]}] {item["code"]} {item["path"]}: {item["detail"]}')
    else:
        lines.append('No findings.')
    lines += ['', 'Measurement only. This tool writes nothing; manifest scope is a maintainer',
              'decision recorded in docs/adr/0004-manifest-integrity-scope.md.']
    return '\n'.join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--format', choices=['text', 'json'], default='text')
    parser.add_argument('--enforce-covered', action='store_true',
                        help='fail when an entry the manifest already claims has drifted. Off by '
                             'default until the scope decision in ADR 0004 is made, because turning '
                             'it on requires every PR touching a covered file to refresh the manifest.')
    parser.add_argument('--enforce-coverage', action='store_true',
                        help='fail while any tracked file carries no digest. Only meaningful under '
                             'the whole-tree policy of ADR 0004 option 1.')
    arguments = parser.parse_args()
    try:
        result = audit(arguments.root, arguments.enforce_covered, arguments.enforce_coverage)
    except CannotMeasure as exc:
        print(f'CANNOT-MEASURE: {exc}', file=sys.stderr)
        print('No coverage measurement was produced; this is a failure, not a skip.', file=sys.stderr)
        return EXIT_CANNOT_MEASURE
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
