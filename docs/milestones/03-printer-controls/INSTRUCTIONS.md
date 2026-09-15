# M3 — Capabilities, controls, transport and job state

**Dependencies:** M1 accepted transport boundary; M2 prepared output for end-to-end tests
**Goal:** Control real printer behavior safely, serialize virtual queues and report delivery uncertainty honestly.

## Before editing

Read all four milestone files, AGENTS.md, the accepted baseline ADR, current handoff and [sprint baseline](../../SPRINT-BASELINE.md). Verify dependency/evidence state and current environment. MIT, Tahoe 26 minimum and local signing are confirmed; do not repeatedly request an Apple account or older hardware.

## Suggested sequential PR slices

### M3.1 — Implement capabilities and schema validation

Typed tri-state capabilities, installed hardware, bounded profile loading and provenance. Prioritize GC420d direct-thermal/tear-off profile and explicit unknowns.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M3.2 — Implement controls and settings resolution

Command mapping with model limits/persistence, per-job option resolution, offsets and media/thermal policies.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M3.3 — Implement network transport and state machine

Inert/loopback fixtures first; partial-write handling, timeouts, receipts and retry boundaries. GC420d USB first; no network-only substitution.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M3.4 — Implement qualified USB path

Reuse only a proven backend contract or add the required public transport adapter; support rediscovery and cancellation.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M3.5 — Implement physical-device coordination

Cross-process lifetime ownership across all queues and maintenance; alias, crash and stale-lock tests.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M3.6 — Qualify finishing and fault handling

Cutter/peeler behavior, status handling, persistent-state isolation and physical fault matrix.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

## Working procedure

Use the [execution protocol](../../EXECUTION.md). Prefer focused branches/green coherent commits, not automatic merges. Test portable logic, Mac APIs and milestone cases at their required evidence levels. Missing local GUI/device access blocks those tests, not independent implementation. The reference configuration is not operational consent: installation, queue changes and printer commands require explicit finite authorization.

Read [local signing](../../LOCAL-SIGNING.md) before any helper/install code. M1 must prove no-account admission/authorization early; do not weaken identity checks to make ad-hoc code work. Keep S1 baseline qualification, retained S2 accessory/model scope and deferred S3 trusted-public signing separate.

## Slice handoff

Update docs/HANDOFF.md with exact SHA, acceptance coverage, tests/results, API/schema/security decisions, blocked evidence and next safe action. Update global and scoped progress without equating compile/simulation/GUI/physical/signature-policy results. Keep public evidence sanitized. Do not publish/merge, change permissions or spend unapproved labels just because CI is green.
