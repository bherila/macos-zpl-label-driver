# M5 — Native application, installation and distribution

**Dependencies:** Accepted M1 no-account adapter/install proof; M2–M4 components; no Developer ID required
**Goal:** Deliver a secure account-free local build/install/use/update/uninstall experience with native UI and virtual workflows.

## Validation matrix

| Case | Environment | Procedure / oracle |
|---|---|---|
| Local native install | Approved Tahoe host; record cleanliness | Build/ad-hoc sign without Apple account, then use native guided install; record approvals/ownership; demonstrate no build-tool runtime dependency. A fresh account alone is not a fresh host. |
| Normal operation | Local Mac + approved GC420d session | Close UI, print, restart, repeat under finite budgets; check defaults, queue mapping and direct-thermal/tear-off restrictions. |
| Privilege/substitution attacks | Disposable approved setup | Reject wrong client, changed payload, unowned queue, arbitrary path, symlink/TOCTOU, oversized IPC and forged signing claims; no Team-ID dependency or relaxed fallback. |
| Distinct ad-hoc builds | Two reviewed source revisions | Sign both without certificates; upgrade and roll back through approved flow; verify new hashes and authorization, old-job/profile safety and unchanged unrelated queues. |
| Interrupted lifecycle | Disposable approved install | Interrupt staged install/update; repair; test idle/active/idempotent uninstall and profile-retention policy. |
| Accessibility/privacy | Local GUI review | Keyboard/VoiceOver walkthrough and sensitive-data-negative diagnostic export checks. |
| Local vs downloaded artifacts | Exact SHA; isolated Tahoe environments | Record code verification separately from Gatekeeper/package/installer/helper admission; observe supported per-item approvals without disabling protections. No notarization pass is expected or claimed. |

## Evidence and regression requirements

Record exact source SHA, toolchain/SDK/OS/app versions, observed configuration, profile/fixture IDs and hashes, expected/actual result, commands and artifact locations. NOT RUN/BLOCKED/FAIL/PASS are different. A zero exit without inspecting its expected result is not an oracle. Add a minimal regression with each corrected defect; do not update all goldens or hide errors to manufacture success.

Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md). For physical GC420d sessions use the [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) and obtain a finite named-device/job/label/command allowance first. Exact observed runtime is Tahoe 26.x, not an assumed old Mac. Record local ad-hoc signature verification separately from OS policy, installed-spooler and helper authorization.

A new user account is not a clean OS host. Hosted Mac tests are not USB/physical evidence. Unsupported accessory/transfer tests remain separate from the tear-off reference setup. Publish no serials, sensitive payloads or credentials.

## Exit report

List each acceptance ID with implementation state, achieved evidence, applicable scope and open restriction. Update progress/support only to the observed level. An implemented milestone with blocked hardware or GUI evidence is not globally accepted. No Apple Developer identity is needed for the active local scope; deferred trusted-public distribution remains deferred, not passed.
