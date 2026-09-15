# Epic — Native macOS Label Printer Driver

**Repository:** `bherila/macos-zpl-label-driver`
**Owner:** bherila
**Status:** planned; starter scaffold supplied, no printer support qualified.

## Outcome

Install once, configure one or more label workflows, then print directly from ordinary macOS applications. Control supported printer options, render sharp native-resolution labels, extract/rotate/scale labels from sheets and preserve correct ordering/status across virtual queues. Swift-first, Apple Silicon first, local-only by default, independently implemented from public references.

## Product requirements

All feature requirements are mapped in [REQUIREMENTS.md](docs/REQUIREMENTS.md). Shared architecture, contracts, security and evidence policies are normative. This is six product workstreams plus startup, not six commits. The proposed breakdown contains 38 PR-sized slices; individual commits may be smaller.

## Milestone checklist

| Done | Milestone | Dependencies | Suggested PR slices | Completion |
|---|---|---|---:|---|
| [ ] | [M0 — Repository, project setup and CI](docs/milestones/00-bootstrap/SPEC.md) | None | 4 | Exact prescribed evidence and scope, not code alone |
| [ ] | [M1 — macOS printing integration proof](docs/milestones/01-printing-integration/SPEC.md) | M0; local Tahoe 26 Mac for GUI/scheduler/no-account installation evidence | 5 | Exact prescribed evidence and scope, not code alone |
| [ ] | [M2 — Geometry, imaging and ZPL engine](docs/milestones/02-imaging-engine/SPEC.md) | M0; use M1 input/transform findings for production adapter integration | 6 | Exact prescribed evidence and scope, not code alone |
| [ ] | [M3 — Capabilities, controls, transport and job state](docs/milestones/03-printer-controls/SPEC.md) | M1 accepted transport boundary; M2 prepared output for end-to-end tests | 6 | Exact prescribed evidence and scope, not code alone |
| [ ] | [M4 — Sheet extraction and browser workflows](docs/milestones/04-label-extraction/SPEC.md) | M2 engine; M1 workflow media behavior; M3 profile/control integration | 6 | Exact prescribed evidence and scope, not code alone |
| [ ] | [M5 — Native application, installation and distribution](docs/milestones/05-product-distribution/SPEC.md) | Accepted M1 no-account adapter/install proof; M2–M4 components; no Developer ID required | 6 | Exact prescribed evidence and scope, not code alone |
| [ ] | [M6 — Compatibility, qualification and release gate](docs/milestones/06-compatibility-release/SPEC.md) | M1–M5 implemented for declared scope; actual Tahoe/GC420d/local-signing evidence; broader accessory tests remain separate | 5 | Exact prescribed evidence and scope, not code alone |

## Confirmed sprint baseline

GC420d USB, 4×6 pre-cut stock, tear-off/no cutter; Tahoe 26.0 minimum; MIT confirmed; local ad-hoc signing with no Apple Developer account. Read [baseline](docs/SPRINT-BASELINE.md), [hardware](docs/hardware/GC420D.md), [local signing](docs/LOCAL-SIGNING.md) and [release scopes](docs/RELEASE-SCOPES.md). No configuration is qualified by these inputs.

## Dependency flow

```text
M0 -> M1 (Tahoe input/options/local-signing admission and authorization gate)
 |      |
 +----> M2 -> M3 -> M4 -> M5 -> M6
```

Portable M2 and independent M3/M4 logic can proceed when local evidence is blocked, without presuming the adapter passed. Prioritize GC420d USB and keep simulated/generic accessory work separate.

## Review-sized implementation slices

### M0 — Repository, project setup and CI

- [ ] **M0.1 — Initialize and reconcile repository.** Confirm ownership/visibility; use already-confirmed MIT; retain existing history; import revised scaffold and baseline without private data.
- [ ] **M0.2 — Verify Swift package boundaries.** Build core/Mac targets on Tahoe, enforce 26.0 deployment, validate reference inputs and run secret-free local-ad-hoc diagnostic signing.
- [ ] **M0.3 — Activate and verify CI.** Execute macos-26 ARM CI; no pre-Tahoe matrix; prove docs-only/failing-code paths and the stable required check.
- [ ] **M0.4 — Establish contribution and evidence workflow.** Add/verify issue templates, security reporting, progress tracking, handoff and dependency policy.

### M1 — macOS printing integration proof

- [ ] **M1.1 — Implement inert filter/capture harness.** CUPS ABI parser, safe diagnostics, temporary-job handling, original experimental PPD and removable capture queue.
- [ ] **M1.2 — Measure document paths.** Synthetic PDF/HTML fixture capture across apps; full-page, MIME, vector/raster and transform observations.
- [ ] **M1.3 — Prove controls and defaults.** System generic options, option round-trips, immutable profile references and held-job behavior.
- [ ] **M1.4 — Prove execution and transport boundary.** Tahoe spooler/permissions, ad-hoc execution after restart, no-account installer/helper authorization spike, and actual downstream lifetime locking.
- [ ] **M1.5 — Record adapter go/no-go.** Evidence-backed ADR; alternate IPP spike only where necessary; list remaining integration risks.

### M2 — Geometry, imaging and ZPL engine

- [ ] **M2.1 — Implement geometry and page planning.** Checked units/transforms, exact-size/fit placement, crop region contract and test vectors. Include GC420d physical-pitch/stock/head-extent regression vectors.
- [ ] **M2.2 — Implement Quartz renderer.** White-background rendering, supported PDF semantics, bounded worker/input handling and regression fixtures.
- [ ] **M2.3 — Implement one-bit processing and preview.** Threshold/dither policies, packed bitmap types, exact preview and visual/structural tests.
- [ ] **M2.4 — Implement banded uncompressed ZPL.** Correct field counts/offsets, complete formats, test decoder and command limit checks.
- [ ] **M2.5 — Add lossless compression and benchmarks.** Capability-gated compression, cross-checks, allocation/throughput measurements and bounded staging.
- [ ] **M2.6 — Integrate CLI and proven filter path.** Typed job input, structured errors, cancellation/limits and integration with the accepted M1 adapter.

### M3 — Capabilities, controls, transport and job state

- [ ] **M3.1 — Implement capabilities and schema validation.** Typed tri-state capabilities, installed hardware, bounded profile loading and provenance. Prioritize GC420d direct-thermal/tear-off profile and explicit unknowns.
- [ ] **M3.2 — Implement controls and settings resolution.** Command mapping with model limits/persistence, per-job option resolution, offsets and media/thermal policies.
- [ ] **M3.3 — Implement network transport and state machine.** Inert/loopback fixtures first; partial-write handling, timeouts, receipts and retry boundaries. GC420d USB first; no network-only substitution.
- [ ] **M3.4 — Implement qualified USB path.** Reuse only a proven backend contract or add the required public transport adapter; support rediscovery and cancellation.
- [ ] **M3.5 — Implement physical-device coordination.** Cross-process lifetime ownership across all queues and maintenance; alias, crash and stale-lock tests.
- [ ] **M3.6 — Qualify finishing and fault handling.** Cutter/peeler behavior, status handling, persistent-state isolation and physical fault matrix.

### M4 — Sheet extraction and browser workflows

- [ ] **M4.1 — Implement extraction schema and planner.** Regions, page matching, order, quiet margins, mixed pages and default non-label handling.
- [ ] **M4.2 — Implement deterministic templates.** Letter/A4/native workflows, structural validators, layout versioning and negative fixtures.
- [ ] **M4.3 — Implement teach-once editor components.** Source selection, canonical coordinate editing, exact preview, keyboard interaction and profile import/export.
- [ ] **M4.4 — Implement assisted local detection.** Candidate generation, ambiguity/no-match states, optional Vision adapter and confirmation gate.
- [ ] **M4.5 — Integrate virtual workflow configurations.** Queue/profile bindings, defaults and per-job options preserving application-facing media.
- [ ] **M4.6 — Qualify browser extraction end to end.** App workflows, changed-layout failures, mixed/non-label pages, copies/order and recovery UX.

### M5 — Native application, installation and distribution

- [ ] **M5.1 — Build native setup and configuration UI.** App target, discovery/manual connection, stock/options, status and integrated extraction editor.
- [ ] **M5.2 — Implement queue/default management.** Owned virtual queues, immutable profile publication, clear default layers and restart behavior.
- [ ] **M5.3 — Implement narrow installer/helper.** Implement the M1-proven no-account authorization/staging/code-validation design; reject unsafe client/path/substitution requests and preserve native UX.
- [ ] **M5.4 — Implement lifecycle and recovery.** Transactional upgrade/rollback across distinct ad-hoc builds, repair, safe job drain, immutable profiles and idempotent uninstall.
- [ ] **M5.5 — Implement diagnostics and accessibility.** Privacy-reviewed export, useful errors/uncertainty, keyboard/VoiceOver and localizable text.
- [ ] **M5.6 — Build and validate local distribution.** Source/local-ad-hoc artifacts, native installation and quarantine characterization, checksums/notices/evidence; trusted-public mode explicitly deferred.

### M6 — Compatibility, qualification and release gate

- [ ] **M6.1 — Build compatibility matrix and evidence tooling.** Versioned support claims, evidence integrity checks and requirements coverage report.
- [ ] **M6.2 — Qualify OS/application/workflow paths.** Qualify observed Tahoe app workflows/native/extraction paths; record exact patch/build; no pre-Tahoe matrix.
- [ ] **M6.3 — Qualify hardware quality and faults.** GC420d geometry/scan/USB faults and concurrency first; track unavailable accessory/network physical qualification separately.
- [ ] **M6.4 — Benchmark and harden release candidate.** Reference-machine budgets, resource/security checks and regression fixes.
- [ ] **M6.5 — Complete release gate and scoped expansion ADR.** GC420d-local acceptance and local-signing evidence; truthful limitations/S2 backlog/S3 deferral; IPP/Intel only if independently qualified.

## Non-code gates and release scope

M1 requires actual Tahoe capture/options/spooler and no-account installer/helper evidence. M2–M6 require the matching automated/GUI/physical/lifecycle results. The first physical scope is GC420d-local, not a catalogue of printers. No older Mac, cutter or Apple identity is required to complete the applicable baseline; their absence is not evidence for broader features.

The full product target retains generic finishing/transfer/network capability work and appropriate hardware qualification. S1 success cannot close global S2 accessory gates. S3 Developer-ID/notarized binaries are deferred optional distribution, not an active credential blocker. Report exact source/local signature and approval limitations. Critical security, clipping, count/order or uncertain-replay defects cannot be waived.

## Out of scope for this baseline

Commercial implementation inspection; kernel extensions; cloud rendering/accounts/telemetry; automatic firmware/reset/calibration; speculative universal compatibility; barcode semantic reconstruction; mandatory IPP server; pre-Tahoe backports; paid signing or mandatory Apple accounts. These exclusions do not remove native/browser printing, extraction, supported controls, defaults or safe guided installation.

## Agent entry point

Read [START-HERE.md](START-HERE.md), [AGENTS.md](AGENTS.md), [EXECUTION.md](docs/EXECUTION.md) and all four documents for the next milestone. Reconcile the revised package safely, keep exact progress/handoff records, and continue independent work while evidence gates wait. No auto-merge, release or device/privilege operation beyond explicit authorization.
