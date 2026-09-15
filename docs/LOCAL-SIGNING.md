# Local signing and account-free installation

**Active mode: local ad-hoc signing. No Apple Developer account is available or required for this sprint.** This is macOS certificate-free ad-hoc signing, not iOS Ad Hoc provisioning/distribution.

## Three separate questions

1. Does the executable have a valid code signature for these bytes?
2. Does an OS policy accept its origin/identity for this operation or downloaded launch?
3. Has the user authorized a particular privileged installation or queue operation?

A successful `codesign --verify` answers only a part of the first question. An ad-hoc signature does not authenticate bherila as a publisher, supply an Apple Team ID, notarize code, or authorize privileged IPC. Apple documents code validity and subsystem trust as distinct [R28](REFERENCES.md#r28); ad-hoc signing is an explicit signature mode [R29](REFERENCES.md#r29).

## Build modes

| Mode | Active now? | Requirements and claim |
|---|---|---|
| `local-adhoc` | Yes; default | Identity `-`, no certificate/profile/team, no timestamp service; local/source-build provenance |
| Local certificate | Optional later | Explicit user-owned local identity; never install a trust root or create a keychain identity silently |
| `developer-id` | No; deferred | Explicit future identity, signing pipeline and notarization qualification; never silently fall back to local mode |

Xcode targets should use deliberate local/manual signing settings appropriate to the target: no required `DEVELOPMENT_TEAM`, no provisioning updates and no account-specific entitlements. CLI/helper Mach-O files must also be covered. Verify actual settings/output in CI; do not assume toggling one app target signs every nested executable. Keep the minimum deployment target 26.0 everywhere.

The scaffold includes `scripts/sign-local-diagnostic.sh`, which copies, ad-hoc signs, verifies and executes the **inert diagnostic only**. It performs no installation or printer I/O. Typical command semantics for a deliberately selected built binary are:

```sh
/usr/bin/codesign --force --sign - --timestamp=none path/to/local-binary
/usr/bin/codesign --verify --strict --verbose=2 path/to/local-binary
/usr/bin/codesign --display --verbose=4 path/to/local-binary
```

Check the target Mac's `man codesign` during M0. Do not add `--deep` signing to conceal missing nested signing rules. M5 must implement a deterministic inside-out component signing order and verify each component and the containing bundle. Signing is not proof of stable bit-for-bit release reproducibility.

## Early M1 feasibility gate

Prove locally signed filter/backend execution under the actual Tahoe scheduler, including after UI exit and restart. Separately prototype the intended installer authorization/helper lifecycle with **no Apple identity**. A normal user-shell launch is insufficient. No production installation design may depend implicitly on matching an Apple Team ID.

Prefer the smallest supported native mechanism: a guided Installer package is a candidate without a persistent privileged service; a narrow helper is another candidate only if its account-free authorization and trust design is evidenced. Do not promise a particular SMAppService acceptance rule based on API availability. Record actual approval steps and failures on Tahoe.

An unsigned outer `.pkg` containing ad-hoc-signed payloads is not a Developer-ID-signed installer. `codesign -s -` is not a substitute for an Installer signing identity. Treat package admission, payload code checks and installation authorization separately. If a local package is used, label its exact signing status and test the supported OS approval flow.

## Privileged boundary: no identity shortcuts

Do not authorize a root helper solely by bundle identifier, PID, caller-supplied path, 'signed code', or `anchor trusted`. Ad-hoc code can be re-signed by anyone. Per-artifact code hashes can change on rebuild and must not become an unreviewed user-writable allowlist for privileged execution. A checksum packaged beside writable code does not establish trusted provenance.

Use explicit OS-mediated authorization for narrowly specified operations; stage approved artifacts in a protected ownership boundary; validate final ownership/path/content after staging; address symlink/substitution/TOCTOU races and deny arbitrary commands. If a persistent helper is necessary, document how it authenticates/authorizes clients without a Team ID and how authorized updates replace its accepted code/version. Reject tampered or unexpected code; do not weaken checks to make ad-hoc builds work. Keep PDF parsing/rendering unprivileged.

A reviewed developer-only installation command may support M1 experiments. It does not satisfy M5's guided-install criterion. No embedded password prompts, root shell services, global CUPS policy changes, disabled SIP/Gatekeeper, or automatic quarantine stripping are acceptable substitutes.

## Launch and public OSS delivery

The primary artifact is source plus a reproducible local build/sign/install path. Clearly marked experimental local binaries may be published only with separate maintainer approval, checksums and exact signing status. Downloaded code can encounter Gatekeeper checks even when its code signature verifies. Apple describes per-app approval in Privacy & Security when available; this is not a blanket promise that every installer/helper/download will be accepted [R30](REFERENCES.md#r30).

Test a locally built path separately from a quarantined downloaded path. Report observed restrictions and use supported per-item approval where appropriate; never prescribe globally disabling protections. A clean test account is not a clean host: installed queues, root helpers and OS trust/approval history can be machine-wide. Record the exact test isolation level.

No notarization job, Apple secret, paid account request or trusted-public-distribution gate blocks GC420d-local development/qualification. A future Developer ID mode stays deferred, not passed. See [release scopes](RELEASE-SCOPES.md).
