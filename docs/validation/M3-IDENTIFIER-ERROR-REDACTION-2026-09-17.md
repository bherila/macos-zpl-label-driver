# Identifier-bearing error diagnostics — 2026-09-17

Evaluated local unpublished source `2c128dbf7d47c14a52e3fbb47764ce0c5acf3252`. Advances the routine-diagnostic portion of M3-AC12; does not complete its whole privacy/permissions criterion.

## Defect and independent constraint

Six public error cases carried caller-supplied identifiers into normal description, reflection and nested structural dump: VirtualQueueError.invalidSelector/duplicateQueueID; WorkflowProfileDraft.Error.regionNotFound; ExtractionPlanError.missingAnchor/ambiguousAnchor; ReferenceWorkflowError.requiresTeachOnce. These four types now reuse RedactedDiagnosticValue, with fixed case-specific descriptions. Typed enum payloads and Equatable identity remain intact; applicable page numbers remain available in descriptions. This is diagnostic redaction, not access control or automatic sanitization of arbitrary errors.

The nearest independent constraint is preservation of typed error identity and original associated values while all routine formatting paths redact identifiers. DiagnosticErrorRedactionTests enumerates all six cases, checks description/reflection/nested dump, checks typed values/equality, distinguishes selector/duplicate cases, and exercises the actual invalid-selector constructor failure. Synthetic example.test input only.

## Actual validation

- Before fix: accelerator exit1 at the new core regression, ten expected failing assertions for the initial three cases. No claim that the whole before suite passed.
- Expanded regression before the remaining three fixes: one test, nine failures, exit1.
- Final Core:303 tests debug (final accelerator) and release, zero failures, command exits0.
- Final focused native debug: WorkflowEditorTests and OfflineSetupDiagnosticsTests,20 tests, zero failures, exit0.
- Earlier native debug/release:20 tests each passed the initial three-case source. Final expanded-source native release NOT RUN; those earlier results are not relabeled as current.
- Final accelerator exit0:106 Python,303 Core debug,132 strict vectors,180 compression round trips,12 CLI benchmark cases,15 inert CUPS ABI,14 inert filter ABI,1 filter-to-discard case.
- Repository preflight and diff check exited0. Manual diff/disclosure reading: fixed diagnostic vocabulary and synthetic fixture only.

Logs: `/tmp/zpl-error-redaction-before-accelerator.log`, `expanded-before.log`, `final-core-release.log`, `final-accelerator.log`, `final-native-debug.log`, `native-debug.log`, `native-release.log`, `preflight.log` (each latter basename shares prefix `/tmp/zpl-error-redaction-`). Full native CI, Linux, GUI/VoiceOver, installed scheduler/helper/administrator and physical printer validation NOT RUN for this slice. No printer I/O, fixture/oracle changes, ledger refresh, merge or publication. Older whole-source baselines and frozen Linux/manual candidates remain historical and unchanged.

## Implementation digests

- `Packages/LabelCore/Sources/LabelCore/ExtractionPlan.swift`: `a239f1f2269462fbbd63835d4bcdf0f09f0bc0e299848d0ddac4a0cfa9b94a48`
- `Packages/LabelCore/Sources/LabelCore/ReferenceWorkflows.swift`: `6a340812e71b0e9eaf5f77f8431066f8903f91d6d84b19aa86fc1c98194d2c20`
- `Packages/LabelCore/Sources/LabelCore/VirtualQueueDefinition.swift`: `4ed0d30da6be7291ee614325a79954a4033e700ad1e6d9e856ca1195edbaef60`
- `Packages/LabelCore/Sources/LabelCore/WorkflowProfileDraft.swift`: `8a7efa2c2c420d166941134e4c403fcb0c9e53009f75334eb1b2da0961bb5504`
- `Packages/LabelCore/Tests/LabelCoreTests/DiagnosticErrorRedactionTests.swift`: `c26b6794f27dc22c18114e7b77ef774274da3ba2fcc583b7d7d096408ad5b020`
