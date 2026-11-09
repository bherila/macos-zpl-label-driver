# Re-seal M2-AC04, M2-AC05, M2-AC13 and M3-AC03 after #169–#172 — 2026-11-09

Level A. **No new claim.** This is a rebind, not a re-verification. All four records move from
`9dd834e72d5c8a6704d6853f3d141864b78bb74e` to `041afb5e09bd87ea89f12d17b9742c3e92700abb`, the tip of
`main` after #172.

## Why they were stale

Five pull requests merged after the previously bound `9dd834e`. #168 (`3ff0ac9`) touched only exempt
paths; it was itself the previous re-seal. The other four touched source paths:

| Merge | Non-exempt paths |
|---|---|
| #169 `1e61bfa` | `DECISIONS.md`, `BUILDING.md`, `hosted-queue-spike.yml`, `hosted_queue_spike.sh`, `test_hosted_queue_spike.py` |
| #170 `303d3fe` | `DECISIONS.md`, `hosted_queue_spike.sh` |
| #171 `b43dd02` | `UninstallVerification.swift`, `UninstallVerificationTests.swift` |
| #172 `041afb5` | `QuartzPDFRenderer.swift`, `WorkflowEditorBootstrapTests.swift` |

## A rebind, not a re-verification

The four records cite **51** paths between them, counting the receipt each one cites. Every one was
re-hashed with `git show 041afb5:<path>`: **51 of 51 match**. None of the four merges changed a byte of
any cited path. #172 changed `QuartzPDFRenderer.swift`, which no record cites. Apart from the receipt
replacement below, `sourceSHA` is the only field that moves.

## Receipt replaced, not appended

In all four records the citation of
`docs/validation/EVIDENCE-RESEAL-AFTER-CLAUDE-MD-AND-UPLOAD-ARTIFACT-2026-11-09.md` is **replaced** by
this document, so no record's reference count changes. The chain, by name:

- `docs/validation/M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-FOURTEEN-SLICES-2026-09-22.md`
- `docs/validation/EVIDENCE-RESEAL-AFTER-CLAUDE-MD-AND-UPLOAD-ARTIFACT-2026-11-09.md`
- this document

**No evidence of any criterion is removed or weakened.**

## Executed evidence for the bound commit

All four merges were green on their exact heads, with `swift-macos-arm64` executed rather than skipped:

| PR | Head | Run |
|---|---|---|
| #169 | `1239de2` | 42692845396 |
| #170 | `f2923d9` | 42697549940 |
| #171 | `781afa2` | 42700256865 |
| #172 | `3803639` | 42703546765 |

A PR run is not a run of the squashed `main` commit. The `main` push run for `041afb5` compiles the
exact bound tree.

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

Touches only paths `source_is_unchanged` exempts (`docs/ACCEPTANCE-EVIDENCE.json`, `docs/PROGRESS.json`,
`docs/HANDOFF.md`, this document and `MANIFEST.sha256`), so the binding survives its own squash merge.
