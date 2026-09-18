# M3 accepted job store evidence — 2026-09-15

## Scope

Commit `8bd8c32` adds private immutable persistence for the resolved accepted-job
ticket. Before publication and after every load, the store resolves the exact
queue reference through the queue store, reopens the exact workflow and printer
profiles, checks their canonical digests, and performs the ticket's complete
plan/control validation. The stored ticket must also be the canonical byte
representation and match the requested acceptance identity.

Acceptance identifiers are hashed for file naming. Owner-only no-follow
directories, bounded regular-file reads, exclusive temporary publication,
complete writes, file/directory synchronization, and exclusive atomic rename
come from the shared immutable-store primitive. Same-byte publication is
idempotent; different bytes for the same acceptance identity are a conflict.
The store contains job semantics only—not source PDFs, rendered bitmaps,
printer-language payloads, titles, paths, or endpoint identities.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Accepted-job-store focused tests — 5 passed.
- Exact canonical save/reload after the active queue advanced to another
  immutable revision — passed; the accepted ticket retained the earlier queue
  and generation.
- Idempotent same-byte publication and concurrent conflicting writers — passed;
  exactly one complete conflicting value won.
- Altered acceptance identity, noncanonical bytes, missing queue revision,
  unsafe root, and path-like lookup — rejected.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 153 passed in each configuration.
- LabelMac debug and release — 92 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

## Acceptance impact and remaining gates

This adds partial automated evidence for M3-AC12, M5-AC05, and M5-AC07. No
acceptance row is newly complete. Scheduler intake does not yet create the
ticket/store entry, and source-spool ownership is not implemented. Job state,
authorized cancellation, retention/garbage collection, held-job release,
restart recovery, scheduler publication, and cross-process delivery remain
open. No queue, administrator path, transport, or physical printer was used.
