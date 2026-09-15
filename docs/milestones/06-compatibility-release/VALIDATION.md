# M6 — Compatibility, qualification and release gate

**Dependencies:** M1–M5 implemented for declared scope; actual Tahoe/GC420d/local-signing evidence; broader accessory tests remain separate
**Goal:** Qualify the promised workflows and maintain a truthful support matrix before publishing a usable release.

## Validation matrix

| Case | Environment | Procedure / oracle |
|---|---|---|
| Traceability audit | CI plus maintainer review | Resolve every requirement/acceptance ID to a PR, SHA and evidence level; reject empty pass claims. |
| OS/app matrix | Available target Macs | Run identical versioned fixture workflows on each claimed runtime; record unavailable minimum OS explicitly. |
| Physical regression set | Authorized printers | Print agreed finite batches per qualified configuration, scan and measure; record failures without selective exclusion. |
| Fault campaign | Authorized disposable queue/target | Inject the specified state-transition failures and inspect scheduler/backend/device results before retrying. |
| Reference benchmarks | Known local setup | Repeat release benchmarks with warm/cold separation, same fixtures/media and a recorded baseline. |
| Release rehearsal | Trusted environment and clean Mac | Install exact candidate, print, update/rollback/uninstall, verify provenance/signatures and review all advertised claims. |
| Scope applicability audit | Maintainer + evidence tooling | Compare all global acceptance IDs with S1 applicability and S2/S3 state; reject unqualified accessory/network/Intel/notarized claims or a baseline closure that hides critical gaps. |

## Evidence and regression requirements

Record exact source SHA, toolchain/SDK/OS/app versions, observed configuration, profile/fixture IDs and hashes, expected/actual result, commands and artifact locations. NOT RUN/BLOCKED/FAIL/PASS are different. A zero exit without inspecting its expected result is not an oracle. Add a minimal regression with each corrected defect; do not update all goldens or hide errors to manufacture success.

Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md). For physical GC420d sessions use the [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) and obtain a finite named-device/job/label/command allowance first. Exact observed runtime is Tahoe 26.x, not an assumed old Mac. Record local ad-hoc signature verification separately from OS policy, installed-spooler and helper authorization.

A new user account is not a clean OS host. Hosted Mac tests are not USB/physical evidence. Unsupported accessory/transfer tests remain separate from the tear-off reference setup. Publish no serials, sensitive payloads or credentials.

## Exit report

List each acceptance ID with implementation state, achieved evidence, applicable scope and open restriction. Update progress/support only to the observed level. An implemented milestone with blocked hardware or GUI evidence is not globally accepted. No Apple Developer identity is needed for the active local scope; deferred trusted-public distribution remains deferred, not passed.
