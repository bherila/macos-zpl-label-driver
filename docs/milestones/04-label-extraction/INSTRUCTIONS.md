# M4 — Sheet extraction and browser workflows

**Dependencies:** M2 engine; M1 workflow media behavior; M3 profile/control integration
**Goal:** Extract, rotate, scale and order labels from larger documents without sacrificing source detail or silently discarding content.

## Before editing

Read all four milestone files, AGENTS.md, the accepted baseline ADR, current handoff and [sprint baseline](../../SPRINT-BASELINE.md). Verify dependency/evidence state and current environment. MIT, Tahoe 26 minimum and local signing are confirmed; do not repeatedly request an Apple account or older hardware.

## Suggested sequential PR slices

### M4.1 — Implement extraction schema and planner

Regions, page matching, order, quiet margins, mixed pages and default non-label handling.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M4.2 — Implement deterministic templates

Letter/A4/native workflows, structural validators, layout versioning and negative fixtures.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M4.3 — Implement teach-once editor components

Source selection, canonical coordinate editing, exact preview, keyboard interaction and profile import/export.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M4.4 — Implement assisted local detection

Candidate generation, ambiguity/no-match states, optional Vision adapter and confirmation gate.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M4.5 — Integrate virtual workflow configurations

Queue/profile bindings, defaults and per-job options preserving application-facing media.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M4.6 — Qualify browser extraction end to end

App workflows, changed-layout failures, mixed/non-label pages, copies/order and recovery UX.

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
