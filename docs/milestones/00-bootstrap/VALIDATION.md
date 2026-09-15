# M0 — Repository, project setup and CI

**Dependencies:** None
**Goal:** Establish a reproducible, honest starting repository and safe sequential development process.

## Validation matrix

| Case | Environment | Procedure / oracle |
|---|---|---|
| Bootstrap rehearsal | Fresh temporary checkout | Run the documented sequence without publishing, inspect staged files and ensure no hidden private content is added. |
| Core baseline | Linux or macOS with Swift | Run core debug/release tests and a release build. Record toolchain and architecture. |
| Mac baseline | macOS ARM runner | Run scripts/ci-swift.sh; diagnostic must be inert and return a real Core Graphics result. |
| CI positive/negative | GitHub PRs | Use one normal PR, one documentation-only change and one intentionally failing test on a temporary branch; remove only the intentional failure afterwards. |
| Repository collision | Existing test checkout | Re-run setup instructions against an existing repo and verify no reset/reinitialize/force push occurs. |
| Fork permissions | Contributor-like PR | Verify read-only checks and artifact policy without maintainer secrets. |
| Reference consistency | Offline/CI | Run baseline checker, malformed/mutated baseline regression tests, and ensure old Mac runner/deployment settings cannot silently return. |
| Local signing smoke | macOS 26 ARM | Run host preflight and ci-swift.sh; inspect exact OS/SDK/deployment, native executable and ad-hoc signature; no printer or installation activity. |

## Evidence and regression requirements

Record exact source SHA, toolchain/SDK/OS/app versions, observed configuration, profile/fixture IDs and hashes, expected/actual result, commands and artifact locations. NOT RUN/BLOCKED/FAIL/PASS are different. A zero exit without inspecting its expected result is not an oracle. Add a minimal regression with each corrected defect; do not update all goldens or hide errors to manufacture success.

Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md). For physical GC420d sessions use the [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) and obtain a finite named-device/job/label/command allowance first. Exact observed runtime is Tahoe 26.x, not an assumed old Mac. Record local ad-hoc signature verification separately from OS policy, installed-spooler and helper authorization.

A new user account is not a clean OS host. Hosted Mac tests are not USB/physical evidence. Unsupported accessory/transfer tests remain separate from the tear-off reference setup. Publish no serials, sensitive payloads or credentials.

## Exit report

List each acceptance ID with implementation state, achieved evidence, applicable scope and open restriction. Update progress/support only to the observed level. An implemented milestone with blocked hardware or GUI evidence is not globally accepted. No Apple Developer identity is needed for the active local scope; deferred trusted-public distribution remains deferred, not passed.
