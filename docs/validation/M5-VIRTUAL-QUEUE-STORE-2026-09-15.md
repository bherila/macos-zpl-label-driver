# M5 virtual-queue store evidence — 2026-09-15

## Scope

Commit `ff0f2dc` adds private immutable storage for virtual-queue intent. It
does not publish a CUPS queue, install a component, elevate privileges, contact
a device, or alter system defaults.

Before publication, the store reopens the exact saved workflow profile and
checks its schema, identifier, revision, and canonical SHA-256 digest. It also
requires the separate local unattended-use qualification for that exact
workflow value. The printer profile schema/revision and caller-supplied digest
must match the queue binding. A future printer-profile store must become the
trusted source of that digest; this slice does not claim that missing store.

Queue revisions are written owner-only through no-follow descriptors, complete
writes, file and directory `fsync`, and exclusive atomic rename. Existing
identical bytes are idempotent. Existing different bytes conflict rather than
being replaced. Reads require a regular owner-only, single-link file within the
size cap and verify metadata stability plus the decoded queue identity before
re-resolving its profile references.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- `swift test --package-path Packages/LabelMac --filter VirtualQueueStoreTests`
  — 5 passed.
- `swift test --package-path Packages/LabelMac` — 79 passed.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 136 passed in each configuration.
- LabelMac debug and release — 79 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

Focused cases cover exact qualified-reference round trip, idempotent save,
unqualified and changed workflow rejection, wrong printer-digest rejection,
immutable byte conflict, tampered identity, insecure store roots, and concurrent
conflicting writers leaving one complete winner.

## Acceptance impact and remaining gates

This is additional partial automated support for M5-AC05 and M5-AC07. Both
remain unchecked because they require real macOS integration. A trusted
immutable printer-profile store, active-revision selection, scheduler
publication, held-job policy, update/rollback repair, restart recovery,
preservation of unrelated printers/defaults, and installed cross-queue device
serialization remain unimplemented or unverified. All M1 administrator,
Gatekeeper, USB, and physical-output gates remain open.
