# M5 active queue revision contract evidence — 2026-09-15

## Scope

Commit `087458d` adds a bounded contract for selecting an active immutable
virtual-queue revision. This is portable configuration and local-store API
evidence only. It does not select or publish a CUPS destination, change a
default printer, run an administrator path, or affect an in-flight job.

Each selection binds an exact queue schema/revision/SHA-256 reference. The
first selection has generation 1 and no previous digest. Later selections
require a higher positive generation contract and the distinct digest of the
previous queue target. These fields are intended for a native compare-and-swap
publisher; this slice does not claim that publisher exists yet. A held job can
retain its earlier immutable queue reference even after the active selection
changes.

`VirtualQueueStore.save` now returns the canonical immutable queue reference,
and exact-reference load rejects a wrong digest. The active-selection JSON has
an exact schema and rejects unknown fields, embedded paths/commands/documents,
invalid generation/history combinations, bad scalar types, and oversized
input/output.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Active-selection focused tests — 4 passed.
- Updated queue-store focused tests — 5 passed.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 145 passed in each configuration.
- LabelMac debug and release — 83 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

## Acceptance impact and remaining gates

This adds partial automated support for M5-AC05 and M5-AC07. Neither row is
complete. A cross-process compare-and-swap active-selection store, crash
recovery, scheduler publication/rollback, held-job integration, restart proof,
and preservation of unrelated printers/defaults remain unimplemented or
unverified. All administrator, USB, and physical-output gates remain open.
