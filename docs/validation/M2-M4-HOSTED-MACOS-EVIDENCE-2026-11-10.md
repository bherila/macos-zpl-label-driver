# Hosted-macOS evidence and mutation proofs for M2-AC09, M4-AC02 and M4-AC13 — 2026-11-10

Level A. Resolves the second part of issue #130 under decision D21. Bound to
`3287cc0d941ee42d60c471ba415fc38db7b75c80`, the tip of `main` after #181. The executed evidence below is the
run on `36cb890`, the tip after #180. `3287cc0` differs from `36cb890` only in `docs/test-surfaces.json`,
`docs/VALIDATION-PLAN.md`, `scripts/tests/test_check_test_surfaces.py` and `MANIFEST.sha256` (#181, which
moved these three rows to the `automated-macos` surface), so every Swift source and test is byte-identical and
the run describes the bound tree's Swift. This was checked with `git diff --name-only 36cb890 3287cc0`.

## What executed, and where

- **Unmutated:** `main` push run **42727833058** at `36cb890` (Swift-identical to the bound tree): `repository-preflight`,
  `portable-ubuntu-arm64`, `swift-macos-arm64` and `ci-required` all succeeded. On the hosted `macos-26`
  Apple Silicon runner, `bash scripts/ci-swift.sh` ran the LabelMac suites in debug **and** release with
  **0 failures**: QuartzPDFRendererTests 60 passes (30 tests × 2 configurations),
  QuartzPDFRendererInputSizeBoundTests 6, QuartzPlannedExtractionTests 14, OfflineRenderWorkerTests 32,
  SyntheticInertJobPipelineTests 40 and WorkflowEditorBootstrapTests 46. The specific tests named below each
  passed in both configurations. The hosted `portable-ubuntu-arm64` job ran LabelCore green on the same tree (486 tests, 0 failures when run locally).
- **Mutated, on hosted macOS:** the manual `Compatibility candidates` workflow (which runs the same
  `ci-swift.sh`) was dispatched on throwaway commits that were **never opened as pull requests**, each
  removing a guard. The branch was restored to clean `main` after each run.
- **Mutated, on Linux:** LabelCore guards, run locally with `swift test`.

## Mutation proofs

| Run | Mutation | Tests that failed |
|---|---|---|
| hosted 42720591733 @`5bc0d00` | pixel limit `pixels <= maximumPixels` made unconditional | `QuartzPDFRendererTests.testRejectsInvalidInputAndBoundsBeforeRendering` |
| hosted 42720591733 | `fullPageTarget` 1e9 bound widened to `greatestFiniteMagnitude` | `QuartzPlannedExtractionTests.testNearZeroRegionCannotCreateUnboundedQuartzTransform`, `WorkflowEditorBootstrapTests.testPlannedLabelAdmissionAppliesTheRenderersFullPageTargetBound` |
| hosted 42720591733 | 90° `unrotatedTarget` no longer swaps | `QuartzPlannedExtractionTests.testClockwiseRegionRotationMapsLeftSideToTopWithoutIntermediateRaster` |
| hosted 42720591733 | unconfigured-queue refusal returns `layoutRejected` | `SyntheticInertJobPipelineTests.testReferenceLetterWorkflowRejectsChangedWrongSizedAndUnconfiguredIntake` (actual `layoutRejected`, expected `configurationUnavailable`) |
| hosted 42720591733 | changed-layout refusal returns `configurationUnavailable` | the same test, on the other two cases (actual `configurationUnavailable`, expected `layoutRejected`), plus three other pipeline tests |
| hosted 42720591733 | `reloadForCorrection` planned-label admission removed (#174) | `WorkflowEditorBootstrapTests.testReloadForCorrectionAdmitsTheStoredRevisionsPlannedLabels` |
| hosted 42724264541 @`2debe12` | source-page limit removed at both sites | `testRejectsInvalidInputAndBoundsBeforeRendering`, `WorkflowEditorBootstrapTests.testSourcePageLimitIsAppliedBeforeCreatingDraft`, `testWorkerBootstrapRetainsPageLimitAndCancellation` |
| hosted 42724264541 | encrypted-PDF refusal removed at both sites | `testRejectsPasswordProtectedFixtureAsEncrypted`, `testOfflineCLIReportsEncryptedInputAndWritesNoFinalArtifacts`, `OfflineRenderWorkerTests.testEncryptedFixtureAndTruncatedSourceRemainDistinctThroughWorker`, `OfflineLayoutWorkerTests.testInputAndRequestedPageFailuresRemainSanitized` |
| hosted 42724264541 | input-size guard removed at all three sites | **no test failed.** A real gap, closed by #180 |
| hosted 42727883606 @`1bffaa8` | input-size guard removed at each of the three sites | exactly `QuartzPDFRendererInputSizeBoundTests.testRenderRefuses…`, `testPageBoxRefuses…` and `testDocumentPageBoxesRefuses…`, one per mutation, and nothing else |
| local, Linux | `BitmapLayout` byte-limit guard | `BitmapLayoutTests.testLimitBoundary` |
| local, Linux | `BitmapLayout` multiplication-overflow guard | `BitmapLayoutTests.testRejectsMultiplicationOverflow` |
| local, Linux | placement `.fit` `min` → `max` | two `PhysicalGeometryTests` fit tests |
| local, Linux | 90° source-rect x/y swap | **no test failed** (every rotation test used a region at the origin). Closed by #179: the new asymmetric-region test catches this and four more rotation mutations |
| local, Linux | `ReferenceWorkflows` teach-once refusal type | `ReferenceWorkflowsTests.testLetterAndA4NeverGuessAnUnconfiguredCrop` |
| local, Linux | letter workflow output stock id | `ReferenceWorkflowsTests.testInitialSetUsesOneStockAndDistinctInputGeometry` |

Two rows' mutation sweeps each found a **real coverage gap** that no existing test noticed (the input-size
guard, and the rotation axes). Both were closed by new tests before these records were written.

## Per-row claim, and what is and is not proved

### M2-AC09, resource safety
Implementation cited: `BitmapLayout.swift`, `QuartzPDFRenderer.swift`, `RenderWorkerSupervisor.swift`.

- **Proved by mutation:** pixel limit, byte limit, multiplication overflow, input-size limit at all three
  renderer entry points, source-page limit, encrypted-input refusal.
- **Executed and passing, not mutation-proved:** malformed-input refusal, the worker deadline
  (`testDeadlineTerminatesOwnedWorkerWithoutReturningArtifacts`), cancellation
  (`testCancellationTerminatesOwnedWorkerWithoutReturningArtifacts`), and "no partial default delivery"
  (`testOfflineCLIReportsEncryptedInputAndWritesNoFinalArtifacts` asserts no output file). Removing the
  worker deadline would make its test wait for the 20-minute job timeout, so it was not attempted.
- **Not asserted directly:** "without unbounded allocation" is established by bounding every size before
  allocation, not by a test that measures allocation.

### M4-AC02, extraction geometry
Implementation cited: `PDFPageGeometry.swift`, `ExtractionPlan.swift`, `PhysicalGeometry.swift`,
`QuartzPDFRenderer.swift`, `QuartzPlannedExtraction.swift`.

- **Proved by mutation:** source-rect rotation axes (after #179), placement scale (no hidden stretching),
  the full-page target bound, and the 90° upright-target swap.
- **Executed, not mutation-proved:** the other three right-angle orientations in the Quartz tests, and
  `ExtractionPlan`'s own source-rect derivation beyond the `PDFPageBox` mapping.

### M4-AC13, three reference workflows
Implementation cited: `ReferenceWorkflows.swift`, `ExtractionPlan.swift`, `SyntheticInertJobPipeline.swift`.

- **Proved by mutation:** the teach-once refusal type, the pipeline's two refusal kinds (changed layout,
  unconfigured queue), and the Letter workflow's shared stock id.
- **Executed, not mutation-proved:** the A4 and native workflows' stock id, "distinct input geometry", and
  that a refused intake loads no job (the pipeline test asserts it, but removing that behavior was not
  attempted).
- The cited prior document records a later correction (`68264a6`). The bound SHA above, not that
  document's headline SHA, is the one these records cover.

Recording a row with an "executed, not mutation-proved" clause is a judgement, stated here rather than
hidden: the tests exist and pass, but the bar of "remove the guard, watch a named test fail" is met only for
the clauses listed first.

## Not shown

GUI, installed scheduler, USB transport, physical output and every release gate: NOT RUN.
