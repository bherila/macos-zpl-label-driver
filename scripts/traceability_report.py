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
SHA = re.compile(r'[0-9a-f]{40}\Z')
DIGEST = re.compile(r'[0-9a-f]{64}\Z')
MAXIMUM_FILE_BYTES = 2 * 1024 * 1024
MANIFEST_PATH = 'MANIFEST.sha256'
MAXIMUM_MANIFEST_ENTRIES = 4096


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


def source_is_unchanged(root, evaluated_sha, current_sha):
    if not SHA.fullmatch(evaluated_sha) or not SHA.fullmatch(current_sha):
        return False
    ancestor = subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', evaluated_sha, current_sha],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    if ancestor.returncode != 0:
        return False
    changed = subprocess.check_output(['git', '-C', str(root), 'diff', '--no-ext-diff', '--no-textconv', '--name-only', '--no-renames', '-z',
                                       evaluated_sha, current_sha, '--'], timeout=10).decode().split('\0')
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
            # describes the tree exactly: a deleted entry or a wrong digest is corrupted integrity
            # metadata, not bookkeeping, and must not silently keep older evidence current.
            if manifest_describes_tree(root, current_sha):
                continue
            return False
        return False
    return True


def manifest_describes_tree(root, sha):
    """True when every MANIFEST.sha256 entry at `sha` matches that path's content at `sha`."""
    try:
        listing = subprocess.check_output(['git', '-C', str(root), 'show', f'{sha}:{MANIFEST_PATH}'],
                                          stderr=subprocess.DEVNULL, timeout=10)
    except subprocess.SubprocessError:
        return False
    if len(listing) > MAXIMUM_FILE_BYTES:
        return False
    entries = []
    for line in listing.decode('utf-8', errors='strict').splitlines():
        if not line.strip():
            continue
        digest, separator, path = line.partition('  ')
        if not separator or not DIGEST.fullmatch(digest) or not path or '\0' in path:
            return False
        entries.append((digest, path))
        if len(entries) > MAXIMUM_MANIFEST_ENTRIES:
            return False
    if not entries:
        return False
    request = ''.join(f'{sha}:{path}\n' for _, path in entries).encode()
    try:
        batch = subprocess.run(['git', '-C', str(root), 'cat-file', '--batch'],
                               input=request, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    except subprocess.SubprocessError:
        return False
    if batch.returncode != 0:
        return False
    stream, offset = batch.stdout, 0
    for digest, _ in entries:
        end = stream.find(b'\n', offset)
        if end < 0:
            return False
        header = stream[offset:end].split(b' ')
        # A missing path yields "<request> missing"; only a blob can back an entry.
        if len(header) != 3 or header[1] != b'blob':
            return False
        try:
            size = int(header[2])
        except ValueError:
            return False
        start = end + 1
        offset = start + size + 1
        if size < 0 or offset > len(stream):
            return False
        if hashlib.sha256(stream[start:start + size]).hexdigest() != digest:
            return False
    return offset == len(stream)


def build_report(root, source_sha, workspace_dirty=False, source_matches=None):
    started = time.monotonic()
    def check_budget():
        if time.monotonic() - started >= 60:
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
                   (source_matches is not None and source_matches(record['sourceSHA']))) and not workspace_dirty
        eligible = (record['state'] == 'pass' and valid and current
                    and record['level'] == rows[identifier]['requiredEvidence'])
        check_budget()
        rows[identifier]['hasCurrentDeclaredPass'] |= eligible
        rows[identifier]['hasCurrentDeclaredBlocker'] |= current and record['state'] in {'fail', 'blocked'}
        rows[identifier]['records'].append({'level': record['level'], 'state': record['state'],
                                            'referencesValid': bool(valid), 'currentSource': current,
                                            'meetsRequiredDeclaredEvidence': bool(eligible)})
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
    return {'schemaVersion': 1, 'sourceSHA': source_sha, 'workspaceDirty': workspace_dirty,
            'evidenceMeaning': 'Maintainer declarations with checked references; not independent semantic or hardware verification.',
            'readyForMaintainerReview': bool(mandatory) and all(not r['pendingAcceptanceIDs'] for r in mandatory),
            'requirements': report_requirements, 'acceptance': list(rows.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        source = subprocess.check_output(['git', '-C', str(args.root), 'rev-parse', 'HEAD'], text=True, timeout=10).strip()
        dirty = bool(subprocess.check_output(['git', '-C', str(args.root), 'status', '--porcelain'], text=True, timeout=10))
        matches = {}
        def source_matches(evaluated):
            if evaluated not in matches:
                if len(matches) >= 512:
                    raise ValueError('Source revision budget exceeded')
                matches[evaluated] = source_is_unchanged(args.root, evaluated, source)
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
