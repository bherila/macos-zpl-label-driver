# Ledger records for M4-AC03, M4-AC04, M4-AC05, and four withdrawn claims — 2026-11-09

Level A. Resolves part of issue #130 under decision D21: for each checked row with no ledger record,
**record it** where executed evidence exists at the prescribed level, otherwise **uncheck it**. Unchecking
withdraws an unsupported claim; the criterion itself is unchanged. The per-row analysis was done by a
read-only agent and **every factual claim below was re-verified against the tree** before use.

Bound to `3d5f3458555d7baded51740a3a3628b26f62c8ca`, the tip of `main` after #176.

## Recorded (3)

All three run on Linux in LabelCore. At the bound tree: `swift test --package-path Packages/LabelCore`
executed **485 tests, 0 failures**; the five suites below executed LabelOrderPlanTests 8,
ExtractionPlanTests 10, WorkflowProfileDraftTests 10, StructuralMatchingTests 4 and
StructuralAnchorAnalyzerTests 5, all with 0 failures. Hosted `portable-ubuntu-arm64` ran the same suite on
every merged slice (most recently run 42714971015, green).

| Row | Implementation cited | Tests and prior evidence cited | Asserts |
|---|---|---|---|
| `M4-AC03` | `LabelOrderPlan.swift`, `ExtractionPlan.swift`, `WorkflowProfileDraft.swift` | `LabelOrderPlanTests`, `ExtractionPlanTests`, `WorkflowProfileDraftTests`, `M4-DRAFT-ORDER-ACCOUNTING-2026-09-15.md` | `testMultiplePagesRegionsAndCopiesUseExplicitOutputOrder` asserts exactly `[A,B,C,A,B,C]` collated and `[A,A,B,B,C,C]` uncollated; `testGlobalReorderSurvivesJSONRoundTripAndPlannerCopies` asserts `[B,A,C,B,A,C]` |
| `M4-AC04` | `ExtractionPlan.swift`, `StructuralAnchorAnalyzer.swift` | `StructuralMatchingTests`, `StructuralAnchorAnalyzerTests`, `ExtractionPlanTests`, `M4-STRUCTURAL-ANALYSIS-2026-09-15.md` | `testChangedAndAmbiguousLayoutsFailBeforeAnyPlan` asserts `.missingAnchor` and `.ambiguousAnchor` specifically; changed geometry gives `.inputGeometryMismatch`; typed errors are the "useful reasons" |
| `M4-AC05` | `ExtractionPlan.swift`, `WorkflowProfileDraft.swift` | `ExtractionPlanTests`, `WorkflowProfileDraftTests`, `M4-DRAFT-ORDER-ACCOUNTING-2026-09-15.md` | `testEveryPageMustBeAccountedForAndExplicitSkipIsReported` asserts `.unaccountedSourcePage(2)` and `skippedPages == [.init(sourcePage: 2, reason: .customsForm)]`; `testChangedGeometryAndMissingPagesFailBeforePlanningOutput` asserts `.missingSourcePage(2)` |

### Proved by mutation

Each guard was removed in turn, the named suite run, and the file byte-restored (`cmp`):

| Mutation | Result |
|---|---|
| `LabelOrderPlan.swift` `if collated` → `if !collated` | `LabelOrderPlanTests.testCollated`, `testUncollated`, and `ExtractionPlanTests.testMultiplePagesRegionsAndCopiesUseExplicitOutputOrder` fail |
| `ExtractionPlan.swift` ambiguous-anchor guard (`candidates.count == 1`) removed | `StructuralMatchingTests.testChangedAndAmbiguousLayoutsFailBeforeAnyPlan` fails |
| `ExtractionPlan.swift` missing-anchor guard removed | `testChangedAndAmbiguousLayoutsFailBeforeAnyPlan` and `testRequiredAnalysisIsDistinctFromObservedNoMatch` fail |
| `ExtractionPlan.swift` unaccounted-page guard disabled | **The test process crashes** (`Fatal error: page accounting checked`, signal 4, exit 1) on the next line's `preconditionFailure`, not an assertion failure. A first sweep misread this as "no failure" because it only looked for assertion lines; the raw run shows the crash. Detection is real, and the guard is the only thing standing between an unaccounted page and a crash |

### Wording limits stated, not hidden

- `M4-AC03` says "shared ordering examples", which has no referent in the tree. The tests assert **explicit
  literal sequences**, and that is what is evidenced.
- `M4-AC04`: the structural analyzer is border-only per `M4-STRUCTURAL-ANALYSIS-2026-09-15.md`; barcode and
  dark-block anchors are not qualified here.

## Unchecked (4): the evidence does not support the wording

| Row | Why |
|---|---|
| `M2-AC02` | "…or qualified input raster" has no support: no raster input type exists. The core claim (the render API accepts only original PDF bytes) is structural and untested against substitution. |
| `M4-AC07` | "Detection uses only analysis inputs" is structural only; the `previewPBM == bitmap.pbmData()` assertion is tautological because the property is defined as the same call. |
| `M4-AC08` | Evidence covers **unknown fields** (`rawZPL`, `filePath`, `embeddedDocument` keys give `.unknownField`). Values are different: `WorkflowProfile.isSafeIdentifier` rejects only whitespace, control characters and length over 128, so `../etc/x` or `^XA^FDx^XZ` **are accepted** as an id. They look inert: the profile store names files by a digest of the id, and no ZPL encoder reads profile ids. But no test shows that, so "no imported … paths … accepted" is not demonstrated. A test asserting ids never reach a file name or ZPL would make this recordable. |
| `M5-AC12` | The row cites no document. The 2026-09-15 setup-app signing document supports the default and the Developer-ID refusal (exit 2, no fallback), but "any selected **future** Developer-ID mode" has no referent, since the refusal is unconditional, and no unit test asserts the refusal. |

Narrowing any of these rows' wording would lower an acceptance criterion; that is a maintainer decision and
is **not** made here.

## Left as reported, for a follow-up (4)

- `M2-AC09`, `M4-AC02` and `M4-AC13` are recordable, but only with LabelMac tests, which build on macOS only.
  They need a hosted `macos-26` run recorded as evidence, as `M2-AC05` and `M3-AC03` did.
- `M2-AC12` is **supported, not unsupported**, and an earlier statement of mine was wrong. DECISIONS.md D21
  says it "is expected to be unchecked"; that rested on an assumption I did not check. The cited document
  (`M2-PERFORMANCE-BASELINE-2026-09-15.md`) names the machine (MacBookPro18,3, macOS 26.6.2, Apple Silicon),
  a release build and hashed fixtures, and records latency, peak memory, output bytes and throughput, which is
  what the row asks for. It is nonetheless **not recordable at the current tip**: the measurement was taken
  at `6fcb63e`, and a record bound to today's tip would claim a baseline for code it never measured. Repeating
  the harness on the Mac at the tip is the way to qualify it. D21's wording needs correcting in a source slice.

All four stay checked with no record, and the diagnostic keeps reporting them. Issue #130 stays open for them.

## Not shown

macOS, GUI, installed scheduler, USB transport, physical output and every release gate: NOT RUN.
