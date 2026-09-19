#!/usr/bin/env python3
"""Refresh `MANIFEST.sha256` in place: the one command that pays the coverage tax.

ADR 0004 option 1 makes every pull request that touches a covered file refresh this
manifest in the same commit. That is a real per-contributor cost, and a cost paid by
hand is a cost eventually forgotten -- so it is paid here instead.

This writes; `scripts/manifest_audit.py` reads and never writes. Every path rule,
size cap and symlink defence is imported from that module rather than restated, so
the two cannot drift: an entry is hashed here exactly as the audit hashes it, through
one `O_NOFOLLOW` descriptor chain, refusing anything over the cap.

Two deliberate refusals:

* An entry is never removed. `manifest_describes_tree` permits a widening refresh and
  forbids a shrinking one, because a dropped entry is corrupted integrity metadata
  rather than bookkeeping. Removing a path is therefore a manual edit a reviewer must
  see, not something a refresh may do silently.
* A file that is absent, unreadable or oversized is reported and left at its recorded
  digest. Rewriting it to some placeholder would turn an integrity failure into a
  clean build, which is the exact inversion this manifest exists to prevent.
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from manifest_audit import (  # noqa: E402
    CannotMeasure, MANIFEST_PATH, MAXIMUM_ENTRIES,
    parse_manifest, read_repository_file, repository_relative, tracked_files,
)

ROOT = Path(__file__).resolve().parents[1]


def digest_of(root: Path, name: str) -> tuple[str, str]:
    """('ok', hex) or (why-not, '')."""
    status, _, body = read_repository_file(root, name)
    if status != 'read':
        return status, ''
    return 'ok', hashlib.sha256(body).hexdigest()


def refresh(root: Path, backfill: bool) -> dict:
    recorded = parse_manifest(root)
    names = set(recorded)
    if backfill:
        # The manifest never describes itself.
        names |= {n for n in tracked_files(root) if n != MANIFEST_PATH}
    if len(names) > MAXIMUM_ENTRIES:
        raise CannotMeasure(
            f'{len(names)} entries exceeds the {MAXIMUM_ENTRIES} cap a valid manifest may hold')

    updated, added, refused = {}, [], []
    for name in sorted(names):
        if not repository_relative(name):
            refused.append((name, 'not a repository-relative path'))
            continue
        why, hexdigest = digest_of(root, name)
        if why != 'ok':
            # Keep what was recorded; an integrity failure must stay visible to the audit.
            if name in recorded:
                updated[name] = recorded[name]
            refused.append((name, why))
            continue
        updated[name] = hexdigest
        if name not in recorded:
            added.append(name)

    changed = [n for n in updated if n in recorded and updated[n] != recorded[n]]
    body = ''.join(f'{updated[n]}  {n}\n' for n in sorted(updated))
    return {'body': body, 'added': added, 'changed': sorted(changed),
            'refused': refused, 'total': len(updated)}


def main() -> int:
    backfill = '--backfill' in sys.argv[1:]
    check = '--check' in sys.argv[1:]
    for flag in sys.argv[1:]:
        if flag not in {'--backfill', '--check'}:
            print(f'unknown option {flag}', file=sys.stderr)
            return 2
    try:
        result = refresh(ROOT, backfill)
    except CannotMeasure as error:
        print(f'CANNOT-REFRESH {error}', file=sys.stderr)
        return 2

    target = ROOT / MANIFEST_PATH
    identical = target.read_text(encoding='utf-8') == result['body']
    if check:
        print(f'{result["total"]} entries; '
              f'{len(result["changed"])} would be refreshed, {len(result["added"])} would be added')
        return 0 if identical else 1

    if not identical:
        target.write_text(result['body'], encoding='utf-8')
    for name in result['changed']:
        print(f'  refreshed {name}')
    for name in result['added']:
        print(f'  added     {name}')
    for name, why in result['refused']:
        print(f'  REFUSED   {name}: {why}', file=sys.stderr)
    print(f'{result["total"]} entries, {len(result["changed"])} refreshed, '
          f'{len(result["added"])} added, {len(result["refused"])} refused')
    # A refused entry is an integrity problem the audit must still see.
    return 1 if result['refused'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
