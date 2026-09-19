#!/usr/bin/env python3
"""Read-only acceptance traceability. Declared evidence is not independent proof."""
import argparse
import hashlib
import json
import os
import stat
from pathlib import Path
import re
import subprocess
import time

LEVELS = {'A', 'C', 'I', 'H', 'R'}
STATES = {'not-run', 'pass', 'fail', 'blocked', 'not-applicable'}
# Levels an offline suite, a hosted compile or an inert check can actually reach. A criterion that
# prescribes I, H or R is never satisfied by one of these, however green the run was.
OFFLINE_LEVELS = {'A', 'C'}
# One row, four independent questions. They are reported separately because a row can answer some
# and not others, and a row that answers only the first two is not qualified.
VERDICTS = ('qualified', 'stale-source', 'invalid-references', 'wrong-evidence-level',
            'claimed-without-record', 'record-without-checkbox', 'no-passing-record',
            'current-blocker', 'no-record')
SHA = re.compile(r'[0-9a-f]{40}\Z')
DIGEST = re.compile(r'[0-9a-f]{64}\Z')
MAXIMUM_FILE_BYTES = 2 * 1024 * 1024
MANIFEST_PATH = 'MANIFEST.sha256'
MAXIMUM_MANIFEST_ENTRIES = 4096
MAXIMUM_MANIFEST_BYTES = 64 * 1024 * 1024
REPORT_BUDGET_SECONDS = 60


class Deadline:
    """One wall-clock budget shared by every step of a single report.

    Manifest verification is bounded by this rather than by independent per-subprocess timeouts. A
    valid manifest may carry MAXIMUM_MANIFEST_ENTRIES entries, and several evidence records bound to
    distinct ancestor revisions each walk their own manifest, so per-entry timeouts bound the work
    only at entries x revisions x timeout -- far past the budget they run inside. Exhausting the
    budget fails closed: an unverified manifest never keeps an evidence record current.
    """

    def __init__(self, seconds=REPORT_BUDGET_SECONDS):
        self.expires = time.monotonic() + max(0.0, float(seconds))

    def remaining(self):
        return self.expires - time.monotonic()

    def expired(self):
        return self.remaining() <= 0

    def timeout(self, ceiling):
        """The remaining budget capped by this call's own ceiling, or None once it is spent."""
        left = self.remaining()
        return min(ceiling, left) if left > 0 else None


def repository_file(root, relative, cache=None, total=None):
    relative = Path(relative)
    if relative.is_absolute() or '..' in relative.parts or not relative.parts:
        raise ValueError('Invalid repository reference')
    parent = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    descriptor = None
    try:
        for part in relative.parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
        descriptor = os.open(relative.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > MAXIMUM_FILE_BYTES:
            raise ValueError('Unsafe or oversized repository file')
        fingerprint = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
        key = str(relative)
        if cache is not None and key in cache:
            previous, digest = cache[key]
            if fingerprint != previous:
                raise ValueError('Reference changed during report')
            return None, digest
        if total is not None:
            total[0] += before.st_size
            if total[0] > 64 * 1024 * 1024:
                raise ValueError('Reference byte budget exceeded')
        data = bytearray()
        while len(data) <= MAXIMUM_FILE_BYTES:
            chunk = os.read(descriptor, min(65536, MAXIMUM_FILE_BYTES - len(data) + 1))
            if not chunk:
                break
            data.extend(chunk)
        after = os.fstat(descriptor)
        if (len(data) > MAXIMUM_FILE_BYTES or len(data) != before.st_size
                or fingerprint != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)):
            raise ValueError('Reference changed or exceeded budget')
        digest = hashlib.sha256(data).hexdigest()
        if cache is not None:
            cache[key] = (fingerprint, digest)
        return bytes(data), digest
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(parent)


def read_json(path, root=None):
    root = path.parent if root is None else root
    raw, _ = repository_file(root, path.relative_to(root))
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique)


def validate_reference(root, reference, cache=None, total=None):
    if not isinstance(reference, dict) or set(reference) != {'path', 'sha256'}:
        return False
    name, digest = reference['path'], reference['sha256']
    if not isinstance(name, str) or not isinstance(digest, str) or not DIGEST.fullmatch(digest):
        return False
    if Path(name).is_absolute() or '..' in Path(name).parts or not Path(name).parts:
        return False
    try:
        _, actual = repository_file(root, name, cache, total)
    except OSError:
        return False
    return actual == digest


def source_is_unchanged(root, evaluated_sha, current_sha, deadline=None):
    if deadline is None:
        deadline = Deadline()
    if not SHA.fullmatch(evaluated_sha) or not SHA.fullmatch(current_sha):
        return False
    budget = deadline.timeout(10)
    if budget is None:
        return False
    ancestor = subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', evaluated_sha, current_sha],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=budget)
    if ancestor.returncode != 0:
        return False
    budget = deadline.timeout(10)
    if budget is None:
        return False
    changed = subprocess.check_output(['git', '-C', str(root), 'diff', '--no-ext-diff', '--no-textconv', '--name-only', '--no-renames', '-z',
                                       evaluated_sha, current_sha, '--'], timeout=budget).decode().split('\0')
    evidence_metadata = {'docs/ACCEPTANCE-EVIDENCE.json', 'docs/PROGRESS.json', 'docs/SCOPE-STATUS.json',
                         'docs/HANDOFF.md', 'docs/HANDOFF-HISTORY-2026-09-17.md'}
    for name in filter(None, changed):
        if name in evidence_metadata or (name.startswith('docs/validation/') and name.endswith('.md')):
            continue
        if re.fullmatch(r'docs/milestones/[a-z0-9-]+/ACCEPTANCE\.md', name):
            continue  # Criterion semantics remain bound by milestones.json.
        if name == MANIFEST_PATH:
            # Recording evidence must refresh this derived manifest, so treating any edit to it as a
            # source change would invalidate every record it describes. Exempt it only when it still
            # refresh is truthful and does not shrink coverage: a dropped entry, a wrong digest or a
            # path that no longer exists is corrupted integrity metadata, not bookkeeping, and must
            # not silently keep older evidence current.
            if manifest_describes_tree(root, current_sha, evaluated_sha, deadline):
                continue
            return False
        return False
    return True


def manifest_entries(root, sha, deadline=None):
    """Parsed `MANIFEST.sha256` entries at `sha`, or None when absent, malformed or out of budget."""
    if deadline is None:
        deadline = Deadline()
    budget = deadline.timeout(10)
    if budget is None:
        return None
    try:
        listing = subprocess.check_output(['git', '-C', str(root), 'show', f'{sha}:{MANIFEST_PATH}'],
                                          stderr=subprocess.DEVNULL, timeout=budget)
    except subprocess.SubprocessError:
        return None
    if len(listing) > MAXIMUM_FILE_BYTES:
        return None
    try:
        text = listing.decode('utf-8')
    except UnicodeError:
        return None
    entries, seen = [], set()
    for line in text.splitlines():
        if not line.strip():
            continue
        digest, separator, path = line.partition('  ')
        # A repeated path would also let a short manifest request one blob many times.
        if not separator or not DIGEST.fullmatch(digest) or not path or '\0' in path or path in seen:
            return None
        seen.add(path)
        entries.append((digest, path))
        if len(entries) > MAXIMUM_MANIFEST_ENTRIES:
            return None
    return entries


def manifest_describes_tree(root, sha, baseline_sha, deadline=None):
    """True when the manifest at `sha` covers everything it did at `baseline_sha` and every entry
    matches that path's content at `sha`. A refresh may widen coverage, never shrink it.

    Every step draws on one shared `deadline`; exhausting it returns False rather than continuing,
    so a manifest too large to verify in the remaining budget cannot keep older evidence current."""
    if deadline is None:
        deadline = Deadline()
    entries = manifest_entries(root, sha, deadline)
    if not entries:
        return False
    baseline = manifest_entries(root, baseline_sha, deadline) or []
    if not {path for _, path in baseline} <= {path for _, path in entries}:
        return False
    # Resolve identities and sizes first so no oversized or absent blob is ever buffered.
    request = ''.join(f'{sha}:{path}\n' for _, path in entries).encode()
    if len(request) > MAXIMUM_FILE_BYTES:
        return False
    budget = deadline.timeout(60)
    if budget is None:
        return False
    try:
        check = subprocess.run(['git', '-C', str(root), 'cat-file', '--batch-check'], input=request,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=budget)
    except subprocess.SubprocessError:
        return False
    if check.returncode != 0:
        return False
    reported = check.stdout.decode('utf-8', errors='replace').splitlines()
    if len(reported) != len(entries):
        return False
    identifiers, total = [], 0
    for line in reported:
        fields = line.split(' ')
        # A path absent at `sha` reports "<request> missing"; only a blob can back an entry.
        if len(fields) != 3 or fields[1] != 'blob' or not SHA.fullmatch(fields[0]):
            return False
        try:
            size = int(fields[2])
        except ValueError:
            return False
        if size < 0 or size > MAXIMUM_FILE_BYTES:
            return False
        total += size
        if total > MAXIMUM_MANIFEST_BYTES:
            return False
        identifiers.append(fields[0])
    for (digest, _), identifier in zip(entries, identifiers):
        # Bounded by what is left of the whole report, not by an independent per-entry timeout.
        budget = deadline.timeout(30)
        if budget is None:
            return False
        try:
            blob = subprocess.check_output(['git', '-C', str(root), 'cat-file', 'blob', identifier],
                                           stderr=subprocess.DEVNULL, timeout=budget)
        except subprocess.SubprocessError:
            return False
        if len(blob) > MAXIMUM_FILE_BYTES or hashlib.sha256(blob).hexdigest() != digest:
            return False
    return True


def evidence_status(row):
    """Report the four things a "complete" row conflates, and which one it actually fails.

    (a) a checked checkbox in a milestone ACCEPTANCE.md, (b) a ledger record whose cited bytes still
    hash to what it recorded, (c) a record whose evaluated source still describes HEAD, and (d) a
    record at the level docs/VALIDATION-PLAN.md prescribes. Each is answered independently, because a
    row can satisfy (a) and (b) while failing (c) or (d) and must not read as qualified. The
    per-dimension booleans may be answered by different records, so they diagnose rather than
    qualify; `qualified` still requires one single record to answer all four at once.
    """
    passing = [record for record in row['records'] if record['state'] == 'pass']
    qualified = bool(row['declaredComplete'] and row['hasCurrentDeclaredPass']
                     and not row['hasCurrentDeclaredBlocker'])
    status = {'checkboxComplete': bool(row['declaredComplete']),
              'hasDigestValidRecord': any(record['referencesValid'] for record in passing),
              'hasCurrentSourceRecord': any(record['currentSource'] for record in passing),
              'hasRequiredLevelRecord': any(record['levelMatchesRequired'] for record in passing),
              'promotesBelowRequiredLevel': bool(row['requiredEvidence'] not in OFFLINE_LEVELS
                                                 and any(record['level'] in OFFLINE_LEVELS for record in passing)),
              'qualified': qualified}
    if row['hasCurrentDeclaredBlocker']:
        verdict = 'current-blocker'
    elif qualified:
        verdict = 'qualified'
    elif not passing:
        if row['records']:
            verdict = 'no-passing-record'
        else:
            verdict = 'claimed-without-record' if row['declaredComplete'] else 'no-record'
    else:
        # Name the first unanswered question of the record that answers the most of them, so the
        # output points at one cause instead of restating every dimension.
        best = max(passing, key=lambda record: (record['levelMatchesRequired'],
                                                record['referencesValid'], record['currentSource']))
        if not best['levelMatchesRequired']:
            verdict = 'wrong-evidence-level'
        elif not best['referencesValid']:
            verdict = 'invalid-references'
        elif not best['currentSource']:
            verdict = 'stale-source'
        else:
            verdict = 'record-without-checkbox'
    status['verdict'] = verdict
    return status


def build_report(root, source_sha, workspace_dirty=False, source_matches=None, deadline=None):
    # `source_matches` receives this deadline, so time spent verifying a manifest inside it is spent
    # from the same budget these checks enforce rather than from an independent one.
    if deadline is None:
        deadline = Deadline()
    def check_budget():
        if deadline.expired():
            raise ValueError('Report deadline exceeded')
    root = Path(root).resolve()
    if not SHA.fullmatch(source_sha):
        raise ValueError('Invalid source SHA')
    milestones = read_json(root / 'docs/milestones.json', root)
    requirements = read_json(root / 'docs/requirements.json', root)['requirements']
    ledger = read_json(root / 'docs/ACCEPTANCE-EVIDENCE.json', root)
    if set(ledger) != {'schemaVersion', 'records'} or type(ledger['schemaVersion']) is not int or ledger['schemaVersion'] != 1 or not isinstance(ledger['records'], list):
        raise ValueError('Invalid acceptance evidence schema')
    if len(ledger["records"]) > 512:
        raise ValueError("Evidence record budget exceeded")
    rows = {}
    if not isinstance(milestones, list) or not 1 <= len(milestones) <= 16:
        raise ValueError('Milestone budget exceeded')
    for milestone in milestones:
        check_budget()
        if not isinstance(milestone['criteria'], list) or not 1 <= len(milestone['criteria']) <= 256:
            raise ValueError('Criterion budget exceeded')
        if (type(milestone['n']) is not int or not 0 <= milestone['n'] <= 9
                or not isinstance(milestone['slug'], str)
                or not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,127}', milestone['slug'])):
            raise ValueError('Unsafe milestone selector')
        table_path = root / 'docs/milestones' / milestone['slug'] / 'ACCEPTANCE.md'
        raw_table, _ = repository_file(root, table_path.relative_to(root))
        table = raw_table.decode('utf-8')
        checks = re.findall(r'^\|\s*\[([ xX])\]\s*\|\s*(M\d+-AC\d+)\s*\|', table, re.M)
        expected = [f"M{milestone['n']}-AC{i:02d}" for i in range(1, len(milestone['criteria']) + 1)]
        if [identifier for _, identifier in checks] != expected:
            raise ValueError('Acceptance table/metadata mismatch')
        for (checked, identifier), (area, level, _) in zip(checks, milestone['criteria']):
            if identifier in rows or not isinstance(area, str) or not isinstance(level, str) or level not in LEVELS:
                raise ValueError('Duplicate acceptance ID or unknown evidence level')
            rows[identifier] = {'id': identifier, 'area': area, 'requiredEvidence': level,
                                'declaredComplete': checked.lower() == 'x', 'records': [],
                                'hasCurrentDeclaredPass': False, 'hasCurrentDeclaredBlocker': False}
    seen, cache, total = set(), {}, [0]
    for record in ledger['records']:
        check_budget()
        keys = {'acceptanceID', 'level', 'state', 'sourceSHA', 'implementation', 'evidence'}
        if not isinstance(record, dict) or set(record) != keys:
            raise ValueError('Invalid evidence record shape')
        identifier = record['acceptanceID']
        if identifier not in rows or record['level'] not in LEVELS or record['state'] not in STATES:
            raise ValueError('Unknown acceptance ID, level or state')
        if not isinstance(record['sourceSHA'], str) or not SHA.fullmatch(record['sourceSHA']):
            raise ValueError('Invalid evidence source SHA')
        selector = (identifier, record['level'], record['sourceSHA'])
        if selector in seen:
            raise ValueError('Duplicate evidence assessment')
        seen.add(selector)
        implementations, evidence = record['implementation'], record['evidence']
        if (not isinstance(implementations, list) or not isinstance(evidence, list)
                or len(implementations) > 16 or len(evidence) > 16):
            raise ValueError('Invalid reference lists')
        valid = (bool(implementations) and bool(evidence)
                 and all(validate_reference(root, ref, cache, total) for ref in implementations + evidence))
        current = (record['sourceSHA'] == source_sha or
                   (source_matches is not None and source_matches(record['sourceSHA'], deadline))) and not workspace_dirty
        level_matches = record['level'] == rows[identifier]['requiredEvidence']
        eligible = record['state'] == 'pass' and valid and current and level_matches
        check_budget()
        rows[identifier]['hasCurrentDeclaredPass'] |= eligible
        rows[identifier]['hasCurrentDeclaredBlocker'] |= current and record['state'] in {'fail', 'blocked'}
        rows[identifier]['records'].append({'level': record['level'], 'state': record['state'],
                                            'referencesValid': bool(valid), 'currentSource': bool(current),
                                            'levelMatchesRequired': bool(level_matches),
                                            'meetsRequiredDeclaredEvidence': bool(eligible)})
    for row in rows.values():
        check_budget()
        row['evidenceStatus'] = evidence_status(row)
    report_requirements, requirement_ids = [], set()
    for requirement in requirements:
        identifier, mapped = requirement['id'], requirement['acceptanceIDs']
        if identifier in requirement_ids or not mapped or len(mapped) != len(set(mapped)) or any(i not in rows for i in mapped):
            raise ValueError('Invalid requirement/acceptance mapping')
        if type(requirement['mandatory']) is not bool:
            raise ValueError('Invalid mandatory flag')
        requirement_ids.add(identifier)
        pending = [i for i in mapped if not (rows[i]['declaredComplete'] and rows[i]['hasCurrentDeclaredPass'] and not rows[i]['hasCurrentDeclaredBlocker'])]
        report_requirements.append({'id': identifier, 'mandatory': requirement['mandatory'],
                                    'acceptanceIDs': mapped, 'pendingAcceptanceIDs': pending})
    mandatory = [r for r in report_requirements if r['mandatory']]
    check_budget()
    summary = {name: 0 for name in VERDICTS}
    # Four separate counts, never one. A reader who trusts the checkboxes sees the first figure;
    # the honest one is the last. Measured on main at c3bbc5c they read 13 / 2 / 0 / 0 / 0, and the
    # eleven checked rows with no record at all are counted separately from the stale ones.
    counts = {'checkboxComplete': 0, 'hasDigestValidRecord': 0, 'hasCurrentSourceRecord': 0,
              'hasRequiredLevelRecord': 0, 'checkedWithNoRecord': 0, 'qualified': 0}
    for row in rows.values():
        summary[row['evidenceStatus']['verdict']] += 1
        for name in counts:
            counts[name] += bool(row['evidenceStatus'].get(name))
        counts['checkedWithNoRecord'] += bool(row['declaredComplete'] and not row['records'])
    return {'schemaVersion': 1, 'sourceSHA': source_sha, 'workspaceDirty': workspace_dirty,
            'evidenceMeaning': 'Maintainer declarations with checked references; not independent semantic or hardware verification.',
            'evidenceStatusMeaning': ('checkboxComplete is a milestone checkbox, hasDigestValidRecord is a ledger '
                                      'record whose cited bytes still match, hasCurrentSourceRecord is a record whose '
                                      'evaluated source still describes HEAD, hasRequiredLevelRecord is a record at the '
                                      'prescribed A/C/I/H/R level. Only qualified means one single record answers all four.'),
            'readyForMaintainerReview': bool(mandatory) and all(not r['pendingAcceptanceIDs'] for r in mandatory),
            'evidenceSummary': summary, 'evidenceCounts': counts,
            'requirements': report_requirements, 'acceptance': list(rows.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        source = subprocess.check_output(['git', '-C', str(args.root), 'rev-parse', 'HEAD'], text=True, timeout=10).strip()
        dirty = bool(subprocess.check_output(['git', '-C', str(args.root), 'status', '--porcelain'], text=True, timeout=10))
        matches = {}
        def source_matches(evaluated, deadline):
            if evaluated not in matches:
                if len(matches) >= 512:
                    raise ValueError('Source revision budget exceeded')
                matches[evaluated] = source_is_unchanged(args.root, evaluated, source, deadline)
            return matches[evaluated]
        report = build_report(args.root, source, dirty, source_matches)
        final_source = subprocess.check_output(['git', '-C', str(args.root), 'rev-parse', 'HEAD'], text=True, timeout=10).strip()
        final_dirty = bool(subprocess.check_output(['git', '-C', str(args.root), 'status', '--porcelain'], text=True, timeout=10))
        if final_source != source or final_dirty != dirty:
            raise ValueError('Workspace changed during report')
        print(json.dumps(report, indent=2))
    except (ValueError, OSError, KeyError, TypeError, RecursionError, UnicodeError, subprocess.SubprocessError):
        parser.exit(1, 'Invalid traceability input; no qualification result produced.\n')


if __name__ == '__main__':
    main()
