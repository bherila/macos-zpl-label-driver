# System validation plan

## Evidence levels

| Level | What it establishes | What it does not establish |
|---|---|---|
| A — automated | Pure functions, schemas, known fixtures, simulated faults, bit-exact encoding | Native print dialog, installed scheduler behavior or physical output |
| C — repository/configuration | Actual repo settings, CI execution, action pins and policy inspection | Product behavior not covered by executed tests |
| I — macOS integration | Real Mac frameworks/executables, queue/GUI/helper behavior on recorded runtime | Physical printing unless a real device was tested |
| H — hardware | Observed output/status/finishing on a named device configuration | Other resolutions, firmware, accessories or an entire model family |
| R — release | Exact candidate installation/distribution lifecycle, declared signing mode and provenance | Untested configurations or all future releases |

Hosted macOS can validate many noninteractive I tests. Application dialog, retail-host setup, privacy approvals, restart and physical devices often need a reviewed local session. Linux can validate portable Swift but not Apple frameworks. A printed label image shown on screen is not H evidence.

### Which session a criterion needs

The level says what a pass establishes. It does not say where one can be obtained, and that is the
question in front of an agent deciding what to work on: criteria at level `I` can need hosted CI, a
supervised GUI session, an installed scheduler on a test Mac, or a named reference Mac holding a
benchmark baseline. [`docs/test-surfaces.json`](test-surfaces.json) records that second answer for
every criterion, and `python3 scripts/check_test_surfaces.py` keeps it honest against
[`milestones.json`](milestones.json) -- the same identifiers, no orphans in either direction, a
surface whose declared level matches the level the criterion prescribes, and a `reach` drawn from a
closed set rather than from Python truthiness. A surface implies a level, so changing one without
the other is a contradiction the checker refuses rather than reports.

The checker does **not** constrain reach by level. An earlier revision refused any level `H` or `R`
surface that claimed per-pull-request reach, reasoning that CI must reach neither a private printer
nor the release gate. That rule is gone: a level says what a pass establishes, not whether a pull
request may obtain one. Level `R` describes an installation and distribution lifecycle rather than
the act of publishing, and a secret-free pull request could exercise an ad-hoc candidate's lifecycle
without publishing anything. The rule was the same conflation of the two questions this section
exists to undo. The honest basis for such a constraint is a declared **effect** -- writing to a
device, publishing an artifact -- and this map declares no effects.

These are two questions and the table keeps them apart. **Where** a pass can be obtained is the
surface. **Which pull requests reach it** is a separate column with three answers rather than two:
every ordinary pull request, only those whose changed paths select the surface, or none at all
because the pass needs apparatus the pull request under review does not have. Two surfaces may
share a location and differ in reach: `config` and `config-experiment` are both repository and CI
inspection, but proving that CI fails closed needs pull requests built for that purpose rather than
the one being reviewed.

| Surface | Level | Where a pass can be obtained | Which PRs reach it | Criteria |
|---|---|---|---|---|
| `automated` | A | Linux container and hosted `macos-26` CI | every ordinary PR | 30 |
| `installed` | I | test Mac with an installed scheduler or helper | none | 18 |
| `gui` | I | test Mac, interactive supervised session | none | 11 |
| `physical` | H | the named tear-off GC420d over USB | none | 8 |
| `macos-native` | I | hosted `macos-26` CI, noninteractive | only Swift-affecting PRs | 7 |
| `config` | C | repository and CI inspection on the PR under review | every ordinary PR | 4 |
| `release` | R | the release gate | none | 3 |
| `accessory` | H | a printer that actually has the cutter or peeler under test | none | 2 |
| `benchmark` | I | the named reference Mac, release build, retained baseline | none | 2 |
| `config-experiment` | C | dedicated pull requests, including a contributor-like fork | none | 2 |
| `bootstrap` | C | a fresh temporary checkout, and one against an existing repository | none | 1 |
| `per-claim` | I | one session per advertised claim, in the environment it names | none | 1 |
| `repo-settings` | C | an authenticated maintainer inspection of live repository settings | none | 1 |

`macos-native` is the whole reason the reach column has three answers. `.github/workflows/ci.yml`
gates `swift-macos-arm64` on the `swift_changed` output that `scripts/ci_scope.py` derives from the
changed paths, so a pull request touching only Markdown, `LICENSE`, `docs/PROGRESS.json`,
`docs/milestones.json` or `docs/requirements.json` never compiles anything natively and reaches none
of those seven criteria. The classifier fails open, so an uncertain diff still runs the job.
`automated` is not conditional in the same way: its portable tests run in the Linux container on any
branch whatever the diff contains, and hosted CI is an additional place they run rather than the
only one.

Seven surfaces exist because a single flag was carrying both questions. `config-experiment` holds
M0-AC06 and M0-AC09, whose evidence is an intentionally failing pull request, a documentation-only
pull request and a fork pull request -- repository inspection, but never of the pull request under
review. `bootstrap` holds M0-AC01, whose "before creation" is a one-time event the pull request
under review is made too late to observe, and which the M0 matrix reaches through a fresh-checkout
rehearsal and an existing-repository collision check. `repo-settings` holds M0-AC10, which asks
about private vulnerability reporting and branch protection -- settings the repository holds, not
files it contains, unreadable by a read-only pull request token and observable only by an
authenticated maintainer. Those two stay apart because their apparatus differs: a checkout anyone
can make against files, versus administrative access to a configuration. `benchmark` holds M2-AC12
and M6-AC09, because shared hosted-runner timing is informational here and a reviewed threshold
needs a named local setup. `accessory` holds M3-AC10 and M6-AC06, which need an approved accessory
target; the S1 unit is tear-off with no cutter and establishes nothing about them. `per-claim` holds
M6-AC11, which has no single session at all: an Intel claim needs execution on Intel, an IPP claim
needs its integration path exercised, and neither follows from a hosted Apple Silicon run.
`macos-native` is the seventh, above.

The map says where a criterion **can** be validated and nothing about whether it **has** been. That
is [`ACCEPTANCE-EVIDENCE.json`](ACCEPTANCE-EVIDENCE.json), and a surface here is never evidence
there. Reachable is not validated: sitting on a surface a pull request reaches is not a pass, and
the figures below count places, not results.

34 of 90 criteria sit on a surface every ordinary pull request reaches, 7 of 90 only when the pull
request's changed paths select that surface, and 49 of 90 need a separate named session.


## Required test layers

**Portable:** unit/property tests for checked geometry, units, canonical regions, profile/version validation, option precedence, copy/order plans, mono layout, encodings/decoders, state transitions and fault policy. Use deterministic seeds and bounded adversarial inputs.

**Mac framework:** real Quartz fixtures, supported PDF annotations/forms behavior, Vision availability, executable architecture, resource caps, cancellation and exact preview. Review platform-specific raster baselines separately from invariant encodings.

**Installed scheduler:** real CUPS jobs, typed options, held-job revision, input MIME/fidelity, permission boundaries, downstream lifecycle, cancellation and retry behavior. A shell-based cupsfilter run is useful but insufficient.

**GUI:** required applications/system dialogs; extraction editor; installation/repair/uninstall; accessibility; controlled diagnostic export. Save sanitized screenshots and steps. Do not automate clicks blindly on a user's working desktop.

**Physical:** approved finite label batches, stock/resolution checks, scanner payload equality, media/finishing behavior, competing queues and faults. Start with a three-label smoke budget; larger qualification batches need explicit consent. An initial quality campaign can use 30 labels per selected workflow/configuration, with the precise scope and consumable budget agreed first. Require all expected labels accounted for and all scans correct in that sample; do not turn this into a universal 'perfect' guarantee.

**Release (active local mode):** exact commit/artifacts, ad-hoc signatures/entitlements, local build/install and separately recorded quarantined-download behavior, target runtime/isolation, source/license notices, upgrade rollback, uninstall and compatibility report. Developer ID/notarization/stapling applies only to the deferred trusted-public mode, not S1. A clean user account is not a clean host.

## Fixture strategy

[Fixtures/catalog.json](../Fixtures/catalog.json) is a plan, not a claim that the assets exist. Generate original synthetic fixtures as the relevant milestones land. Prefer analytic vector shapes and synthetic addresses, account identifiers and barcode payloads. Commit only redistributable inputs with hashes, generator version, expected geometry/order and provenance. Do not distribute local font files.

Required fixture families: native-size label; Letter and A4; rotated/shifted boxes; high/low-resolution raster; transparency; small text; mixed vector/raster; multiple regions; mixed page sizes; instruction/customs pages; changed carrier layout; ambiguous candidates; encrypted/damaged input; absurd dimensions; non-byte-aligned rows; band boundaries; multi-copy/ordered sequences; malformed profile/status/IPC.

Golden policy: packed bitmap/encoder reconstructions are exact. PDF vector geometry has analytic structural checks. Fonts/anti-aliasing/Quartz changes may need reviewed OS-specific visual tolerances and baseline hashes. Never use indiscriminate golden refresh to dismiss defects.

## Fault matrix

| Boundary | Inject | Required outcome |
|---|---|---|
| Input/planning | Corrupt/encrypted input, mismatch, unsupported option, limits | No default device output; distinct error |
| Rendering/preparation | Timeout, worker crash, disk full, cancellation | Bounded cleanup; no default partial prepared-job send |
| Transmission before accepted bytes | Refused connection, immediate unplug | Safe failed/not-sent state; bounded retry only if proven safe |
| Transmission after possible bytes | Disconnect, backend death, power loss | Uncertain/partial state; no blind replay |
| Device handling | Paper/ribbon out, head open, peel wait | Actual supported state or unknown; not invented completion |
| Concurrency | Two queues, child dies, alias, maintenance | One ownership domain; no interleaving or permanent stale lease |
| Installation/update | Denied approval, replaced payload, interrupted write | Safe rollback/repair; no arbitrary privileged access |
| Recovery/uninstall | Restart, old profile revision, active job | Documented drain/cancel policy; owned resources only |

## Performance policy

Record cold/warm render/encode, peak RSS, prepared size, transfer time, first physical label and sustained rate separately. Initial engineering targets for a simple 4x6 203-class-DPI label on a reference M1-class Mac are warm render+encode p95 below 500 ms and peak processing memory below 256 MiB. These are proposed performance targets, not measured facts. M2 must measure; M6 must adopt explicit reviewed budgets and explain any changed targets. Do not mask a regression by switching fixtures or lowering quality. Shared CI timing is informational; use repeatable local reference runs for thresholds.

Actual dot pitch and all hardware dimensions come from the profile, not the '203-class' marketing shorthand. Physical positioning tolerance depends on model/stock and measured calibration; digital quantization is tested to the documented one-dot bound.

## Release gates

A usable qualified release requires mandatory features with the prescribed evidence. An experimental release may expose narrower work only with conspicuous limitations. 'Code complete' does not close H or R gates. Full feature-parity closure includes physical finishing validation for advertised cutters/peelers, not merely visible checkboxes.

No critical bug in privilege boundaries, resource handling, clipping, copies/order, uncontrolled replay or destructive device commands may be waived as 'CI passed'. Hardware that cannot be validated remains unverified. AirPrint/IPP compliance and barcode-quality certification are not inferred from basic operation.

## Reporting

Use the evidence template for each run. Link exact SHA, fixture/profile versions, environment, expected/actual observations and sanitized artifacts. Separate missing evidence from failed evidence. Requirements mapping is in REQUIREMENTS.md/requirements.json; milestone acceptance files are the checklist authority. PROGRESS.json tracks independent states, not an overall fabricated percentage.

## Revision-2 reference and scope rules

Use [GC420d/Tahoe first-run plan](validation/GC420D-TAHOE-FIRST-RUN.md). Confirmed target: GC420d USB, 4×6 pre-cut labels, tear-off/no cutter, macOS 26 minimum and local ad-hoc signing. No older Mac, Apple identity or cutter is required to proceed with this scope. Missing local hardware/GUI access still blocks corresponding evidence, not safe independent implementation.

Treat current dark/speed/geometry/status as unknown until observed. Validate the 8-dots/mm oracle and unsupported-option rejection automatically. Do not send ribbon/cutter/peel commands to satisfy generic tests on unsuitable hardware. Record those tests as not applicable to the installed S1 baseline while retaining S2 requirements. The first proposed three-label session remains subject to explicit consent; it has not been authorized by this document.

Global milestone state and scoped qualification are separate. Maintain PROGRESS.json and SCOPE-STATUS.json; do not mark global accessory evidence passed when only S1 was exercised. S3 trusted-public signing is deferred, not silently passed or an active credential blocker.
