# M5 — Native application, installation and distribution

**Dependencies:** Accepted M1 no-account adapter/install proof; M2–M4 components; no Developer ID required
**Goal:** Deliver a secure account-free local build/install/use/update/uninstall experience with native UI and virtual workflows.

## Acceptance checklist

Evidence levels: **A** automated; **C** repository/CI/configuration inspection; **I** real macOS integration; **H** physical hardware; **R** release/distribution in the declared signing mode. See [validation policy](../../VALIDATION-PLAN.md) and [release scopes](../../RELEASE-SCOPES.md).

| Done | ID | Area | Minimum evidence | Acceptance criterion |
|---|---|---|---|---|
| [ ] | M5-AC01 | Install-once UX | I | A supported Tahoe Mac can install/configure through native UI without terminal commands, Apple accounts or weakened OS security; actual approvals and host isolation level are documented. |
| [ ] | M5-AC02 | Native architecture | I | Every shipped executable/helper/library required on Apple Silicon is ARM-native; no hidden Rosetta dependency exists. |
| [ ] | M5-AC03 | Routine application printing | I | Configured queues print after UI closes and after restart under the advertised session/service conditions. |
| [ ] | M5-AC04 | Complete controls/defaults | I | All qualified controls are usable through the system dialog/workflow and utility defaults; unsupported options are explicit. |
| [ ] | M5-AC05 | Virtual queues | I | Several workflows share one device without interleaving; creating/updating them preserves unrelated printers/defaults. |
| [ ] | M5-AC06 | Privileged boundary | I | No-account authorization, protected staging, client/code/path validation and anti-substitution tests pass; bundle ID/ad-hoc signature alone is not privileged authorization and no renderer/arbitrary shell runs as root. |
| [ ] | M5-AC07 | Transactional lifecycle | I | Interrupted install/update rolls back or repairs safely; held jobs/profile revisions survive according to policy. |
| [ ] | M5-AC08 | Uninstall | I | Repeated uninstall removes only owned resources and respects the explicit profile-retention choice. |
| [ ] | M5-AC09 | Diagnostics/privacy | I | Default logs/exports contain no sensitive label payloads; full export requires opt-in and review. |
| [ ] | M5-AC10 | Accessibility | I | Core setup/profile/status/error flows support keyboard and VoiceOver and do not rely solely on color. |
| [ ] | M5-AC11 | Local distribution security | R | Exact local-ad-hoc components verify and pass declared installation/lifecycle tests without Apple credentials; local versus quarantined launch outcomes and provenance are recorded honestly. No notarization claim is made. |
| [x] | M5-AC12 | Signing-mode separation | A | Local-ad-hoc is the explicit secret-free default; any selected future Developer-ID mode fails if unavailable instead of silently downgrading. Source/local binaries are accurately labeled. |
| [ ] | M5-AC13 | Ad-hoc update identity | I | Two distinct locally signed builds upgrade/rollback through authorized code validation; changed hashes do not silently break use or permit arbitrary client/payload replacement. |

## Completion rules

Check an item only after its exact evidence is recorded. Implemented is not physically tested. Account-free local signing is the active mode; future Developer-ID notarization is not an S1 blocker. Scope-specific nonapplicability is recorded with reasons and never silently becomes a global pass. Critical security, clipping, count/order or uncontrolled-replay defects block qualification. Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md), [progress](../../PROGRESS.json) and [scope status](../../SCOPE-STATUS.json).
