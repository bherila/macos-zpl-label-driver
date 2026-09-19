# Evidence — one shared finishing-preview budget and one accepted load

- Date/time and operator: 2026-09-19, automated Claude session, unattended
- Exact repository commit SHA: `1264c6cad02513e3d97292f81549daf88885a4c4`
  (implementation and regressions). Base: `d6f03d7` on `origin/main`. This
  document is committed separately on the same branch and is the only file it adds.
- Related requirement and acceptance IDs: none claimed. This slice advances no
  acceptance criterion and promotes no ledger record. It fixes issue #97 and adds
  regressions for the new contract.
- Evidence level: **none claimed for the changed code.** The changed code is
  LabelMac Swift and is **uncompiled** in this environment. Nothing below is
  A-level evidence for it; the commands that did run exercise other packages.
- Status: CHANGE RECORDED, NOT VALIDATED HERE. Compile and test evidence must come
  from a hosted `macos-26` run on the pull request.
- macOS/Linux, architecture, Swift, Xcode/SDK, runner image: Linux
  `6.18.44-fc-v37` x86_64 (`x86_64-unknown-linux-gnu`), Swift 6.1.3 release
  toolchain, CPython 3.11.15, `libcups2-dev` present. No macOS, no Xcode, no
  `xcrun`, no macOS runner.
- Application/version and system-dialog versus browser-preview path: none. The
  changed path is the offline `finishing-preview` / `finishing-inspect` CLI and its
  library types. Output stays inert and file-backed.
- Printer model, resolution, firmware family, transport, stock/accessories (no serial):
  none. No printer, transport, queue or device command on any path in this slice.
- Fixture ID/hash and generator version: the new tests read the committed
  `Fixtures/generated/native-vector.pdf` through the real `label-render-worker`.
  They were **not executed** here (see NOT RUN).
- Profile/job-ticket revision/hash: none read or written outside per-test
  temporary directories.
- Explicit hardware/installation authorization and finite label/command budget:
  not required and not requested. Zero labels, zero device commands, zero system
  changes, zero network access.

## Procedure

Issue #97: `FinishingPreviewCommand.run` performed four full accepted-job loads,
each reaching `AcceptedFinishingJob.accept` and re-analyzing the same original PDF
through the layout worker — one for inspection, one inside
`AcceptedFinishingCancellationStore.monitor`, one inside
`AcceptedFinishingAttemptStore`, and one inside `prepare` before rendering. Only
the last is needed to produce the preview. Separately,
`FinishingInspectionCommand.report` took no deadline parameter and started its own
`60 - elapsed` clock while `run` started a second one moments later, so the two
budgets drained in parallel and a document whose single analysis fits inside 60s
could still fail as `timedOut`, attributed to the wrong cause.

The change takes the direction the maintainer preferred — remove the redundant
analyses rather than only account for them — and adds the shared budget the issue
allows for:

1. `FinishingDeadline` (new, `Packages/LabelMac/Sources/LabelMac/FinishingDeadline.swift`)
   is one monotonic budget with fail-closed expiry, shaped after the `Deadline`
   class in `scripts/traceability_report.py` that the maintainer already accepted
   for "one wall-clock budget shared by every step of a single report". It is a
   `Sendable` value on `ContinuousClock`, checks cancellation before expiry, caps
   each reading at `OfflineRenderWorkerProcess.defaultDeadlineSeconds`, and throws
   the existing `AcceptedFinishingJob.Error.invalidLimit` / `.cancelled` /
   `.timedOut` so no caller sees a new error vocabulary. Its clock is injectable
   (module-internal initializer) so expiry is testable without waiting 60 seconds.
2. `ValidatedAcceptedFinishingContext` (in `AcceptedFinishingJobStore.swift`)
   records exactly one verified reopen: catalog root, exact reference and accepted
   job. Its initializer is `fileprivate`, so it can only be produced by
   `AcceptedFinishingJobStore.validatedContext`, which is the existing verified
   `load` path. It is deliberately not delivery, replay, cancellation or
   completion authority, and it is bound to the catalog root that produced it.
3. `AcceptedFinishingCancellationStore.monitor`,
   `AcceptedFinishingAttemptStore.recoveryObservation`,
   `AcceptedFinishingRecovery.inspect`, `AcceptedFinishingJobStore.prepare` and
   `PackedFinishingPreviewExport.write` gained **additive** overloads taking that
   context and/or the shared deadline. Every existing signature is unchanged, so
   callers outside this command — including anything layered on the attempt and
   cancellation stores — keep their own independent reopen and their own
   `deadlineSeconds` parameter.
4. `FinishingInspectionCommand.observe(workerExecutable:deadline:)` takes the
   caller's budget and returns the verified context alongside the same JSON.
   `report(workerExecutable:cancellation:)` is retained unchanged as a wrapper
   that creates a fresh budget, so `finishing-inspect`, `LabelDriverCLI` and
   `FinishingInspectionModel` are untouched.
   `FinishingPreviewCommand.run(workerExecutable:deadline:)` threads one budget
   through inspection, preparation and export.

Preserved deliberately: the catalog-identity check still runs before and after
inspection and still fails with `catalogChanged`; the recovery pass still reads
recorded intent before polling cancellation, so a request recorded between the two
is still reported; absence of intent remains observation only; uncertain
publication and the replay veto are untouched; the preview JSON still reports
`hardwareCompletion: unknown` and `automaticReplayAuthorized: false`.

Behaviour that changes, stated plainly: the accepted record is now read from disk
**once** per `finishing-preview` instead of four times, so a mutation of that
record in the middle of a single preview is no longer detected by a later reopen
within the same command. Nothing was granted by that repetition — each later
reopen could only fail — and the digest check at load time plus the before/after
catalog-identity check still bind the exported preview to the exact verified
record. The three later reopens were the cause of the redundant analyses the issue
asks to remove.

## Expected and observed results

Commands actually run in this environment, from the worktree at
`1264c6cad02513e3d97292f81549daf88885a4c4`:

```sh
python3 scripts/check_repo.py                      # exit 0
python3 -m unittest discover -s scripts/tests      # exit 0
swift test --package-path Packages/LabelCore       # exit 0
python3 scripts/run-accelerator-checks.py          # exit 0
git diff --check                                   # exit 0, no output
```

Observed:

```
Repository preflight passed (links, metadata, milestone files, action pins).
Ran 108 tests in 1.165s
OK (skipped=2)
Executed 313 tests, with 0 failures (0 unexpected) in 5.269 seconds
Cross-language ZPL/PBM/analytic round-trips: 132
Independent ASCII compression round-trips: 180
Finite encoding benchmark CLI cases: 12
Inert CUPS ABI cases: 15
Inert CUPS filter ABI cases: 14
Inert filter-to-discard pipeline cases: 1
PASS: offline accelerator suite. macOS/scheduler/hardware qualification is separate.
```

**None of those four suites compiles or exercises a single line of this change.**
They are recorded only to show that the unrelated Python tooling, the portable
LabelCore engine and the repository preflight are unaffected by it.

The only mechanical check applied to the changed Swift here was a parse-only pass,
`swiftc -frontend -parse`, over each of the ten changed or added files; all ten
parsed. **Parsing is not type checking**: it detects syntax errors and nothing
else. Name resolution, overload resolution, `Sendable` and concurrency checking,
availability and exhaustiveness are all unverified.

## Regressions added (written, not executed here)

In `Packages/LabelMac/Tests/LabelMacTests/FinishingPreviewBudgetTests.swift`:

- `testFinishingPreviewSharesOneBudgetAndAnalysesTheAcceptedOriginalOnce` — the
  combined regression the issue asks for. It runs the whole `finishing-preview`
  command over a non-trivial analysis path (the real vector original, a structural
  border anchor, two extraction regions at two copies, four output labels) through
  a finite pass-through worker script that records each operation flag and execs
  the real worker. It asserts exactly two `--analysis-directory` invocations — one
  for acceptance, one for preparation's page accounting — where the old code would
  report five, and four `--job-directory` renders; that the exported PBM bytes
  equal an independently prepared set; that one deadline read before the command
  is strictly greater than one read after it; and that no attempt or cancellation
  record is published.
- `testFinishingPreviewBudgetSpentDuringInspectionTimesOutBeforePreparation` — the
  focused timeout regression on the new contract. A stepped clock spends thirty
  seconds per reading, so inspection alone exhausts the shared sixty-second
  budget. It asserts `timedOut`, that the acceptance analysis ran but no render
  did, and that no preview directory or staging directory is left behind. Two
  independent clocks would have hidden exactly this.
- `testFinishingPreviewCancellationVetoesPreparationExportAndRecoveryReads` — the
  focused cancellation regression. Cancellation before admission throws
  `cancelled` with zero worker invocations and no output; cancellation after
  inspection makes preparation, recovery inspection and the attempt read all throw
  `cancelled`; an already prepared job still exports nothing under a cancelled
  budget; and no intent or cancellation record is published by any of it.
- `testValidatedFinishingContextIsNotReusableAcrossCatalogs` — a context validated
  against one catalog root is rejected with `contextMismatch` by the job,
  cancellation and attempt stores of another, and by recovery inspection.
- `testFinishingDeadlineIsOneFailClosedBudget` — the budget's own limits: invalid
  and out-of-range seconds are `invalidLimit`, successive readings decrease,
  expiry is `timedOut`, a cancelled budget is `cancelled` rather than a timeout,
  and no reading exceeds the worker maximum.

Whether these tests compile, run or pass is **unknown from this environment**.

## NOT RUN and why

- `swift test --package-path Packages/LabelMac` — **NOT RUN.** Impossible here.
  `Packages/LabelMac/Package.swift` declares `platforms: [.macOS("26.0")]` and the
  target imports `CryptoKit`, `Darwin` and `CoreGraphics`. `swift build
  --package-path Packages/LabelMac` on this Linux toolchain exits 1 with 133
  `error:` lines beginning `no such module 'CryptoKit'`. No shim, stub or
  weakening of the platform declaration was attempted, and none should be.
- `bash scripts/ci-swift.sh` — **NOT RUN.** It requires macOS and `xcrun`.
- Everything the changed code actually does: Core Graphics rendering, the real
  layout/extraction worker child processes, `renameatx_np`/`fsync` export
  durability, macOS file ownership and mode checks. All are macOS-only and unrun.

## Artifacts

No binary artifact is retained. The Linux build log confirming the LabelMac
failure was written to `/tmp/labelmac-build.log` and is not committed; it contains
only compiler diagnostics and repository paths.

## Limitations / next action

The single largest limitation is that the LabelMac Swift in this slice is
**uncompiled**. A hosted `macos-26` run on the pull request is the first
compilation of it and the only source of test evidence; a green Linux result here
says nothing about it. Until that run exists, treat the implementation as
unverified and the five regressions as unexecuted text.

Beyond that: no acceptance ID is claimed or advanced, no ledger record is written
or re-sealed, and `docs/PROGRESS.json`, `docs/SCOPE-STATUS.json`,
`docs/ACCEPTANCE-EVIDENCE.json` and `MANIFEST.sha256` are untouched. Note that
`Packages/` is not exempt from the traceability report's currency rule, so records
citing LabelMac files may need re-sealing after this merges — that is a separate
slice, not this one. macOS printing, the scheduler, installed queues, signing,
USB, the GUI and any GC420d behaviour remain NOT RUN, and nothing here creates
device-write, admission or replay authority.
