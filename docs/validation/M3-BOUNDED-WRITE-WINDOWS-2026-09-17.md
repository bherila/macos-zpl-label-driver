# M3 — bounded delivery write windows and invalid accounting

## Requirements and independent constraints

Additional partial M3-AC05/09/12 and M2-AC09 automated implementation, not
installed scheduler or physical acceptance. Branch: `codex/m2-ascii-graphic-compression`,
follow-on commit on PR #81. No transport endpoint, queue or device I/O is added.

The nearest independent constraints are exact immutable payload/order binding
and truthful uncertainty: a smaller write window must neither skip/repeat bytes
nor accept a count exceeding the actual offered buffer. A sink violating its
byte-count contract provides no evidence that the call wrote nothing, so it
must not authorize automatic replay even when the known accepted prefix is zero.

Previously every short write copied the entire remaining payload. The fixed
writer offers at most 64 KiB per call, a project buffer budget rather than a
printer-memory or packet-size limit. Each return count is checked against that
specific window. Negative/oversized counts become `uncertain` with the known
accepted prefix and return `invalidWriteCount`. A conforming zero-byte return
or thrown-before-write failure retains the existing safe-before-send semantics;
a conforming failure after a known prefix remains uncertain. No resumption or
replay is introduced. Existing tracker start/binding checks still run before
any sink side effect.

## Actual regression evidence

- Old-code focused run: eight tests, **12 assertion failures**, exit 1. A
  1 MiB + 7 byte payload was offered whole rather than within the buffer budget;
  invalid first-call counts became retryable failure. Later invalid counts lost
  their distinct accounting error. The negative evidence is retained privately.
- Fixed `swift test --package-path Packages/LabelCore --filter BoundedDeliveryTests`:
  eight tests, zero failures, exit 0. One large immutable synthetic payload is
  reconstructed exactly across 49,153-byte partial writes, retaining its profile
  snapshot; injected failure after the first prefix is uncertain. Invalid counts
  before/after a known prefix never authorize replay. Existing zero-write and
  stale/binding tests remain green.
- Required `bash scripts/ci-swift.sh`: PASS, exit 0 within the 900-second bound.
  86 Python / 188 Core / 265 Mac tests pass in debug/release; original 132
  and compressed 180 independent vectors, 15 inert probes / 14 filters / one
  pipeline in each configuration, native builds, nested ad-hoc signatures,
  ARM/minimum-26 metadata and packaged-worker output equality all pass.
- PR #81 first review: clean at base `77c29ff` / head `52ba93f`, reviewer
  thumbs-up, no inline findings or review threads. Hosted run 35198999638
  remains active at that head; this follow-on is not yet pushed.
- Actual physical delivery, scheduler retry mapping and USB: NOT RUN.

Actual local runtime: macOS 27.0 (26A428), arm64, Xcode 27.0, Swift 6.4.
The independently frozen B candidate remains unchanged at its original hashes
and source checkpoint; a normal package rebuild must never replace it.

## Next action

Publish the coherent follow-on after required checks and reconcile the PR review
against the changed source pair. Continue independent complete-job transport
binding and control implementation; retain the manual scheduler/hardware gates.
