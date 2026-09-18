# M3 persisted-job restart recovery — 2026-09-15

**Scope:** native automated evidence at `65dce21` with review remediations at
`75fca07` and `616a5d8`. This slice adds a bounded
reconciliation primitive for one known accepted-job ID. It does not enumerate
jobs, install a worker, connect scheduler intake, or contact a printer.

## Proven behavior

- Accepted jobs are classified as needing preparation without mutation.
- Validated prepared and waiting jobs are classified as ready for delivery;
  recovery does not deliver them.
- A persisted transmitting job is reloaded with its exact immutable prepared
  artifact, then recovery acquires the same ticket-derived physical-device
  lease used by delivery.
- If that lease is held, recovery reports a busy physical-device domain and
  leaves lifecycle state unchanged.
- If the lease can be acquired and the job is still transmitting, recovery
  advances it to terminal uncertainty while preserving the exact payload
  identity, byte count, and last known accepted-byte count. It never calls a
  sink or authorizes automatic replay.
- Transmitted, device-confirmed, and uncertain outcomes are read back from the
  validated prepared artifact without lifecycle mutation.
- If a concurrent owner advances a ready job to transmitting between recovery's
  first state read and its prepared-artifact read, recovery routes that observed
  state through the same lease-backed reconciliation path rather than failing
  outside the ownership boundary.
- If cancellation or pre-send failure becomes visible in that same interval,
  recovery boundedly reloads and returns the newer terminal outcome instead of
  treating loss of the prepared binding as corruption.
- State publication uncertainty remains explicit instead of being reported as
  successful reconciliation.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- `swift test --package-path Packages/LabelMac --filter AcceptedJobStoreTests`
  — 41 passed;
- `swift test --package-path Packages/LabelMac` — 146 passed;
- `swift test -c release --package-path Packages/LabelMac` — 146 passed;
- complete `bash scripts/ci-swift.sh` exact-head gate — 64 Python tests,
  165 LabelCore tests in debug and release, 146 LabelMac tests in debug and
  release, 132 independent encoder round trips, 15 backend ABI cases, 10
  filter ABI cases, one inert pipeline case, and local ad-hoc product signature
  verification passed at the remediated exact head.

## Evidence limits and next boundary

This is automated native evidence toward M3-AC09 and restart semantics only.
It does not establish installed integration, scheduler exit/retry mapping,
cross-process recovery discovery, process identity, transport behavior, USB,
device confirmation, or physical output. A production worker still needs a
bounded descriptor/IPC contract and a safe inventory/retention policy. The M1
administrator discard-queue experiment remains a separate prerequisite for
committing to the installed scheduler boundary.
