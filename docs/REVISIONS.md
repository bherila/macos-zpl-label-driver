# Handoff revisions

## Revision 2 — confirmed GC420d / USB / Tahoe 26 / local signing

**Prepared:** 2026-09-15. **Supersedes:** the initial handoff dated 2026-09-15.

This is a complete replacement handoff, not a patch archive. If implementation has already started, reconcile changes on a branch instead of overwriting source, decisions or evidence. No GitHub repository, printer queue or physical device was changed during this revision.

### Confirmed choices

The maintainer confirmed Zebra GC420d, USB, nominal 4 × 6-inch pre-cut stock, tear-off operation without a cutter, macOS Tahoe 26 as the minimum, MIT for original code, and local signing without an Apple Developer account. These are no longer questions for the coding agent. The local chip, exact OS build, firmware, USB identity, sensing method, gap, offsets and current darkness/speed remain observations to collect, not invented defaults.

### Changes to the existing handoff

| Area | Revision |
|---|---|
| Planning and startup | Replace proposed hardware/OS/license/signing assumptions with [the confirmed sprint baseline](SPRINT-BASELINE.md). Preserve six product milestones plus M0 and all 38 review-sized slices. |
| Platform | Both Swift package manifests target macOS 26.0. Required native CI uses standard `macos-26` ARM; optional Intel uses `macos-26-intel`. Remove older-macOS runtime matrices. Linux ARM still handles repository checks. |
| Hardware | Add a sourced [GC420d reference](hardware/GC420D.md) and a machine-readable planning seed. USB and direct-thermal tear-off are the first physical path; generic finishing/transfer/network abstractions remain in scope without claiming this unit supports them. |
| Geometry | Separate 8 dots/mm physical pitch from nominal 203-DPI advertisement and printable bounds. Add an exact rounding/stride/padding/banding oracle plus a portable layout regression test. Derived values are not physical calibration evidence. |
| Signing | Add [local-signing architecture and trust rules](LOCAL-SIGNING.md). Move account-free installed-filter/helper feasibility into M1. Developer ID/notarization is no longer an active sprint dependency. |
| Tooling | Add read-only Mac host preflight, an inert diagnostic ad-hoc-signature smoke script, an offline reference validator, and additional Python tests. CI invokes local-signature smoke without signing secrets. These do not install or print. |
| Acceptance | Preserve all 82 original acceptance IDs, revise applicable descriptions, and add eight criteria. There are now 90 acceptance criteria and 21 mapped requirements. All milestone specs, instructions, acceptance tables and validation plans are aligned. |
| Qualification | Add [three explicit release scopes](RELEASE-SCOPES.md). A GC420d-local qualification does not require borrowing a cutter or purchasing a Developer ID account. It also does not complete broader accessory/network or trusted-binary acceptance. |
| First run | Add a [Tahoe/GC420d first-session plan](validation/GC420D-TAHOE-FIRST-RUN.md) with host checks, inert capture, observation fields and a proposed three-label smoke. Hardware writes, queue changes and elevation still need explicit consent. |

### New acceptance IDs

`M0-AC11`, `M0-AC12`, `M1-AC13`, `M2-AC13`, `M3-AC13`, `M4-AC13`, `M5-AC13`, and `M6-AC13`.

The new requirement mappings are `F20` (reference hardware/platform baseline) and `F21` (account-free local distribution). Existing IDs remain stable for downstream issues and progress tracking. Acceptance wording was intentionally changed where the initial handoff incorrectly made trusted public signing a prerequisite for this maintainer's local release.

### Scope and truthfulness

There is no claim that a driver has been implemented or that macOS, hardware, browser, installation or Gatekeeper tests have run. [HANDOFF-VALIDATION.md](HANDOFF-VALIDATION.md) reports only the checks actually run on this revised scaffold. The source fixture catalog remains a plan; the geometry checks do not replace generated PDF fixtures or barcode scans.

`reference-target.json` is a handoff planning seed, not mutable live state and not a production capability profile. Its deliberately unknown observations and zero authorizations are checked as a baseline. Record real observations, permissions and test outcomes in separate appropriate runtime configuration/private evidence; never invent them or edit the seed to grant an agent blanket authority.

### Resume instruction

Read `START-HERE.md`, `AGENTS.md`, [SPRINT-BASELINE.md](SPRINT-BASELINE.md), [LOCAL-SIGNING.md](LOCAL-SIGNING.md) and [RELEASE-SCOPES.md](RELEASE-SCOPES.md), then execute M0 and the Tahoe/local-signing M1 gates. Continue independent safe implementation while manual evidence is pending. No further license, older-Mac or Apple-account decision is needed to start.

## Revision 3 — implementation accelerator

Added tested Swift packing/graphics/order components, an independent strict decoder,
an offline CLI, an inert CUPS ABI probe, three original PPD candidates and concrete
synthetic PDF/HTML inputs. Native CI now runs the accelerator checks. Existing
90 acceptance IDs and 38 implementation slices are retained; no hardware or
release gate is silently closed. See [ACCELERATOR.md](ACCELERATOR.md) and its
[validation report](ACCELERATOR-VALIDATION.md).
