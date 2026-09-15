# M1 — macOS printing integration proof

**Dependencies:** M0; local Tahoe 26 Mac for GUI/scheduler/no-account installation evidence
**Goal:** Prove full-page capture, native per-job controls and local-signing installation/runtime feasibility before committing to an adapter.

## Acceptance checklist

Evidence levels: **A** automated; **C** repository/CI/configuration inspection; **I** real macOS integration; **H** physical hardware; **R** release/distribution in the declared signing mode. See [validation policy](../../VALIDATION-PLAN.md) and [release scopes](../../RELEASE-SCOPES.md).

| Done | ID | Area | Minimum evidence | Acceptance criterion |
|---|---|---|---|---|
| [ ] | M1-AC01 | Native scheduler execution | I | A Swift ARM executable is invoked by the real scheduler without Rosetta, GUI access or an altered security policy. |
| [ ] | M1-AC02 | Full-page preservation | I | All synthetic Letter/A4 corner and crop markers reach the selected workflow intact in each required application path. |
| [ ] | M1-AC03 | Input fidelity inventory | I | Each app path has recorded MIME/resolution/vector status; no source-fidelity assumption remains implicit. |
| [ ] | M1-AC04 | Print-dialog options | I | Every representative option is visible in the system dialog and reaches the filter with the selected typed value. |
| [ ] | M1-AC05 | Browser distinction | I | Browser-owned preview versus system-dialog behavior is documented, with a usable workflow for required advanced choices. |
| [ ] | M1-AC06 | Transform ownership | I | Copies/ranges/collation/rotation/scaling/number-up ownership is evidenced; duplicate application of a transformation is prevented or explicitly rejected. |
| [ ] | M1-AC07 | Profile snapshot | I | A held job retains its selected immutable profile revision after defaults/profile edits; the snapshot boundary is documented. |
| [ ] | M1-AC08 | Sandbox and privacy | I | Profile access works under the spooler identity; no user-home/desktop dependency or unsolicited payload logging exists. |
| [ ] | M1-AC09 | Cancellation and errors | I | Stdin/file input, SIGTERM, broken pipe and invalid input produce bounded cleanup and correct non-success semantics. |
| [ ] | M1-AC10 | Transport ownership | I | The chosen transport boundary can keep a device-wide lock through downstream delivery/child termination, not just filter stdout completion. |
| [ ] | M1-AC11 | Reversible experiment | I | Creating and deleting only the experimental queue leaves the original printer and global settings unchanged. |
| [ ] | M1-AC12 | Decision evidence | C | ADR links exact evidence per required feature; unsupported controls or input loss are open blockers, not marked solved. |
| [ ] | M1-AC13 | Local-signing feasibility | I | The actual Tahoe scheduler and proposed narrow installer/helper work in local-ad-hoc mode without Apple identity; approval and trust/substitution behavior is recorded. Unproven privileged admission blocks adapter/installer commitment. |

## Completion rules

Check an item only after its exact evidence is recorded. Implemented is not physically tested. Account-free local signing is the active mode; future Developer-ID notarization is not an S1 blocker. Scope-specific nonapplicability is recorded with reasons and never silently becomes a global pass. Critical security, clipping, count/order or uncontrolled-replay defects block qualification. Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md), [progress](../../PROGRESS.json) and [scope status](../../SCOPE-STATUS.json).
