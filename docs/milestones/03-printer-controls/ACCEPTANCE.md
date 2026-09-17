# M3 — Capabilities, controls, transport and job state

**Dependencies:** M1 accepted transport boundary; M2 prepared output for end-to-end tests
**Goal:** Control real printer behavior safely, serialize virtual queues and report delivery uncertainty honestly.

## Acceptance checklist

Evidence levels: **A** automated; **C** repository/CI/configuration inspection; **I** real macOS integration; **H** physical hardware; **R** release/distribution in the declared signing mode. See [validation policy](../../VALIDATION-PLAN.md) and [release scopes](../../RELEASE-SCOPES.md).

| Done | ID | Area | Minimum evidence | Acceptance criterion |
|---|---|---|---|---|
| [x] | M3-AC01 | Capability truthfulness | A | Unknown, absent and unsupported remain distinct; unverified accessory controls are not enabled silently. Evidence: [current per-ID assessment](../../validation/M3-CAPABILITY-TRUTHFULNESS-ASSESSMENT-2026-09-17.md); [historical controls](../../validation/M3-AUTOMATED-CONTROLS-2026-09-15.md). |
| [x] | M3-AC02 | Settings validation | A | Every explicit choice is range/combination checked; unsupported options fail instead of silently clamping or dropping. Evidence: [2026-09-15 automated controls](../../validation/M3-AUTOMATED-CONTROLS-2026-09-15.md). |
| [ ] | M3-AC03 | Control coverage | A | Protocol mapping covers speed, darkness, thermal method, tracking, dimensions, offsets and supported finishing with cited semantics. |
| [x] | M3-AC04 | No implicit persistent mutation | A | Ordinary output has no reset/calibrate/save/erase/firmware commands; persistent actions require separate authorization. Evidence: [2026-09-15 automated controls](../../validation/M3-AUTOMATED-CONTROLS-2026-09-15.md). |
| [ ] | M3-AC05 | Network correctness | A | Short writes, backpressure, framing, zero-byte failure, mid-stream disconnect and timeouts pass simulator tests. |
| [ ] | M3-AC06 | USB path | H | The declared USB configuration prints and recovers from unplug/replug using a tested lifetime/cancellation contract. |
| [ ] | M3-AC07 | Cross-process serialization | I | Two real processes on different virtual queues cannot overlap device output or configuration; maintenance uses the same boundary. |
| [ ] | M3-AC08 | Crash/alias handling | I | Child/backend crash and connection aliases cannot bypass ownership or leave permanent stale locks. |
| [ ] | M3-AC09 | Uncertain delivery | I | Post-send ambiguity is visible and is not automatically replayed by the application or scheduler. |
| [ ] | M3-AC10 | Finishing behavior | H | Each advertised cut policy and peel wait/resume behavior is observed on matching installed hardware. |
| [ ] | M3-AC11 | State isolation | H | Alternating workflows with different supported settings produce intended results without accidental inheritance. |
| [ ] | M3-AC12 | Privacy and permissions | A | Endpoints/status frames/options are validated; logs and IPC do not expose private identities or allow arbitrary commands. |
| [x] | M3-AC13 | Installed GC420d constraints | A | Reference profile constrains pitch/speeds/direct-thermal/tear-off, rejects absent-cutter and disabled-peeler requests, preserves unknown sensing/current values, and never substitutes network transport for USB. Evidence: [2026-09-15 automated controls](../../validation/M3-AUTOMATED-CONTROLS-2026-09-15.md). |

## Completion rules

Check an item only after its exact evidence is recorded. Implemented is not physically tested. Account-free local signing is the active mode; future Developer-ID notarization is not an S1 blocker. Scope-specific nonapplicability is recorded with reasons and never silently becomes a global pass. Critical security, clipping, count/order or uncontrolled-replay defects block qualification. Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md), [progress](../../PROGRESS.json) and [scope status](../../SCOPE-STATUS.json).
