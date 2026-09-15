# M2 — Geometry, imaging and ZPL engine

**Dependencies:** M0; use M1 input/transform findings for production adapter integration
**Goal:** Produce deterministic, bounded label output from original documents with an exact monochrome preview.

## Before editing

Read all four milestone files, AGENTS.md, the accepted baseline ADR, current handoff and [sprint baseline](../../SPRINT-BASELINE.md). Verify dependency/evidence state and current environment. MIT, Tahoe 26 minimum and local signing are confirmed; do not repeatedly request an Apple account or older hardware.

## Suggested sequential PR slices

### M2.1 — Implement geometry and page planning

Checked units/transforms, exact-size/fit placement, crop region contract and test vectors. Include GC420d physical-pitch/stock/head-extent regression vectors.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M2.2 — Implement Quartz renderer

White-background rendering, supported PDF semantics, bounded worker/input handling and regression fixtures.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M2.3 — Implement one-bit processing and preview

Threshold/dither policies, packed bitmap types, exact preview and visual/structural tests.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M2.4 — Implement banded uncompressed ZPL

Correct field counts/offsets, complete formats, test decoder and command limit checks.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M2.5 — Add lossless compression and benchmarks

Capability-gated compression, cross-checks, allocation/throughput measurements and bounded staging.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M2.6 — Integrate CLI and proven filter path

Typed job input, structured errors, cancellation/limits and integration with the accepted M1 adapter.

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
