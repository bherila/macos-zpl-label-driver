# M1 — macOS printing integration proof

**Dependencies:** M0; local Tahoe 26 Mac for GUI/scheduler/no-account installation evidence
**Goal:** Prove full-page capture, native per-job controls and local-signing installation/runtime feasibility before committing to an adapter.

## Validation matrix

| Case | Environment | Procedure / oracle |
|---|---|---|
| Application capture matrix | Local Apple Silicon Mac | Print synthetic native-size, Letter and A4 fixtures in each required app. Save sanitized input metadata and screenshots of options. |
| Held-job revision | Local scheduler | Hold a synthetic job, publish new workflow/defaults, release the old job; inspect its revision and output mapping. |
| Transformation probes | Capture sink | Use numbered pages and copies=2 with collate on/off; page range 2; orientation/scale changes; number-up and mirror choices. Record exact captured sequences. |
| Permission/runtime probe | Installed test components | Compare direct invocation with scheduler invocation; verify access/denials and dynamic-library paths. |
| Downstream lifetime probe | Slow synthetic backend | Block the consumer after filter writes; start a second queue job. Verify the proposed owner cannot release access early. |
| Cleanup probe | Test queue only | Cancel, fail and uninstall the experiment; compare before/after queue/default settings. |
| Ad-hoc admission and authorization | Approved Tahoe capture setup | Sign without an account; install only inert experiment with consent; exercise spooler after UI exit/restart; test denied/tampered client or payload; record per-item approval separately from code verification. |

## Evidence and regression requirements

Record exact source SHA, toolchain/SDK/OS/app versions, observed configuration, profile/fixture IDs and hashes, expected/actual result, commands and artifact locations. NOT RUN/BLOCKED/FAIL/PASS are different. A zero exit without inspecting its expected result is not an oracle. Add a minimal regression with each corrected defect; do not update all goldens or hide errors to manufacture success.

Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md). For physical GC420d sessions use the [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) and obtain a finite named-device/job/label/command allowance first. Exact observed runtime is Tahoe 26.x, not an assumed old Mac. Record local ad-hoc signature verification separately from OS policy, installed-spooler and helper authorization.

A new user account is not a clean OS host. Hosted Mac tests are not USB/physical evidence. Unsupported accessory/transfer tests remain separate from the tear-off reference setup. Publish no serials, sensitive payloads or credentials.

## Exit report

List each acceptance ID with implementation state, achieved evidence, applicable scope and open restriction. Update progress/support only to the observed level. An implemented milestone with blocked hardware or GUI evidence is not globally accepted. No Apple Developer identity is needed for the active local scope; deferred trusted-public distribution remains deferred, not passed.
