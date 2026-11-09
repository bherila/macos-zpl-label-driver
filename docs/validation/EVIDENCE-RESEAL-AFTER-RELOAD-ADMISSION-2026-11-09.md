# Re-seal M2-AC04, M2-AC05, M2-AC13 and M3-AC03 after #174 — 2026-11-09

Level A. **No new claim.** This is a rebind, not a re-verification. All four records move from
`041afb5e09bd87ea89f12d17b9742c3e92700abb` to `37d24316224dd91d49d387f0052b7350acbd4c74`, the tip of
`main` after #174.

## Why they were stale

Two pull requests merged after the previously bound `041afb5`. #173 (`c9368da`) touched only exempt
paths; it was itself the previous re-seal. #174 (`37d2431`) touched source:
`Packages/LabelMac/Sources/LabelMac/WorkflowEditor.swift` and
`Packages/LabelMac/Tests/LabelMacTests/WorkflowEditorBootstrapTests.swift`.

## A rebind, not a re-verification

The four records cite **51** paths between them, counting the receipt each one cites. Every one was
re-hashed with `git show 37d2431:<path>`: **51 of 51 match**. Neither file #174 changed is cited by any
record. Apart from the receipt replacement below, `sourceSHA` is the only field that moves.

## Receipt replaced, not appended

In all four records the citation of
`docs/validation/EVIDENCE-RESEAL-AFTER-SPIKE-AND-UNINSTALL-SLICES-2026-11-09.md` is **replaced** by this
document, so no record's reference count changes. The chain, by name:

- `docs/validation/M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-CLAUDE-MD-AND-UPLOAD-ARTIFACT-2026-11-09.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-SPIKE-AND-UNINSTALL-SLICES-2026-11-09.md`
- this document

**No evidence of any criterion is removed or weakened.**

## Executed evidence for the bound commit

#174 was green on its exact head `b389a63` in run 42709853238, with `swift-macos-arm64` executed rather
than skipped. The macOS log shows `testReloadForCorrectionAdmitsTheStoredRevisionsPlannedLabels` passing
in debug and release, and every suite reporting 0 failures. A PR run is not a run of the squashed `main`
commit; the `main` push run for `37d2431` compiles the exact bound tree. The mutation check for #174's
guard was **NOT RUN**: it needs a macOS host.

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

Touches only paths `source_is_unchanged` exempts (`docs/ACCEPTANCE-EVIDENCE.json`, `docs/PROGRESS.json`,
`docs/HANDOFF.md`, this document and `MANIFEST.sha256`), so the binding survives its own squash merge.
