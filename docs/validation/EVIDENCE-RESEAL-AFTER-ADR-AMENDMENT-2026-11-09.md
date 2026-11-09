# Re-seal M2-AC04, M2-AC05, M2-AC13 and M3-AC03 after #175 and #176 — 2026-11-09

Level A. **No new claim.** This is a rebind, not a re-verification. All four records move from
`37d24316224dd91d49d387f0052b7350acbd4c74` to `3d5f3458555d7baded51740a3a3628b26f62c8ca`, the tip of
`main` after #176.

## Why they were stale

#175 (`c509c29`) touched only exempt paths; it was itself the previous re-seal. #176 (`3d5f345`) touched
one source path, `docs/adr/0005-queue-installation-transaction.md`.

## A rebind, not a re-verification

The four records cite **51** paths between them, counting the receipt each one cites. Every one was
re-hashed with `git show 3d5f345:<path>`: **51 of 51 match**. No record cites the ADR. Apart from the
receipt replacement below, `sourceSHA` is the only field that moves.

## Receipt replaced, not appended

In all four records the citation of
`docs/validation/EVIDENCE-RESEAL-AFTER-RELOAD-ADMISSION-2026-11-09.md` is **replaced** by this document, so
no record's reference count changes. The chain, by name:

- `docs/validation/M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-CLAUDE-MD-AND-UPLOAD-ARTIFACT-2026-11-09.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-SPIKE-AND-UNINSTALL-SLICES-2026-11-09.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-RELOAD-ADMISSION-2026-11-09.md`
- this document

**No evidence of any criterion is removed or weakened.**

## Executed evidence

#176's head ran `repository-preflight` and `portable-ubuntu-arm64` green (run 42714971015); the macOS job
was skipped by the scope classifier because #176 changed only documentation, which `ci-required` accepted as
a legitimate skip. The bound tree's LabelCore suite was also run locally: 485 tests, 0 failures.

## Validation

Linux container. Exit status taken from each command itself:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | OK (skipped=2) |
| `python3 scripts/manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| `python3 scripts/evidence_currency.py --gate-stale` (after committing, clean worktree) | exit 0; no stale record remains |

**NOT RUN:** macOS, GUI, installed scheduler, USB transport, physical output and every release gate.

## Scope

Touches only paths `source_is_unchanged` exempts, so the binding survives its own squash merge.
