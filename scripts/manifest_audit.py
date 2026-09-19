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

A manifest is untrusted input on a fork's pull request, so an entry is a path *claim*, not a path
to open. A name that is absolute, carries `..` or `.` components, or holds a backslash or NUL is
refused while parsing, before any filesystem call; every component of an accepted name is opened
`O_NOFOLLOW` relative to the previous descriptor, so no symlink inside the tree can redirect a
read outside it; and no file is read past its cap, which bounds the read rather than being checked
against `st_size` afterwards.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import re
import stat
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


def repository_relative(name: str) -> bool:
    """True only for a path that can name a file inside the repository.

    A manifest is untrusted input on a fork's pull request, and `root / name` resolves an absolute
    entry or one carrying `..` to somewhere else on the runner. The shape of the path is therefore
    judged before any filesystem call, not after the bytes have been read.
    """
    if not name or '\0' in name or '\\' in name:
        return False
    return all(part and part not in ('.', '..') for part in name.split('/'))


def read_repository_file(root: Path, name: str) -> tuple[str, int, bytes]:
    """Read at most `MAXIMUM_FILE_BYTES + 1` bytes of `name` under `root`, following no symlink.

    Returns ('absent', 0, b'') when no regular file is reachable at that path, ('oversized', n,
    b'') when it is larger than the cap -- the one extra byte is what proves it, so nothing larger
    is ever buffered -- and ('read', n, body) otherwise. A cap checked after the read is not a cap,
    and `st_size` is only a hint: a growing file or a procfs entry does not honour it.

    Every component is opened `O_NOFOLLOW` relative to the previous descriptor, so neither a
    traversing entry nor a symlinked directory inside the tree can redirect the read outside it.
    """
    if not repository_relative(name):
        raise CannotMeasure(f'refusing to open {name!r}: not a repository-relative path')
    parts = name.split('/')
    try:
        parent = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as exc:
        raise CannotMeasure(f'cannot open the repository root: {exc}') from exc
    descriptor = None
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    except OSError:
        return 'absent', 0, b''  # missing, a symlink, or a component that is not a directory
    finally:
        os.close(parent)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return 'absent', 0, b''
        body = bytearray()
        while len(body) <= MAXIMUM_FILE_BYTES:
            chunk = os.read(descriptor, min(65536, MAXIMUM_FILE_BYTES - len(body) + 1))
            if not chunk:
                break
            body.extend(chunk)
        if len(body) > MAXIMUM_FILE_BYTES:
            return 'oversized', len(body), b''
        return 'read', len(body), bytes(body)
    except OSError as exc:
        raise CannotMeasure(f'cannot read {name}: {exc}') from exc
    finally:
        os.close(descriptor)


def parse_manifest(root: Path) -> dict[str, str]:
    status, _, raw = read_repository_file(root, MANIFEST_PATH)
    if status == 'absent':
        raise CannotMeasure(f'cannot read {MANIFEST_PATH}: no regular file at that path')
    if status == 'oversized':
        raise CannotMeasure(f'{MANIFEST_PATH} exceeds {MAXIMUM_FILE_BYTES} bytes; it was refused '
                            f'at the cap rather than buffered')
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
        if not repository_relative(name):
            raise CannotMeasure(f'{MANIFEST_PATH}:{number} names {name!r}, which is not a '
                                f'repository-relative path; a manifest that points outside the '
                                f'tree is corrupt integrity metadata, not a measurable state')
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
        if not repository_relative(name):  # parse_manifest refuses these; never reach the disk
            raise CannotMeasure(f'refusing to inspect {name!r}: not a repository-relative path')
        status, size, body = read_repository_file(root, name)
        # Bytes actually read are counted whatever the outcome, so the cumulative cost is bounded
        # by the budget plus at most one capped file rather than by the number of entries.
        total += size
        if total > MAXIMUM_TOTAL_BYTES:
            raise CannotMeasure('manifest-covered bytes exceed the read budget')
        if status == 'absent':
            absent.append(name)
            continue
        if status == 'oversized':
            oversized.append(name)
            continue
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
