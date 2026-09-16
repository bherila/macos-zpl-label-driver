# M3 accepted-job state store evidence — 2026-09-15

## Scope

Commit `fc2c8de` publishes the initial canonical `accepted` state in the same
exclusive directory transaction as the resolved ticket and exact original PDF.
Later state replacements use a private per-job descriptor-relative `flock`,
compare the complete expected record, chain to the SHA-256 of the exact prior
canonical bytes, write and synchronize a private temporary file, and atomically
replace `state.json`.

Post-rename confirmation failure is reported as `commitUncertain`, and the new
complete state remains recoverable. Concurrent writers cannot both advance the
same generation. State reads require a regular owner-only single-link file,
bounded exact reads, stable metadata, canonical JSON, the matching accepted-job
identity, and revalidation of the immutable ticket/profile chain.

Cancellation uses a separate API. The caller supplies a bounded capability
whose SHA-256 must match the digest stored in the accepted ticket using a
constant-time byte comparison. The general transition API rejects cancellation,
wrong capabilities leave state unchanged, and raw capabilities are not stored
in the ticket, source, or state files.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Accepted-job/store focused tests — 14 passed.
- Initial state included in every injected pre-publication cleanup boundary —
  passed; no partial bundle remained.
- Exact prior-state digest, stale expected-state rejection, concurrent one-winner
  publication, and post-rename uncertain/recoverable behavior — passed.
- Wrong and bypassed cancellation capabilities caused no state mutation; the
  correct capability cancelled before transmission — passed.
- State identity tampering and raw-capability persistence checks — passed.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 159 passed in each configuration.
- LabelMac debug and release — 101 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS.

## Acceptance impact and remaining gates

This adds partial automated evidence for M3-AC09, M3-AC12, M5-AC07, and
M5-AC09. No row is newly complete. Scheduler intake does not create these
bundles yet, prepared artifacts are not connected to the state transition,
scheduler exit/retry mapping is unproven, and retention/secure deletion and
restart recovery policy remain open. No queue, administrator path, transport,
or physical printer was used.
