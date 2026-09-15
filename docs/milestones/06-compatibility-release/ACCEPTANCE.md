# M6 — Compatibility, qualification and release gate

**Dependencies:** M1–M5 implemented for declared scope; actual Tahoe/GC420d/local-signing evidence; broader accessory tests remain separate
**Goal:** Qualify the promised workflows and maintain a truthful support matrix before publishing a usable release.

## Acceptance checklist

Evidence levels: **A** automated; **C** repository/CI/configuration inspection; **I** real macOS integration; **H** physical hardware; **R** release/distribution in the declared signing mode. See [validation policy](../../VALIDATION-PLAN.md) and [release scopes](../../RELEASE-SCOPES.md).

| Done | ID | Area | Minimum evidence | Acceptance criterion |
|---|---|---|---|---|
| [ ] | M6-AC01 | Traceability | A | Every mandatory requirement maps to implementation and required validation evidence; empty/blocked evidence cannot count as pass. |
| [ ] | M6-AC02 | Runtime support | I | Every claimed macOS/architecture row is tested on that runtime; deployment target alone is not qualification. |
| [ ] | M6-AC03 | Application support | I | Required app/native/extraction paths have exact version/profile evidence and disclosed limitations. |
| [ ] | M6-AC04 | Device support | H | Every qualified model/resolution/transport/media/accessory row has physical evidence rather than an inferred family match. |
| [ ] | M6-AC05 | Barcode/geometry quality | H | The agreed sample count scans correctly with expected payloads and satisfies documented geometry/placement tolerances. |
| [ ] | M6-AC06 | Finishing qualification | H | All advertised cutter/peeler behaviors pass real accessory tests or remain explicitly unqualified and gate full parity closure. |
| [ ] | M6-AC07 | Fault/retry behavior | H | Critical disconnect/power/media/cancel/sleep cases recover without uncontrolled replay, false completion or stale ownership. |
| [ ] | M6-AC08 | Concurrent workflows | H | Competing product queues and maintenance retain job/setting isolation and correct physical sequence. |
| [ ] | M6-AC09 | Performance | I | Published speed/resource statements have reproducible measurements and reviewed thresholds on the reference setup. |
| [ ] | M6-AC10 | Security/lifecycle gate | R | No unresolved critical security/lifecycle flaw; exact local candidate passes active M5 account-free distribution and installation checks with isolation/approval limitations recorded. |
| [ ] | M6-AC11 | Optional integration claims | I | Any advertised IPP/Intel/extra transport feature has its own required evidence, not just compilation. |
| [ ] | M6-AC12 | Release honesty | R | Release notes and support matrix accurately distinguish qualified, limited, experimental and unavailable features. |
| [ ] | M6-AC13 | Scoped GC420d closure | C | S1 evidence covers the confirmed target without requiring old macOS/Apple credentials/absent accessories; no S1 result auto-closes S2 finishing tests or marks deferred S3 trusted distribution passed. |

## Completion rules

Check an item only after its exact evidence is recorded. Implemented is not physically tested. Account-free local signing is the active mode; future Developer-ID notarization is not an S1 blocker. Scope-specific nonapplicability is recorded with reasons and never silently becomes a global pass. Critical security, clipping, count/order or uncontrolled-replay defects block qualification. Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md), [progress](../../PROGRESS.json) and [scope status](../../SCOPE-STATUS.json).
