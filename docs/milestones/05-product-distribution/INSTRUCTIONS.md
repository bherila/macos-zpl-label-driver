# M5 — Native application, installation and distribution

**Dependencies:** Accepted M1 no-account adapter/install proof; M2–M4 components; no Developer ID required
**Goal:** Deliver a secure account-free local build/install/use/update/uninstall experience with native UI and virtual workflows.

## Before editing

Read all four milestone files, AGENTS.md, the accepted baseline ADR, current handoff and [sprint baseline](../../SPRINT-BASELINE.md). Verify dependency/evidence state and current environment. MIT, Tahoe 26 minimum and local signing are confirmed; do not repeatedly request an Apple account or older hardware.

## Suggested sequential PR slices

### M5.1 — Build native setup and configuration UI

App target, discovery/manual connection, stock/options, status and integrated extraction editor.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M5.2 — Implement queue/default management

Owned virtual queues, immutable profile publication, clear default layers and restart behavior.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M5.3 — Implement narrow installer/helper

Implement the M1-proven no-account authorization/staging/code-validation design; reject unsafe client/path/substitution requests and preserve native UX.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M5.4 — Implement lifecycle and recovery

Transactional upgrade/rollback across distinct ad-hoc builds, repair, safe job drain, immutable profiles and idempotent uninstall.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M5.5 — Implement diagnostics and accessibility

Privacy-reviewed export, useful errors/uncertainty, keyboard/VoiceOver and localizable text.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

### M5.6 — Build and validate local distribution

Source/local-ad-hoc artifacts, native installation and quarantine characterization, checksums/notices/evidence; trusted-public mode explicitly deferred.

Implement behavior and regression tests together. Record acceptance IDs advanced, keep a reviewable diff and add each real target/test to CI in the same slice.

## Working procedure

Use the [execution protocol](../../EXECUTION.md). Prefer focused branches/green coherent commits, not automatic merges. Test portable logic, Mac APIs and milestone cases at their required evidence levels. Missing local GUI/device access blocks those tests, not independent implementation. The reference configuration is not operational consent: installation, queue changes and printer commands require explicit finite authorization.

Read [local signing](../../LOCAL-SIGNING.md) before any helper/install code. M1 must prove no-account admission/authorization early; do not weaken identity checks to make ad-hoc code work. Keep S1 baseline qualification, retained S2 accessory/model scope and deferred S3 trusted-public signing separate.

## Slice handoff

Update docs/HANDOFF.md with exact SHA, acceptance coverage, tests/results, API/schema/security decisions, blocked evidence and next safe action. Update global and scoped progress without equating compile/simulation/GUI/physical/signature-policy results. Keep public evidence sanitized. Do not publish/merge, change permissions or spend unapproved labels just because CI is green.
