# M3 — Capabilities, controls, transport and job state

**Dependencies:** M1 accepted transport boundary; M2 prepared output for end-to-end tests
**Goal:** Control real printer behavior safely, serialize virtual queues and report delivery uncertainty honestly.

## Validation matrix

| Case | Environment | Procedure / oracle |
|---|---|---|
| Protocol vectors | Portable suite | Generate expected sequences from documented profile settings; test bounds and all forbidden destructive command classes. |
| Network fault server | Loopback only | Accept variable-size writes, close before/after selected byte offsets, stall and emit bounded/malformed status replies. |
| Two-process contention | macOS inert backend | Start jobs from two queue processes, delay downstream consumption and inject child death; examine serialized transcript. |
| USB qualification | Approved real target | Print a small agreed batch; unplug before/mid/after transmission; reconnect and inspect job state before any manual retry. |
| Finishing qualification | Approved accessory target | Test finite per-label/batch/job-end cut sequences and peel removal waits; stop on unexpected mechanical action. |
| Setting leakage | Approved target/media | Alternate workflows; query supported settings or inspect test labels; verify persistent actions are not emitted. |
| Scheduler retry policy | Installed test queue | Force ambiguous backend failure and inspect actual queue behavior; prove no uncontrolled duplicate reprint. |
| GC420d negative options | Portable/profile integration tests | Reject thermal transfer, cut, peel, rewind, speed 5 and forged raw options before device I/O; missing current values remain unknown; simulate USB identity/status failures without assumptions. |

## Evidence and regression requirements

Record exact source SHA, toolchain/SDK/OS/app versions, observed configuration, profile/fixture IDs and hashes, expected/actual result, commands and artifact locations. NOT RUN/BLOCKED/FAIL/PASS are different. A zero exit without inspecting its expected result is not an oracle. Add a minimal regression with each corrected defect; do not update all goldens or hide errors to manufacture success.

Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md). For physical GC420d sessions use the [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) and obtain a finite named-device/job/label/command allowance first. Exact observed runtime is Tahoe 26.x, not an assumed old Mac. Record local ad-hoc signature verification separately from OS policy, installed-spooler and helper authorization.

A new user account is not a clean OS host. Hosted Mac tests are not USB/physical evidence. Unsupported accessory/transfer tests remain separate from the tear-off reference setup. Publish no serials, sensitive payloads or credentials.

## Exit report

List each acceptance ID with implementation state, achieved evidence, applicable scope and open restriction. Update progress/support only to the observed level. An implemented milestone with blocked hardware or GUI evidence is not globally accepted. No Apple Developer identity is needed for the active local scope; deferred trusted-public distribution remains deferred, not passed.
