# M3 resolved job ticket evidence — 2026-09-15

## Scope

Commit `d6c4130` adds a bounded, deterministic accepted-job contract that binds
work to exact immutable queue, workflow, and printer-profile references. It
also records the physical-device coordination digest, active-selection
generation, source digest and bounds, intake provenance, final output order,
explicitly skipped pages, ownership of copies and page ranges, fixed ownership
of extraction/orientation/scaling, resolved printer controls, and acceptance
and cancellation identities.

The decoder first obtains a structurally complete queue reference, then requires
the caller to resolve and supply the exact immutable queue, workflow, and
printer values before full validation succeeds. It re-derives the expected
output plan and rejects changed references, ordering, ownership, unsupported
controls, unknown fields, bad scalar types, oversized input, and copy expansion
that would overflow or exceed the output cap. Read-only observed printer values
remain distinct from qualified defaults, and the resolved media-geometry
request is no longer discarded.

The format intentionally excludes titles, paths, payload bytes, endpoint
identities, and raw printer commands. Page-range ownership is represented, but
the current extraction planner admits the complete source-page set only; a
future intentional page-range planner must land before subset tickets can be
accepted.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Resolved-job-ticket focused tests — 8 passed.
- Exact round trip and immutable-reference checks — passed.
- Active-selection change after acceptance — prior accepted reference retained.
- Ordering, copies, collation, skipped-page, and ownership tamper vectors —
  rejected.
- Unsupported controls, unknown fields, path injection, Boolean-as-integer,
  input-size, wire-size, and integer-overflow vectors — rejected.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 153 passed in each configuration.
- LabelMac debug and release — 87 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

## Acceptance impact and remaining gates

This adds partial automated evidence for M3-AC02, M3-AC12, M5-AC05, and
M5-AC07. No acceptance row is newly complete. The contract is not yet persisted
as an accepted-job record or integrated with scheduler intake. Submission-time
snapshotting, held-job release after an active revision changes, restart
recovery, retention/garbage collection, system-dialog option propagation, and
cross-process delivery remain open. No queue, administrator path, USB device,
network printer, or physical printer was contacted.
