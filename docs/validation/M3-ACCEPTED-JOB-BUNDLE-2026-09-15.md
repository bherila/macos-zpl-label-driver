# M3 accepted job bundle evidence — 2026-09-15

## Scope

Commit `e2b6332` replaces ticket-only accepted-job persistence with one private,
immutable publication containing the canonical resolved ticket and the exact
original PDF bytes named by that ticket. Both files are fully written and
synchronized inside an owner-only temporary directory before one exclusive
directory rename makes the pair visible. Rendered and printer-language payloads
remain outside this store.

The store checks the source byte count and SHA-256 digest before any publication
and after every load. It also re-resolves the exact immutable queue, workflow,
and printer references and repeats complete ticket validation. Owner-only
no-follow directories, regular owner-only single-link files, bounded reads,
stable metadata checks, and hashed acceptance identifiers constrain the private
storage boundary.

Faults before rename remove the unpublished temporary pair. A fault after the
rename is classified as `commitUncertain`; the complete bundle remains
recoverable and callers are not told that publication safely failed. Identical
republication is idempotent, while any different ticket or source bytes for the
same acceptance identity conflict without replacement.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Accepted-job-bundle focused tests — 9 passed.
- Exact ticket and source reload after the active queue advanced — passed; the
  accepted bundle retained its earlier immutable queue and generation.
- Fault injection after ticket write, after source write, before rename, and
  after rename — passed with no partial visible bundle; post-rename failure was
  uncertain and recoverable.
- Concurrent conflicts, idempotent replay, source digest mismatch, ticket/source
  tampering, missing references, unsafe roots, symbolic links, and hard links —
  rejected as specified.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 153 passed in each configuration.
- LabelMac debug and release — 96 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

## Acceptance impact and remaining gates

This adds partial automated evidence for M3-AC12, M5-AC05, and M5-AC07. No
acceptance row is newly complete. The API receives already-bounded bytes; a
descriptor-bound scheduler intake path is not implemented or proven. Job-state
and authorized-cancellation persistence, retention and secure deletion policy,
held-job release, restart recovery, scheduler publication, and cross-process
delivery remain open. The synthetic bytes used by the store tests identify PDF
intent but this storage boundary does not parse or render them. No queue,
administrator path, transport, or physical printer was used.
