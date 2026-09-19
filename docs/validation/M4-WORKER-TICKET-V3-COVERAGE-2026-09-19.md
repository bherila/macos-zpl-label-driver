# M4 — Schema-v3 worker ticket coverage (issue #93, gap 1)

Test-only slice. No production behaviour was changed; no source file under
`Packages/*/Sources/` was modified.

## Environment

- Host: Linux x86_64 (`x86_64-unknown-linux-gnu`), Swift 6.1.3.
- `Packages/LabelCore` builds and tests on this host.
- `Packages/LabelMac` is macOS-only (`platforms: [.macOS("26.0")]`) and **cannot**
  build here. Confirmed, not assumed:
  `swift build --package-path Packages/LabelMac` →
  `error: no such module 'CryptoKit'` (`AcceptedFinishingAttemptStore.swift:1:8`).
- No printer, USB, CUPS queue or device I/O was involved at any point.

## Starting state

Branch `codex/m3-t3-worker-ticket`, based on `origin/main` at `eb70ca7`.

Issue #93 gap 1 is **partly stale**. It states "Nothing tests that branch", but
commit `29b3fb3` ("Bind worker protocol decoding and returned bitmaps", #95)
landed after the issue was filed and already covers three of the four items:

| Issue item | Existing coverage at `eb70ca7` |
| --- | --- |
| v3 ticket carries the margins | `OfflineExtractionWorkerTests.testNonZeroMarginTicketCarriesSchemaVersionThreeAndEveryEdge` |
| zero-margin ticket stays v2 | `OfflineExtractionWorkerTests.testZeroMarginTicketStaysAtSchemaVersionTwoWithoutMarginKey` |
| `OfflineConversionTicket` round-trips v3 | `OfflineExtractionWorkerTests.testEmittedTicketRoundTripsThroughOfflineConversionTicket` |

Those were left untouched. This slice adds only what was genuinely missing:
the **negative** cases, and typed-error assertions for them.

## Commands and exact results

| Command | Result |
| --- | --- |
| `python3 scripts/check_repo.py` | PASS — "Repository preflight passed (links, metadata, milestone files, action pins)." |
| `python3 -m unittest discover -s scripts/tests` | PASS — Ran 161 tests, `OK (skipped=2)` |
| `swift test --package-path Packages/LabelCore` | PASS — Executed 327 tests, 0 failures |
| `python3 scripts/run-accelerator-checks.py` | PASS — "PASS: offline accelerator suite." (132 round-trips, 180 ASCII, 12 benchmark, 15 CUPS ABI, 14 filter ABI, 1 pipeline) |
| `git diff --check` | clean, exit 0 |
| `swiftc -frontend -parse` on both changed files | exit 0 each |
| `sha256sum -c MANIFEST.sha256` | see below |

`swiftc -frontend -parse` is a **syntax check only**. It is not type checking.
The LabelMac tests added here are therefore **uncompiled and unrun**.

## Branches now covered

Emission-side gates, in `ExtractionPlanTests` (LabelCore — actually executed here):

- A non-zero `outputMargins` on a `schemaVersion: 2` profile is rejected with
  `ExtractionPlanError.invalidProfile`.
- Margins that consume the full stock width, and separately the full stock
  height, are each rejected with `ExtractionPlanError.invalidProfile`.
- Non-finite (`nan`, `+inf`, `-inf`) and negative edges are rejected by
  `OutputMargins.init` with `PagePlacementError.invalidMargins`, on each of the
  four edges independently.
- An admitted margin survives planning and reaches `PlannedExtractionLabel`,
  which is the value the worker ticket serializes.

Parsing-side gates, in `OfflineExtractionWorkerTests` (LabelMac — NOT run here):

- A negative edge on the emitted v3 ticket → `PagePlacementError.invalidMargins`.
- Margins leaving no printable area → `OfflineConversionTicket.TicketError.malformedJSON`.
- Margins present at `schemaVersion: 2` → `TicketError.malformedJSON`.
- A v3 ticket with `outputMargins` stripped → `TicketError.malformedJSON`
  (refused, not defaulted to zero).
- A non-finite margin spliced in as a raw JSON literal (`1e400`, `-1e400`),
  which `JSONSerialization` cannot itself produce.

These negative tickets are built by mutating a **genuinely emitted** ticket from
`OfflineExtractionWorker.ticketJSON`, not a hand-written JSON blob, so the
rejected shapes stay tied to the real wire form.

## Deliberate weakening of one assertion, and why

The raw-literal non-finite test accepts either `TicketError.malformedJSON` or
`PagePlacementError.invalidMargins`. `OfflineConversionTicket.init(jsonData:)`
can reject `1e400` at `JSONDecoder` (→ `malformedJSON`) or admit an infinity
that `OutputMargins.init` then refuses (→ `invalidMargins`), and which one fires
depends on Foundation's non-conforming-float behaviour, which I could not
observe on this host. The assertion still requires a **typed** rejection from a
closed set of two and still fails on success, on clamping, and on any untyped
error. It should be tightened to the single exact error once it has run on
macOS CI.

## Observation (not a defect, not fixed)

`OfflineConversionTicket.init(jsonData:)` is documented around `TicketError` but
also propagates `PagePlacementError`, `MillimetersError` and other LabelCore
geometry errors from its component initializers (lines 102, 131, 133, 147). This
is a pre-existing, consistent pattern that predates the v3 margin work rather
than something v3 introduced, so it was left alone and is recorded here only so
the two error domains crossing this boundary are not a surprise to a caller.

No defect was found in the v3 emission or parsing logic itself.

## NOT RUN

- `swift test --package-path Packages/LabelMac` — **NOT RUN**. macOS-only
  package; `CryptoKit` is unavailable on this Linux host. Every LabelMac test
  added in this slice is therefore unvalidated: not compiled, not type checked,
  not executed. Hosted macOS CI is the first thing that will compile them.
- `bash scripts/ci-swift.sh` — **NOT RUN**. Requires a Mac.
- Type checking of any changed LabelMac file — **NOT RUN** (`-frontend -parse`
  is syntax only).
- Core Graphics / `QuartzPDFRenderer` margin clipping behaviour — **NOT RUN**
  here; unchanged by this slice and covered elsewhere on macOS.
- Any physical print, device I/O, USB enumeration, CUPS queue exercise,
  scheduler interaction, GUI run, signing or installation — **NOT RUN**, and out
  of scope for a test-only slice.
- Issue #93 **gap 2** (security review of the v3 parsing path) — **NOT ADDRESSED**.
  This slice closes gap 1 only.

## Claims

This slice claims no acceptance criterion. A Linux run of LabelCore does not
validate macOS printing, Core Graphics, USB, signing or the GUI, and no result
here is evidence of physical output.
