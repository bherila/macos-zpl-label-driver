# M3 prepared-job store evidence — 2026-09-15

## Scope

Commit `9dfe442` makes the prepared artifact and its lifecycle authorization one
ordered, recoverable transaction. The typed payload now carries the exact
resolved output identities in order and the resolved printer controls used by
the encoder. Publication requires those identities, controls, and the immutable
printer-profile snapshot to match the accepted ticket.

Under the existing per-job cross-process lock, `prepared.zpl` is written to an
owner-only exclusive temporary file, synchronized, renamed without replacing
an existing artifact, and directory-synchronized before `state.json` may move
from `accepted` to `prepared`. The prepared state records the exact byte count
and SHA-256. A failure before the state transition leaves an inert orphan: an
exact retry may reuse it, but different bytes conflict. A failure after the
state rename reports `commitUncertain`, and the complete artifact/state pair is
recoverable by verified load.

The general state API can no longer manufacture a `prepared` generation from
an arbitrary digest. Every payload-bearing load and later state transition
requires a bounded, stable, owner-only, regular, single-link artifact whose
count and digest match the lifecycle record. Accepted, failed, and cancelled
states never expose an orphan artifact for delivery.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Prepared-label/job focused tests — 7 passed.
- Accepted-job/store focused tests — 18 passed.
- Exact output-order, profile, and resolved-control ticket binding — passed.
- Arbitrary digest-only `accepted` to `prepared` transition — rejected.
- Concurrent prepared publishers — exactly one state winner.
- Faults after artifact rename and after its directory synchronization left the
  state accepted; exact retry succeeded and different bytes conflicted.
- Fault after state rename reported uncertain; verified load recovered the
  complete prepared generation.
- Missing, changed, linked, symlinked, and loosely permissioned artifacts were
  not returned or advanced.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 163 passed in each configuration.
- LabelMac debug and release — 105 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS.

## Acceptance impact and remaining gates

This adds partial automated evidence for M3-AC02, M3-AC09, M3-AC12, M5-AC07,
and M5-AC09. No row is newly complete. Real multi-page extraction/rendering is
not yet orchestrated into this store. Scheduler intake, held-job release,
delivery result mapping, retention/deletion policy, restart enumeration, queue
installation, transport, and physical-printer evidence remain open. No queue,
administrator path, transport, or physical printer was used.
