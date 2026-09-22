# Re-seal M2-AC04, M2-AC05, M2-AC13 and M3-AC03 after fourteen merged slices — 2026-09-22

Level A. **No new claim.** This is a rebind, not a re-verification. All four records move from
`1471eda37aa4f03415a8f89097bd362464efcc84` to `55a67f89dba5c2024a22639a362200f46daeeb04`, the tip of
`main` after #161.

## Why they were stale

Fifteen pull requests merged between the previously bound `1471eda` and this one. #147 (`96e3391`)
touched only exempt paths; it was itself the previous re-seal. Each of the other fourteen touched at
least one path `source_is_unchanged` treats as source, so each staled all four records on its own.

| Merge | Non-exempt paths |
|---|---|
| #149 `c203c27` | `FinishingFramedCommandFamilyTests.swift` |
| #151 `19474bf` | `WorkerTicketSchemaV3Tests.swift` |
| #152 `a9e7474` | `M3ControlQualificationCoverageTests.swift` |
| #153 `3877f39` | `.gitignore`, `AGENTS.md`, `TRACEABILITY.md` |
| #154 `c7e7353` | `OfflineConversion.swift`, `OfflineConversionTicketErrorSurfaceTests.swift`, `WorkerTicketSchemaV3Tests.swift` |
| #155 `9272f9b` | 5 files: `PrinterProfile.swift`, `GeometryControlIntegrationTests.swift`, `M3ControlQualificationCoverageTests.swift`, `PrinterProfileTests.swift`, `VirtualQueueDefinitionTests.swift` |
| #157 `2eef3a1` | `FinishingControlQualificationTests.swift` |
| #158 `e04f40d` | `BUILDING.md`, `check_native_artifacts.py`, `ci-swift.sh`, `test_native_artifacts.py` |
| #159 `b77d164` | `AcceptedJobStateTests.swift`, `ExtractionPlanTests.swift`, `PagePlacementFitQuantizationTests.swift`, `SourceRegionSelectionTests.swift` |
| #163 `fb7c9f9` | `ci.yml`, `BUILDING.md`, `test_traceability_report.py` |
| #150 `cb5b562` | `QueueInstallationOwnershipRecord.swift`, `QueueInstallationRecovery.swift`, `QueueInstallationTransaction.swift`, `QueueInstallationTransactionTests.swift` |
| #156 `4b16baa` | 6 files: `AGENTS.md`, `BUILDING.md`, `VALIDATION-PLAN.md`, `test-surfaces.json`, `check_test_surfaces.py`, `test_check_test_surfaces.py` |
| #160 `a5e50a0` | `ci.yml` |
| #161 `55a67f8` | `ci.yml` |

Nine of these fourteen merged before this session and were never re-sealed. They had left the same four
records `stale-source` on `main` since #149. The last five (#163, #150, #156, #160 and #161) are this
session's. Batching them all under one receipt is what `AGENTS.md` asks for.

## A rebind, not a re-verification

The four records cite **49** implementation and evidence paths between them:

| Record | Cited before | Superseded receipt | Re-hashed at `55a67f8` | Match |
|---|---:|---|---:|---:|
| `M2-AC04` | 7 | `M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md` | 7 | 7 |
| `M2-AC13` | 20 | `M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md` | 20 | 20 |
| `M2-AC05` | 11 | none | 11 | 11 |
| `M3-AC03` | 11 | none | 11 | 11 |

**49 of 49 match.** None of the fourteen merges changed a byte of any cited path; the digests were
computed against the committed tree at `55a67f8`, not a working copy. Apart from the receipt change below,
`sourceSHA` is the only field that moves on any record.

## Receipts: replaced, and added where none existed

`M2-AC04` and `M2-AC13` each cited `docs/validation/M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md`. That
citation is **replaced** by this document, not joined by it, per the receipt-replacement rule in
`AGENTS.md`. `M2-AC13` stays at 13 evidence entries.

`M2-AC05` and `M3-AC03` were first bound by #147 against the hosted `macos-26` run in
`docs/validation/M3-HOSTED-MACOS-CONTROL-COVERAGE-2026-09-20.md`. That document is their original
evidence, not a receipt, and it stays. They had no receipt to replace, so this one is **added**, taking
each from 6 evidence entries to 7, well inside the 16-entry cap.

The chain stays auditable by name:

- `docs/validation/M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-SEVEN-SLICES-2026-09-20.md`
- this document

**No evidence of any criterion is removed or weakened.** A receipt records that a rebind happened and
why it was safe. It says nothing about whether the criterion holds; the tests, the oracle and the
original validation documents do, and every one is untouched and still digest-valid.

## Executed evidence for the bound commit

This slice touches no Swift file and runs no Swift suite as its evidence. The bound commit's own CI is the
execution record: every one of the fourteen merges went through `ci-required`, and the last five were
green on their exact heads, with `swift-macos-arm64` executed rather than skipped:

| PR | Head | macOS job |
|---|---|---|
| #163 | `e6fb35c` | executed, passed |
| #150 | `187d5a1` | executed, passed |
| #156 | `45be538` | executed, passed |
| #160 | `477e1fb` | executed, passed |
| #161 | `cf5b6e5` | executed, passed |

`portable-ubuntu-arm64` also ran and passed on #156, #160 and #161. A PR run is not a run of the squashed
`main` commit. The `main` push run for `55a67f8` is the one that compiles the exact bound tree.

## Validation

Linux container, Swift 6.1.3, CPython 3.11. Exit status taken from each command itself:

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
