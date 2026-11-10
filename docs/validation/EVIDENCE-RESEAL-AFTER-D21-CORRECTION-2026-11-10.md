# Re-seal ten records after #183 — 2026-11-10

Level A. **No new claim.** This is a rebind, not a re-verification. All ten records move from
`3287cc0d941ee42d60c471ba415fc38db7b75c80` to `d62312655b77a04c394db21dfe3f08d92e5ad24f`, the tip of `main`
after #183: `M2-AC04`, `M2-AC05`, `M2-AC09`, `M2-AC13`, `M3-AC03`, `M4-AC02`, `M4-AC03`, `M4-AC04`, `M4-AC05`
and `M4-AC13`.

## Why they were stale

#182 (`69a944a`) touched only exempt paths; it was itself the previous re-seal. #183 (`d623126`) changed one
source path, `docs/DECISIONS.md` (a correction to decision D21), which no record cites.

## A rebind, not a re-verification

The ten records cite **102** paths between them, counting each record's receipt. Every one was re-hashed with
`git show d623126:<path>`: **102 of 102 match**. Apart from the receipt replacement below, `sourceSHA` is the
only field that moves.

## Receipt replaced, not appended

In the seven records that cite one (`M2-AC04`, `M2-AC05`, `M2-AC13`, `M3-AC03`, `M4-AC03`, `M4-AC04`,
`M4-AC05`) the citation of
`docs/validation/EVIDENCE-RESEAL-AFTER-HOSTED-MACOS-SLICES-2026-11-10.md` is **replaced** by this document, so
no record's reference count changes. The other three (`M2-AC09`, `M4-AC02`, `M4-AC13`) were written in #182,
cite no receipt, and are not given one: for them `sourceSHA` is the only field that moves. The chain, all under `docs/validation/`, by name:
`M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19`, `M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19`,
`M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19`, `M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19`,
`M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19`, `M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20`,
`EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22`,
`EVIDENCE-RESEAL-AFTER-CLAUDE-MD-AND-UPLOAD-ARTIFACT-2026-11-09`,
`EVIDENCE-RESEAL-AFTER-SPIKE-AND-UNINSTALL-SLICES-2026-11-09`,
`EVIDENCE-RESEAL-AFTER-RELOAD-ADMISSION-2026-11-09`, `EVIDENCE-RESEAL-AFTER-ADR-AMENDMENT-2026-11-09`,
`EVIDENCE-RESEAL-AFTER-HOSTED-MACOS-SLICES-2026-11-10`, then this document.

**No evidence of any criterion is removed or weakened.**

## Executed evidence

#183's head ran `repository-preflight` and `portable-ubuntu-arm64` green (run 42734376403); the macOS job
was skipped by the scope classifier because #183 changed only documentation, which `ci-required` accepted as a
legitimate skip. Every Swift source and test is byte-identical to `3287cc0` and to `36cb890`, whose macOS run
is the executed evidence cited in `M2-M4-HOSTED-MACOS-EVIDENCE-2026-11-10.md`.

## Validation

Linux container. Exit status taken from each command itself:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | OK (skipped=2) |
| `python3 scripts/manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| `python3 scripts/evidence_currency.py --gate-stale` (after committing, clean worktree) | exit 0; no stale record remains |

**NOT RUN:** GUI, installed scheduler, USB transport, physical output and every release gate.

## Scope

Touches only paths `source_is_unchanged` exempts, so the binding survives its own squash merge.
