# Re-seal M2-AC04, M2-AC05, M2-AC13 and M3-AC03 after #166 and #167 — 2026-11-09

Level A. **No new claim.** This is a rebind, not a re-verification. All four records move from
`55a67f89dba5c2024a22639a362200f46daeeb04` to `9dd834e72d5c8a6704d6853f3d141864b78bb74e`, the tip of
`main` after #167.

## Why they were stale

Three pull requests merged after the previously bound `55a67f8`. #164 (`2c6cb41`) touched only exempt
paths; it was itself the previous re-seal. The other two touched paths `source_is_unchanged` treats as
source:

| Merge | Non-exempt paths |
|---|---|
| #166 `2c2c889` | `CLAUDE.md` (removed) |
| #167 `9dd834e` | `.github/workflows/ci.yml` (`actions/upload-artifact` 7.0.1 → 7.0.2) |

#166 left all four records `stale-source` on `main` from 2026-11-07, and the scheduled
`Evidence staleness` workflow failed on each run from then (runs 48, 49 and 50). #167 was batched under
this same receipt rather than re-sealing twice.

## A rebind, not a re-verification

The four records cite **51** paths between them, counting the receipt each one cites. Every one was
re-hashed with `git show 9dd834e:<path>` against the committed tree, not a working copy:

| Record | Cited before | Superseded receipt | Re-hashed at `9dd834e` | Match |
|---|---:|---|---:|---:|
| `M2-AC04` | 7 | `EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md` | 7 | 7 |
| `M2-AC13` | 20 | `EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md` | 20 | 20 |
| `M2-AC05` | 12 | `EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md` | 12 | 12 |
| `M3-AC03` | 12 | `EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md` | 12 | 12 |

**51 of 51 match.** Neither merge changed a byte of any cited path. Apart from the receipt replacement
below, `sourceSHA` is the only field that moves on any record.

## Receipt replaced, not appended

In all four records the citation of
`docs/validation/EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md` is **replaced** by this document,
per the receipt-replacement rule in `AGENTS.md`. No record's reference count changes.

The chain stays auditable by name:

- `docs/validation/M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md`
- this document

**No evidence of any criterion is removed or weakened.** A receipt records that a rebind happened and
why it was safe; the tests, the oracle and the original validation documents carry the claim, and every
one is untouched and still digest-valid.

## Executed evidence for the bound commit

This slice touches no Swift file and runs no Swift suite as its evidence. #167 was green on its exact
head `579da37` in run 42683401956: `repository-preflight`, `portable-ubuntu-arm64`,
`swift-macos-arm64` (executed, not skipped) and `ci-required` all succeeded. A PR run is not a run of the
squashed `main` commit; the `main` push run for `9dd834e` compiles the exact bound tree.

## Validation

Linux container. Exit status taken from each command itself:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | OK (skipped=2) |
| `python3 scripts/manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| `python3 scripts/evidence_currency.py --gate-stale` (after committing, clean worktree) | exit 0; no stale record remains |

**NOT RUN:** macOS, GUI, installed scheduler, USB transport, physical output and every release gate.
This rebind qualifies none of them.

## Scope

Touches only paths `source_is_unchanged` exempts (`docs/ACCEPTANCE-EVIDENCE.json`, `docs/PROGRESS.json`,
`docs/HANDOFF.md`, this document and `MANIFEST.sha256`), so the binding survives its own squash merge.
