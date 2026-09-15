# M1 — macOS printing integration proof

**Dependencies:** M0; local Tahoe 26 Mac for GUI/scheduler/no-account installation evidence
**Goal:** Prove full-page capture, native per-job controls and local-signing installation/runtime feasibility before committing to an adapter.

## Before editing

Read all four milestone files, AGENTS.md, the accepted baseline ADR, current handoff and [sprint baseline](../../SPRINT-BASELINE.md). Verify dependency/evidence state and current environment. MIT, Tahoe 26 minimum and local signing are confirmed; do not repeatedly request an Apple account or older hardware.

## Suggested sequential PR slices

### M1.1 — Implement inert filter/capture harness

CUPS ABI parser, safe diagnostics, temporary-job handling, original experimental PPD and removable capture queue.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M1.2 — Measure document paths

Synthetic PDF/HTML fixture capture across apps; full-page, MIME, vector/raster and transform observations.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M1.3 — Prove controls and defaults

System generic options, option round-trips, immutable profile references and held-job behavior.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M1.4 — Prove execution and transport boundary

Tahoe spooler/permissions, ad-hoc execution after restart, no-account installer/helper authorization spike, and actual downstream lifetime locking.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M1.5 — Record adapter go/no-go

Evidence-backed ADR; alternate IPP spike only where necessary; list remaining integration risks.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

## Working procedure

Use the [execution protocol](../../EXECUTION.md). Prefer focused branches/green coherent commits, not automatic merges. Test portable logic, Mac APIs and milestone cases at their required evidence levels. Missing local GUI/device access blocks those tests, not independent implementation. The reference configuration is not operational consent: installation, queue changes and printer commands require explicit finite authorization.

Read [local signing](../../LOCAL-SIGNING.md) before any helper/install code. M1 must prove no-account admission/authorization early; do not weaken identity checks to make ad-hoc code work. Keep S1 baseline qualification, retained S2 accessory/model scope and deferred S3 trusted-public signing separate.

## Slice handoff

Update docs/HANDOFF.md with exact SHA, acceptance coverage, tests/results, API/schema/security decisions, blocked evidence and next safe action. Update global and scoped progress without equating compile/simulation/GUI/physical/signature-policy results. Keep public evidence sanitized. Do not publish/merge, change permissions or spend unapproved labels just because CI is green.

## Revision 3 starting material

Read [ACCELERATOR.md](../../ACCELERATOR.md) for existing tested components, fixture
inputs and slice-specific reuse instructions. Do not start these components from
empty placeholders. Their preparation tests are not full milestone acceptance;
retain all Mac, integration, security and physical evidence gates.
