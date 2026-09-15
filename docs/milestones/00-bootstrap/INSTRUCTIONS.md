# M0 — Repository, project setup and CI

**Dependencies:** None
**Goal:** Establish a reproducible, honest starting repository and safe sequential development process.

## Before editing

Read all four milestone files, AGENTS.md, the accepted baseline ADR, current handoff and [sprint baseline](../../SPRINT-BASELINE.md). Verify dependency/evidence state and current environment. MIT, Tahoe 26 minimum and local signing are confirmed; do not repeatedly request an Apple account or older hardware.

## Suggested sequential PR slices

### M0.1 — Initialize and reconcile repository

Confirm ownership/visibility; use already-confirmed MIT; retain existing history; import revised scaffold and baseline without private data.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M0.2 — Verify Swift package boundaries

Build core/Mac targets on Tahoe, enforce 26.0 deployment, validate reference inputs and run secret-free local-ad-hoc diagnostic signing.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M0.3 — Activate and verify CI

Execute macos-26 ARM CI; no pre-Tahoe matrix; prove docs-only/failing-code paths and the stable required check.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M0.4 — Establish contribution and evidence workflow

Add/verify issue templates, security reporting, progress tracking, handoff and dependency policy.

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
