# Workflow editor UI defects from the supervised GUI session — 2026-09-19

Level A for the added regressions; **no GUI evidence is claimed by this slice**. Every fix here is
source reasoning plus hosted compilation. None of it has been seen on screen, and only a supervised
macOS session can confirm any of it. No acceptance ID advances and no evidence level is promoted.

## Provenance of the reports

A supervised local session drove the real UI on an M1 MacBook Pro (macOS 27.0 / 26A428) against a
locally built `Label Printer Driver Setup.app`, with its worktree at `d6f03d7`. The seven defects
below are **relayed observations**, not measurements taken here. The validation document that
session wrote is uncommitted on that machine and is not in this repository.

## What is fixed

**(e) The approval cluster could not be reached when both images were shown.** The cluster is emitted
unconditionally — confirmed by reading the view tree — so the cause had to be positional. The pane is
hard-capped at `.frame(height: 720)` and sits inside the setup window's own `ScrollView`, so zooming
or widening the window grants it no extra height; the maintainer's "zoom proves it is not clipping"
test could not discriminate. `previewView` was `.frame(maxWidth: .infinity, minHeight: 240)` with **no
maximum** around a `scaledToFit()` 4x6 bitmap, so a wider pane made the preview taller. Two changes,
either of which alone would help and which together are robust to every candidate mechanism:
`previewReviewControls`, the error line and the action row now sit below the `ScrollView` as pinned
siblings, and the preview image is capped at `maxHeight: 300`, matching the cap the source reference
already had. Controls that commit a revision no longer depend on scroll position.

**"Show Source Page" never changed and could not dismiss.** The label was a string literal and the
action only ever re-rendered, so there was no toggle at all: once shown, the reference stayed until a
different region was selected or the document was reopened, which is exactly the reported stickiness.
The label is now derived from `model.sourcePreview` and the button clears it when one is displayed.
Hiding is inert — it drops a rendered image and performs no worker or device work.

**(d) A focus change discarded the reviewed preview with nothing changed.** Two independent guards,
because the two paths fail differently.

At the model layer, `updateSelectedRegion` returns early when the requested rectangle equals the one
stored. This does **not** weaken `replaceDraft`'s contract that a successful mutation invalidates
review even when values are later undone: that contract defends a sequence of real edits, and each
call in such a sequence still changes the draft. It cannot affect the existing
`testUnsavedUndoCannotResurrectReviewOrAcceptAnOldDisplayedGeneration` for a stronger reason than
expected — that test drives `setSelectedRotation`, a different method, and both of its calls are
genuine mutations. The comparison must precede `editableDraft()`: on a saved revision that returns
`store.correctionDraft(for:)` at revision `latest + 1`, so comparing drafts afterwards can never
detect the no-op and would instead fork a revision and clear `isSaved`.

At the text layer, `MeasurementField` commits nothing when the field's text still equals what the
model formats to. This is necessary because the millimetre round trip does not preserve exact
rectangles: the field displays a value rounded to two fraction digits, so re-committing the displayed
text can produce a rectangle differing in its last bits, which the model-level guard would — correctly
— treat as a real change. Asking "was this field edited at all" is the question that matters.

**(c) Decimal entry silently lost the fraction.** `TextField(value:format:)` over a `Binding` whose
`set` committed on every successful parse made each keystroke a committed edit. Typing `101.6`
committed 101 at `101`; at `101.` the parse still yielded 101, the `get` re-rendered the field from
the model as `101`, and the pending fraction was discarded. `MeasurementField` holds in-progress text
in its own state and commits on submit or focus loss. Parsing and formatting share one locale-aware
`FloatingPointFormatStyle`, so a decimal-comma locale reads and writes exactly as before. This is
also the mechanism behind the documented "shrink width and height first" workaround.

**(b) Pluralization.** `unreviewedRegionSummary` and `labelRegionSummary(page:regions:)` moved to the
model, which is what makes them testable at all — an inline view string is not. Both now agree with
their count, and `require`/`requires` agrees too. Explicit conditionals rather than automatic grammar
agreement, because AGA behaviour cannot be verified on this host and the app carries no other
localization.

**(f) The USB vendor ID was number-formatted.** SwiftUI interpolation of a `UInt16` applies the
viewer's locale format, rendering VID `0x0A5F` as `2,655` — a thousands separator inside an
identifier, matching nothing a USB tool prints. `USBPrinterObservation.interfaceLabel` formats hex,
as `system_profiler` and the USB-IF registry do, so the value can be cross-checked as written. It is
deliberately **not** `description`: `RedactedDiagnosticValue` redacts that so these values never
reach a log, and the test asserts the redaction still holds.

## What is NOT fixed, and why

**(a) Raw enum case names as user-facing errors — already fixed in-tree; not reproducible from
source.** `report(_:)` was `lastError = String(describing: error)` verbatim from `55a9ef5` through
`56fdc7b`, which produces exactly the reported `editSnapshotChanged` and `invalidNormalizedRegion`.
`78acd9b` (#100, 2026-09-18) replaced it with the mapping now in place, which handles both domains.
`78acd9b` **is an ancestor of `d6f03d7`**, the session's worktree HEAD, so the driven bundle was
built from older sources than the worktree it sat in. That is consistent with the session's own note
that all four running processes reported `isRunningFromDevPath: true` and the driven window was never
positively tied to the hashed bundle.

This cannot be proven retroactively, which is itself the defect worth fixing: `artifacts/` accumulates
one `setup-app.XXXXXX` directory per build with nothing pruning or marking the newest, and
`Info.plist` carried a hard-coded `0.1.0`/`1` with no provenance whatsoever. `scripts/build-local-app.sh`
now stamps the source revision (plus a `-modified` suffix for a dirty tree) into `CFBundleVersion` and
`LabelBuildRevision` before codesign seals the plist, and prints it. A future sighting can be tied to
a commit.

The one genuine test gap is closed regardless: the `PageGeometryError`/`PhysicalGeometryError` branch
of `report(_:)` — the source of the second observed string — had no coverage anywhere in the suite.
Three rows are added to the existing table.

**No claim is made that (a) is resolved.** If it recurs on a bundle whose stamp is at or after
`78acd9b`, this analysis is wrong. The decisive probe is
`strings -a "<app>/Contents/MacOS/label-printer-setup" | grep -F "The draft changed. Review the current values"`
on the exact executable driven — present means post-`78acd9b` and the stale-bundle explanation dies.

**(g) Transient layout collapse on new-window creation and on opening a PDF.** Not characterised and
deliberately untouched. Speculatively "fixing" an unreproduced layout glitch would be a guess. It
needs a live reproduction and should be tracked separately.

## Tests

Six new LabelMac cases plus three rows on the existing `report(_:)` table: identical-rectangle commit
preserves review, preview and generation; a no-op on a saved revision does not fork a revision or
clear `isSaved`; a real edit still invalidates; the no-op guard does not short-circuit the stale
edit-binding check that precedes it; both plural summaries agree with their counts and never read
`1 regions`; and `interfaceLabel` carries no grouping separator while `description` stays redacted.

## Validation

Linux x86_64, Swift 6.1.3, CPython 3.11. All exit 0:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | 157 tests, OK (skipped=2) |
| `swift test --package-path Packages/LabelCore` | 326 tests, 0 failures |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/run-accelerator-checks.py` | PASS |
| `bash -n scripts/build-local-app.sh` | syntax OK |
| `swiftc -frontend -parse` on all changed Swift | clean |
| `git diff --check` | clean |

**NOT RUN, and this is the dominant risk in the slice:** `swift test --package-path Packages/LabelMac`
cannot run on Linux — the package declares `platforms: [.macOS("26.0")]` and imports CryptoKit, Darwin
and CoreGraphics. `bash scripts/ci-swift.sh` needs macOS and `xcrun`. **Every line of changed SwiftUI
and every new test here is uncompiled and unexecuted.** `swiftc -parse` is syntax only — not type
checking, overload resolution or `Sendable` checking. `MeasurementField` uses `@FocusState`, the
two-parameter `onChange`, and `Double.init(_:format:)` against `FloatingPointFormatStyle`, none of
which is verified. The hosted `macos-26` run is the first compilation; expect to iterate.

`scripts/build-local-app.sh` runs only on macOS, so the `plutil` stamping is likewise first executed
by hosted CI.

## Scope

No printer I/O, USB write, calibration, scheduler, installation or privileged action is introduced.
Hiding the source reference and the no-op guard both *reduce* work performed. No rendering, encoding,
review-gate, profile, ticket or device-control semantics change. GUI, installation, scheduler, USB,
printer and release remain NOT RUN.

This slice changes `Packages/` and `scripts/`, neither exempt, so it stales `M2-AC04` and `M2-AC13`;
the re-seal is owed after the last non-exempt change in this batch.
