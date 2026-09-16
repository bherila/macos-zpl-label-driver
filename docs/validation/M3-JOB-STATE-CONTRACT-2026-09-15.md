# M3 durable job-state contract evidence — 2026-09-15

## Scope

Commit `ac6a178` adds a bounded canonical contract for accepted, prepared,
waiting, transmitting, transmitted, device-confirmed, uncertain,
failed-before-transmission, and cancelled-before-transmission states. Prepared
and later states bind one payload SHA-256 and byte count. Progress is monotonic,
full transmission remains distinct from device confirmation, and ambiguity is
terminal rather than implicitly retryable.

Each replacement increments a generation and names the SHA-256 of the exact
prior canonical record. The contract rejects path-like identities, malformed or
oversized JSON, unknown fields, invalid payload bounds, changed payloads,
backward byte counts, incomplete transmission claims, and transitions out of a
terminal state.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Focused accepted-job-state tests — 6 passed.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 159 passed in each configuration.
- LabelMac debug and release — 96 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS.

## Acceptance impact and remaining gates

This is additional partial automated evidence for M3-AC09, M3-AC12, and
M5-AC07. No row is newly complete. The record is not yet persisted, cancellation
tokens are not yet authorized against an accepted ticket, and no scheduler exit
mapping, restart recovery, transport, queue, administrator path, or physical
printer was exercised.
