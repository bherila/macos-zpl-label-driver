# M5 — Native application, installation and distribution

**Dependencies:** Accepted M1 no-account adapter/install proof; M2–M4 components; no Developer ID required
**Goal:** Deliver a secure account-free local build/install/use/update/uninstall experience with native UI and virtual workflows.

## Native user experience

Build SwiftUI setup with AppKit bridges where needed. Default reference: GC420d USB, direct thermal, 4×6 pre-cut stock, tear-off/no cutter. Offer native/Letter/A4 workflows, confirm sensing/stock/defaults, and clearly distinguish unavailable versus unknown features. Peeler behavior stays disabled for the selected setup. Do not invent a USB URI or current darkness/speed.

Normal printing must work after closing the settings window and after restart under documented session/service conditions. Provide setup, reusable extraction editor, exact-output preview, system-dialog/default options, status/uncertainty, diagnostics, repair, update and uninstall. Keyboard/VoiceOver, useful units/errors and localizable strings are required. Preserve unrelated queues and default-printer settings.

## Account-free installation

Use the M1-evidenced narrow native installation mechanism on Tahoe; a guided Installer package or a narrowly authorized helper is acceptable only after its **no-account** admission/trust design passes. Local ad-hoc signing does not supply a publisher identity, Team ID or authorization. Never infer a helper's safety from matching bundle IDs or a user-writable checksum. See [LOCAL-SIGNING.md](../../LOCAL-SIGNING.md).

The user approves specific install/queue actions through OS-supported authorization, not an app-owned password field. Stage code and manifests safely; validate ownership/paths/content and guard symlink/substitution races. A persistent helper, if necessary, must have a reviewed client authorization and update story without Apple identity. No generic root commands, arbitrary file copies, user-home executables running as root, privileged PDF renderer, global CUPS policy changes or SIP/Gatekeeper disablement.

An unsigned outer package and ad-hoc-signed payload are distinct artifacts. Do not call such a package Developer-ID-signed or assume notarization. Record real OS approval and installer behavior; no promise of exactly one password dialog. A developer CLI may support experiments but does not satisfy the final native guided-install criterion.

Use a staged transaction, protected ownership manifest and rollback. Published immutable profiles are readable by the spooler without executing user-provided code. Test without dependencies on the build machine's Homebrew/Xcode runtime paths. A fresh account does not establish a clean system: record host cleanliness and preexisting approvals/helpers explicitly.

## Local signing and lifecycle

Build all Mac products with deployment target 26.0 and ARM-native components. Local ad-hoc signing is the default with no Apple account, Team ID, provisioning or signing secrets. Sign nested components deliberately inside-out and verify each plus its containing bundle. Extend CI when targets appear; do not hide missing signing coverage with deep signing or success placeholders.

A rebuild can change code hashes. Test two differently built locally signed versions through authorized upgrade, rollback and uninstall; ensure client/payload validation neither breaks updates nor relaxes to arbitrary callers. Keep immutable profile revisions for held jobs and do not remove runtime components active jobs still need. Never delete unrelated queues or profiles. Idempotent uninstall asks explicitly about preserving user profiles/history and handles partial installs safely.

Start with user-initiated local rebuild/install or explicit download-and-run of an accurately labeled local artifact. No automatic unsigned-code feed, unauthenticated self-updater or executable download during installation. Publication still requires separate maintainer approval.

## Active distribution and deferred trusted mode

Active scope S1 ships source/build instructions and an account-free local installation path. Exact artifacts carry source SHA, checksums, component signature mode, dependency notices, tests and limitations. Compare local build launch with quarantined downloaded launch separately; any supported per-item OS approval is explicit. No automatic quarantine stripping or global security bypass. A valid code signature is not a passed Gatekeeper or installed-spooler test.

Developer-ID signing, notarization and stapling are optional **deferred S3 work**, not active acceptance requirements or missing credentials to request. Preserve a separate future build mode that fails clearly if explicitly selected without credentials and never silently falls back. Any future protected signing workflow uses reviewed refs, least-privilege secrets and approvals. [Release scopes](../../RELEASE-SCOPES.md) governs claims.


## Related documents

Read [acceptance](ACCEPTANCE.md), [instructions](INSTRUCTIONS.md) and [validation](VALIDATION.md). Shared [contracts](../../CONTRACTS.md), [sprint baseline](../../SPRINT-BASELINE.md), [local signing](../../LOCAL-SIGNING.md), [release scopes](../../RELEASE-SCOPES.md) and [validation policy](../../VALIDATION-PLAN.md) apply.

## Primary references

[R01](../../REFERENCES.md#r01), [R15](../../REFERENCES.md#r15), [R16](../../REFERENCES.md#r16), [R17](../../REFERENCES.md#r17), [R18](../../REFERENCES.md#r18), [R21](../../REFERENCES.md#r21), [R26](../../REFERENCES.md#r26), [R27](../../REFERENCES.md#r27), [R28](../../REFERENCES.md#r28), [R29](../../REFERENCES.md#r29), [R30](../../REFERENCES.md#r30). Documentation supports APIs/model facts, not unperformed runtime or physical tests.
