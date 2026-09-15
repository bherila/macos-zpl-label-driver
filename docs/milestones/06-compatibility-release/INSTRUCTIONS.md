# M6 — Compatibility, qualification and release gate

**Dependencies:** M1–M5 implemented for declared scope; actual Tahoe/GC420d/local-signing evidence; broader accessory tests remain separate
**Goal:** Qualify the promised workflows and maintain a truthful support matrix before publishing a usable release.

## Before editing

Read all four milestone files, AGENTS.md, the accepted baseline ADR, current handoff and [sprint baseline](../../SPRINT-BASELINE.md). Verify dependency/evidence state and current environment. MIT, Tahoe 26 minimum and local signing are confirmed; do not repeatedly request an Apple account or older hardware.

## Suggested sequential PR slices

### M6.1 — Build compatibility matrix and evidence tooling

Versioned support claims, evidence integrity checks and requirements coverage report.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M6.2 — Qualify OS/application/workflow paths

Qualify observed Tahoe app workflows/native/extraction paths; record exact patch/build; no pre-Tahoe matrix.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M6.3 — Qualify hardware quality and faults

GC420d geometry/scan/USB faults and concurrency first; track unavailable accessory/network physical qualification separately.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M6.4 — Benchmark and harden release candidate

Reference-machine budgets, resource/security checks and regression fixes.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M6.5 — Complete release gate and scoped expansion ADR

GC420d-local acceptance and local-signing evidence; truthful limitations/S2 backlog/S3 deferral; IPP/Intel only if independently qualified.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

## Working procedure

Use the [execution protocol](../../EXECUTION.md). Prefer focused branches/green coherent commits, not automatic merges. Test portable logic, Mac APIs and milestone cases at their required evidence levels. Missing local GUI/device access blocks those tests, not independent implementation. The reference configuration is not operational consent: installation, queue changes and printer commands require explicit finite authorization.

Read [local signing](../../LOCAL-SIGNING.md) before any helper/install code. M1 must prove no-account admission/authorization early; do not weaken identity checks to make ad-hoc code work. Keep S1 baseline qualification, retained S2 accessory/model scope and deferred S3 trusted-public signing separate.

## Slice handoff

Update docs/HANDOFF.md with exact SHA, acceptance coverage, tests/results, API/schema/security decisions, blocked evidence and next safe action. Update global and scoped progress without equating compile/simulation/GUI/physical/signature-policy results. Keep public evidence sanitized. Do not publish/merge, change permissions or spend unapproved labels just because CI is green.
