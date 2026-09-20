# Evidence — M3-AC03 control coverage and M2-AC05 exact preview, on a hosted macOS run

- Date/time and operator: 2026-09-20, automated maintainer session
- Exact repository commit SHA: `1471eda37aa4f03415a8f89097bd362464efcc84`
- Related requirement and acceptance IDs: F03, F07, M3-AC03, M2-AC05
- Evidence level: A
- Status: PASS
- macOS/Linux, architecture, Swift, Xcode/SDK, runner image: GitHub-hosted
  `macos-26` ARM runner, workflow `CI`, job `swift-macos-arm64`, run
  `35497764230`; `bash scripts/ci-swift.sh` in the repository's pinned
  toolchain. Local corroboration on macOS 27.0 (26A428), arm64, Swift 6.4.
- Application/version and system-dialog versus browser-preview path: portable
  `LabelCore` protocol tables and encoders, plus the `LabelMac` framed finishing
  producer and the two offline render parents. No system print dialog is
  involved and no queue was installed.
- Printer model, resolution, firmware family, transport, stock/accessories: none.
  No device was opened, no transport was used and no byte reached a printer. The
  GC420d reference profile is a documented arithmetic and protocol oracle here.
- Fixture ID/hash and generator version: committed generated fixture manifest,
  `Fixtures/generated/manifest.json`; the framed-output test renders
  `Fixtures/generated/native-vector.pdf` through the real private render worker.
- Profile/job-ticket revision/hash: synthetic in-test profiles and version-1
  offline tickets. No installed profile was read or written.
- Explicit hardware/installation authorization and finite label/command budget:
  not required and not requested. Zero labels, zero device commands, zero system
  changes.

## Why a hosted run was the gate

`Packages/LabelMac` does not build on Linux, so every earlier batch could bind only
criteria whose every implementation owner is portable. Issue #103 recorded the
consequence for `M3-AC03`: six of its seven control categories were already covered
by executed `LabelCore` evidence, and supported finishing was not, because the
production finishing route lives in `FinishingFramedOutput.swift`. The same
argument held for `M2-AC05`, whose byte-for-byte enforcement is in
`WorkerBitmapBinding.swift`.

This run is the first `macos-26` execution recorded as evidence against a merged
`main` that contains all of today's slices. `scripts/ci-swift.sh` runs
`xcrun swift test --package-path Packages/LabelMac` in both debug and release, so
the `LabelMac` suites named below are executed, not merely compiled.

## Procedure

Hosted, on the merged commit:

    bash scripts/ci-swift.sh          # LabelCore and LabelMac, debug and release

Locally, for the two mutation proofs below, on the same commit:

    xcrun swift test --package-path Packages/LabelMac
    xcrun swift test --package-path Packages/LabelMac --filter ProfileBoundFinishingJobPlanTests

## Expected and observed results

### M3-AC03 — protocol mapping covers all seven categories with cited semantics

The oracle is the criterion's own list. `ZPLControlProtocol.documentedControls` is
keyed by `ZPLDocumentedControl.Kind`, which is `CaseIterable`, and
`ZPLControlProtocolCoverageTests.testEveryDocumentedKindHasCitedRangeAndIndependentModelLimits`
asserts `Set(rows.keys) == Set(Kind.allCases)`. The mapping is therefore exhaustive
by construction rather than by a list someone maintained by hand:

| Criterion category | Kind(s) | Command | Source |
|---|---|---|---|
| Speed | `printRate` | `^PRp,s,b` | R45 |
| Darkness | `absoluteDarkness` | `^MD0/~SD` | R45 |
| Thermal method | `directThermal`, `thermalTransfer` | `^MTD/^MTT` | R45 |
| Tracking | `gapTracking`, `continuousTracking`, `blackMarkTracking` | `^MNY`, `^MNN/^LL`, `^MNM,offset` | R45, R46 |
| Dimensions | `printWidth`, and `^LL` under continuous tracking | `^PW`, `^LL` | R45, R46 |
| Offsets | `labelHome`, `labelShiftLeft`, `labelTop` | `^LHx,y`, `^LS`, `^LT` | R45 |
| Supported finishing | `tearOff`, plus `ZPLControlProtocol.qualifiedFinishingControls` | `^MMT`, `^MMC/^MMD/~JK`, `^MMP,N/^MMP`, `^MMR` | R45 |

Every row is asserted to carry a `sourceID` of `R45` or `R46`, a non-empty
implemented range, non-empty independent model limits and non-empty notes. Both
identifiers resolve in `docs/REFERENCES.md`, which is why that file is bound as an
implementation path: without it the phrase "cited semantics" has nothing to cite.

The finishing category is the one this run adds. `ZPLFinishingControlLiteral` is the
single authoritative table, and `FinishingFramedOutput` derives from it — it does not
restate it. Two independent tests hold that:

- `ZPLControlProtocolCoverageTests.testNoEmittingSourceRestatesAFinishingLiteral`
  reads the five emitting sources as text, including the `LabelMac` one, and fails on
  a re-hardcoded literal. This runs on every host, including Linux.
- `ProfileBoundFinishingJobPlanTests.testFramedFinishingOutputPreservesCutFilesPeelWaitsAndOneExpandedQuantity`
  executes the producer over all four modes and compares the complete step list
  against an independent oracle that restates the literals deliberately. This needs
  macOS, and is what the hosted run supplies.

**Mutation proof.** In `FinishingFramedOutput.prepare`, the line

    let mode = ZPLFinishingControlLiteral.framedMode(of: policy).line

was replaced by `ZPLFinishingControlLiteral.offlineInspection(of: job.plan.mode).line`
— the bounded-inspection mapping, which yields `^MMC` for cut and `^MMP` for peel
instead of `^MMD` and `^MMP,N`. Result: `9 tests, 3 failures`, all three in
`testFramedFinishingOutputPreservesCutFilesPeelWaitsAndOneExpandedQuantity`
(`ProfileBoundFinishingJobPlanTests.swift:236`, `:337`, and a `payloadMismatch`
raised at `FinishingDeliveryTracker.swift:41`). The file was then restored
byte-for-byte and the restoration confirmed against a digest taken before the edit.

### M2-AC05 — preview reconstruction matches encoder input byte-for-byte

The enforcement is one line in `WorkerBitmapBinding.validate`:

    guard try encoder.diagnosticFormat(bitmap) == output.zpl else { throw Error.invalidBinding }

The preview PBM is unpacked into a `MonochromeBitmap` and repacked through the
graphics encoder, and the result must equal the worker's ZPL exactly. Both render
parents call it — `OfflineRenderWorker.swift:248` and `OfflineExtractionWorker.swift:66`
— so neither can take worker output that fails it.

**Mutation proof.** That guard was deleted and the full `LabelMac` suite run:
`Executed 440 tests, with 2 failures`. The two are named for the property:

- `OfflineRenderWorkerTests.testParentRejectsWorkerBitmapAndZPLSubstitutionDespiteMatchingByteCounts`
  (`OfflineRenderWorkerTests.swift:199`)
- `OfflineExtractionWorkerTests.testReturnedBitmapRequiresExactCanvasPaddingAndDiagnosticEncoding`
  (`OfflineExtractionWorkerTests.swift:29`)

Both fail with `XCTAssertThrowsError failed: did not throw an error`. The first
drives an inert stub worker that returns a preview differing from its ZPL by a single
flipped byte while both byte counts still match the declared metadata, which is
precisely the substitution the criterion forbids. The file was restored byte-for-byte
and the restoration confirmed by digest.

This proof is worth stating plainly because the obvious place to look —
`WorkerBitmapBindingTests.swift` — does **not** cover the guard. It has one test, for
dimension and allocation bounds, and its positive case still passes with the guard
removed. The coverage is real but it lives in the two parent suites, and a reader
checking only the unit named after the file would conclude the opposite.

### A note on the cited 2026-09-17 document

`M3-AC03`'s record cites `docs/validation/M3-DOCUMENTED-CONTROL-ENCODING-2026-09-17.md`, which says in its
own third line that "M3-AC03 remains unchecked". That was true of the tree it describes and is kept rather
than paraphrased away: it is the original validation document for the documented control encoding, and the
record is more auditable citing the partial work it builds on than pretending the coverage arrived whole.
What closes the criterion is this document plus the four executed test files, not that one.

Two other partial documents — `M3-CONTROL-COVERAGE-AUDIT-2026-09-17.md` and
`M3-FINISHING-NORMAL-CONTROL-ENCODING-2026-09-17.md` — are deliberately **not** cited. The first is an audit
of PR #81, where `ZPLControlProtocol.gc420dBaseline` held two entries and most of the criterion's categories
were listed as unimplemented. It accurately describes a tree that no longer exists, and citing it as evidence
for a pass would misrepresent it.

## Artifacts

Workflow run <https://github.com/bherila/macos-zpl-label-driver/actions/runs/35497764230>
(`CI`, event `push`, head `1471eda37aa4f03415a8f89097bd362464efcc84`). Jobs:
`repository-preflight` success, `swift-macos-arm64` success (07:46:42Z to 08:01:53Z),
`ci-required` success.

Suite totals, each run twice because `scripts/ci-swift.sh` tests in debug and release:

| Package | Configuration | Result |
|---|---|---|
| `LabelCore` | debug | `Executed 346 tests, with 0 failures (0 unexpected) in 1.822s` |
| `LabelCore` | release | `Executed 346 tests, with 0 failures (0 unexpected) in 0.935s` |
| `LabelMac` | debug | `Executed 440 tests, with 0 failures (0 unexpected) in 184.101s` |
| `LabelMac` | release | `Executed 440 tests, with 0 failures (0 unexpected) in 159.610s` |

The four load-bearing tests each passed in both configurations:
`ZPLControlProtocolCoverageTests.testEveryDocumentedKindHasCitedRangeAndIndependentModelLimits`,
`ZPLControlProtocolCoverageTests.testNoEmittingSourceRestatesAFinishingLiteral`,
`ProfileBoundFinishingJobPlanTests.testFramedFinishingOutputPreservesCutFilesPeelWaitsAndOneExpandedQuantity`,
`OfflineRenderWorkerTests.testParentRejectsWorkerBitmapAndZPLSubstitutionDespiteMatchingByteCounts` and
`OfflineExtractionWorkerTests.testReturnedBitmapRequiresExactCanvasPaddingAndDiagnosticEncoding`.

The `LabelMac` total of 440 is the same figure the local mutation runs reported, so the two mutation proofs
below were taken against the same suite this run executed. No artifact in this run contains a device identifier,
a serial number or any digest of one.

## Three findings that contradict issue #103

The issue describes a tree from 2026-09-17. Verified against the bound commit before
building anything, per the rule that an issue describes a past tree:

1. **The duplication #103 named as root cause is already fixed.** The issue says the
   production sequences "exist only in `FinishingFramedOutput.swift`", duplicated from
   the LabelCore mapping. They do not. `grep -c` for those literals in that file returns
   `0`; they live in `ZPLControlProtocolCoverage.swift` and the LabelMac file derives
   from it, with a test that fails if either side re-hardcodes one. The change #103
   offered as a "worth considering while fixing" aside has since been made.
2. **F04 does not follow automatically.** The issue says "F04 follows automatically,
   since M3-AC01 and M3-AC02 are already satisfied with current digest-bound records."
   The ledger before this slice held exactly two records, `M2-AC04` and `M2-AC13`.
   `M3-AC01` and `M3-AC02` have no records at all and both boxes are unchecked, so F04
   remains pending on both after this slice. This is stated rather than quietly
   left for a reader to discover from the report.
3. **`M3-AC04` is not closed by this run, though #103's set implies it.** Its criterion
   is that ordinary output carries no reset, calibrate, save, erase or firmware command.
   `LabelCore` asserts that over the control encoders — `ZPLControlEncoderTests`
   and `ZPLDocumentedControlEncoderTests` between them forbid `^J`, `~J`, `^JU`, `~JC`,
   `~JA`, `~DG`, `^PQ` and more — but nothing asserts it over the bytes
   `FinishingFramedOutput` actually assembles. Every component of those bytes comes
   from a covered source, and that is an argument from composition, not an executed
   test. Closing it needs one added assertion in the framed-output test, which is a
   source change and therefore a separate slice.

## Limitations / next action

This run establishes level A for two criteria and nothing beyond it. In particular:

- **It is not hardware evidence.** `M3-AC10` still owns observed cut and peel behaviour
  at level H on installed accessories, and stays open. No cutter or peeler exists on the
  reference unit, and no label was printed.
- **It is not installation or integration evidence.** `M3-AC07` through `M3-AC09` are
  level I and need real processes against an installed queue.
- A hosted macOS result does not validate a physical label printer or a clean retail Mac
  installation.
- The five remaining criteria that #103 listed as blocked on the same run — `M2-AC01`,
  `M2-AC06`, `M3-AC01`, `M3-AC02`, `M3-AC04` — are not claimed here. Each needs its own
  binding argument and its own check that the criterion holds; asserting five more on
  the strength of one green run is the shortcut this ledger exists to prevent. They stay
  in #103.

Next action: the `M3-AC04` assertion above, as a source slice, followed by its own
re-seal.
