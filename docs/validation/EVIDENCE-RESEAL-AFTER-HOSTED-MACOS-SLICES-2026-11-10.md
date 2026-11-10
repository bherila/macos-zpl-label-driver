# Re-seal seven records after #178–#181 — 2026-11-10

Level A. **No new claim.** This is a rebind, not a re-verification. Seven records move from
`3d5f3458555d7baded51740a3a3628b26f62c8ca` to `3287cc0d941ee42d60c471ba415fc38db7b75c80`, the tip of
`main` after #181: `M2-AC04`, `M2-AC05`, `M2-AC13`, `M3-AC03`, `M4-AC03`, `M4-AC04` and `M4-AC05`.

## Why they were stale

#177 (`cecdcee`) touched only exempt paths; it was itself the previous re-seal. Four source merges followed:
#178 (`2d196cf`, `Packages/LabelMac/Sources/LabelSetupApp/main.swift`), #179 (`358ed07`,
`PDFPageGeometryAsymmetricRegionTests.swift`), #180 (`36cb890`, `QuartzPDFRendererInputSizeBoundTests.swift`) and
#181 (`3287cc0`, `docs/test-surfaces.json`, `docs/VALIDATION-PLAN.md` and `scripts/tests/test_check_test_surfaces.py`).

## A rebind, not a re-verification

The seven records cite **72** paths between them. Every one was re-hashed with `git show 3287cc0:<path>`:
**72 of 72 match**. None of the files those merges changed is cited by any of the seven. Apart from the
receipt change below, `sourceSHA` is the only field that moves.

## Receipts

- `M2-AC04`, `M2-AC05`, `M2-AC13` and `M3-AC03` cited
  `docs/validation/EVIDENCE-RESEAL-AFTER-ADR-AMENDMENT-2026-11-09.md`. That citation is **replaced** by this
  document.
- `M4-AC03`, `M4-AC04` and `M4-AC05` were first bound by #177 and cited no receipt. This one is **added**,
  taking each from 5, 5 and 4 evidence entries to 6, 6 and 5, well inside the 16-entry cap.

The chain, by name, for the first four:
`M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19`, `M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19`,
`M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19`, `M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19`,
`M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19`, `M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20`,
`EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22`,
`EVIDENCE-RESEAL-AFTER-CLAUDE-MD-AND-UPLOAD-ARTIFACT-2026-11-09`,
`EVIDENCE-RESEAL-AFTER-SPIKE-AND-UNINSTALL-SLICES-2026-11-09`,
`EVIDENCE-RESEAL-AFTER-RELOAD-ADMISSION-2026-11-09`, `EVIDENCE-RESEAL-AFTER-ADR-AMENDMENT-2026-11-09`
(all under `docs/validation/`), then this document.

**No evidence of any criterion is removed or weakened.**

## Executed evidence

`main` push run 42727833058 at `36cb890` (Swift-identical to the bound tree, see the other document): all four checks green, `swift-macos-arm64` executed rather than
skipped, LabelMac debug and release with 0 failures (see
`docs/validation/M2-M4-HOSTED-MACOS-EVIDENCE-2026-11-10.md`).

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
