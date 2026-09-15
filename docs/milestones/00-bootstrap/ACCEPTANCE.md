# M0 — Repository, project setup and CI

**Dependencies:** None
**Goal:** Establish a reproducible, honest starting repository and safe sequential development process.

## Acceptance checklist

Evidence levels: **A** automated; **C** repository/CI/configuration inspection; **I** real macOS integration; **H** physical hardware; **R** release/distribution in the declared signing mode. See [validation policy](../../VALIDATION-PLAN.md) and [release scopes](../../RELEASE-SCOPES.md).

| Done | ID | Area | Minimum evidence | Acceptance criterion |
|---|---|---|---|---|
| [ ] | M0-AC01 | Repository handling | C | Authenticated owner and target repo are recorded; existing content is preserved or absence is established before creation. |
| [ ] | M0-AC02 | License and privacy | C | License choice is recorded before public push; staged diff contains no private data, credentials or forbidden driver artifacts. |
| [ ] | M0-AC03 | Portable package | A | LabelCore builds and its tests run with a recorded Swift version without Core Graphics/AppKit/SwiftUI imports. |
| [ ] | M0-AC04 | macOS package | I | LabelMac builds natively on a hosted or local Apple Silicon Mac; its Core Graphics smoke test passes. |
| [ ] | M0-AC05 | CI execution | C | A real PR run executes the expected checks on the intended runner architecture; source/toolchain provenance is retained. |
| [ ] | M0-AC06 | CI fails closed | C | A deliberate test failure blocks ci-required; a docs-only PR passes the aggregate without launching unnecessary Mac compilation. |
| [ ] | M0-AC07 | Dependency security | A | All action uses are immutable SHA references; PR permissions are read-only; no signing secrets or privileged install steps exist. |
| [ ] | M0-AC08 | Docs and handoff | A | All relative links/JSON/checker tests pass, every milestone has four documents and the progress file is internally consistent. |
| [ ] | M0-AC09 | Contributor access | C | A fork PR can run the allowed checks after any required maintainer approval; no private-repo secrets are needed. |
| [ ] | M0-AC10 | Reporting status | C | Private vulnerability-reporting availability and branch-protection configuration are recorded accurately, including permission blocks. |
| [ ] | M0-AC11 | Confirmed baseline | A | Reference input matches GC420d/USB/4×6/pre-cut/tear-off/no cutter, 26.0 minimum, MIT and local-ad-hoc mode; unknown observations stay unknown and reference geometry is checked. |
| [ ] | M0-AC12 | Account-free signing smoke | I | On macOS 26 ARM, build/sign/verify/run the inert diagnostic with no Developer ID/Team ID/provisioning/Apple secrets; record actual code signature and minimum deployment metadata. |

## Completion rules

Check an item only after its exact evidence is recorded. Implemented is not physically tested. Account-free local signing is the active mode; future Developer-ID notarization is not an S1 blocker. Scope-specific nonapplicability is recorded with reasons and never silently becomes a global pass. Critical security, clipping, count/order or uncontrolled-replay defects block qualification. Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md), [progress](../../PROGRESS.json) and [scope status](../../SCOPE-STATUS.json).
