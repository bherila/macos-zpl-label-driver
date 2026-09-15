# M6 — Compatibility, qualification and release gate

**Dependencies:** M1–M5 implemented for declared scope; actual Tahoe/GC420d/local-signing evidence; broader accessory tests remain separate
**Goal:** Qualify the promised workflows and maintain a truthful support matrix before publishing a usable release.

## Compatibility scope

Maintain separate claims for OS runtime, architecture, printer model/resolution/firmware, connection, stock/accessories, application/version and extraction-layout revision. A successful compile or generic ZPL label is not evidence for every combination. Use planned, implemented-unverified, qualified, known-limited and unsupported states with evidence links. Initially no hardware row is qualified.

Apple Silicon and macOS 26.0 minimum are confirmed. Test the actual observed Tahoe 26.x runtime, record patch/build and guard later APIs; do not claim every patch or future major is tested. No pre-Tahoe matrix or older Mac is required. Intel remains separate and optional.

Require native-size and sheet-extraction workflows in Preview, Safari, Chrome and Firefox; qualify actual shipping-site layouts individually using synthetic/cleared samples. Broad 'all carrier sites' or 'all Zebra printers' claims are prohibited without evidence that cannot realistically be inferred from a few samples.

## Physical quality and finishing

Use authorized finite batches on the named reference configuration. Verify dimensions, orientation, positioning, readability and expected sequence/count. Exercise small text and representative 1D/2D barcodes, including rotated labels. Scan physical output and compare expected payloads locally. A scan-success claim is not an ISO print-quality grade; do not claim certification without the relevant verification process/equipment.

All advertised cutter/peeler policies require matching hardware evidence. If hardware is unavailable, keep those features implemented-unverified and clearly restricted; do not declare the full product parity gate complete.

## Fault and durability qualification

Exercise power loss, unplug/replug, media/ribbon out, open head, long peel wait, cancellation, sleep/wake, crash at state transitions, disk full, malformed status replies and competing virtual queues. Verify recovery distinguishes prepared, transmitted, device-confirmed and uncertain outcomes. No replay loop or unrecoverable stale lock is allowed. An isolated development queue must not disturb the maintainer's existing working queue.

## Performance

Record release-mode converter time, memory, bytes transferred, first-label time and sustained rate separately. Set reviewed budgets on a reference Mac/device/media, then compare regressions on the same setup. Short shared-runner benchmarks are informational. Full-speed claims must identify quality mode/media/connection and be supported by measurements, not just code-language choice or compression ratio.

## Optional expansion

Evaluate an IPP/PAPPL adapter against the same fidelity/options/defaults/workflow requirements. The interface boundary exists to permit it, but shipping an IPP server is not mandatory for the first feature-complete CUPS release if that release passes the selected OS gate. Do not advertise AirPrint or IPP Everywhere compliance from a server starting successfully. Additional printer languages, mobile platforms, Bluetooth and network sharing are separately approved follow-ups.

## Release gate

Create a requirements-to-evidence report for every mandatory requirement and acceptance item. A baseline experimental release may disclose incomplete gates; a usable/support-qualified release may not label unresolved critical gates complete. Full parity-target closure requires the promised printer controls, imaging, extraction, browser/system printing and product lifecycle, including physical tests for advertised accessories.

Publish source/build provenance, local-ad-hoc artifact checksums/signature state, known limitations, exact tested configurations and upgrade/uninstall guidance. Developer-ID/notarization work is deferred, not an active credential gate. No critical security/correctness defect may be waived by green CI. Leave hardware unsupported rather than presenting a confident false claim.

## Named first qualification scope

S1 is GC420d USB, 4×6 pre-cut stock, tear-off/no cutter on the observed Apple Silicon Tahoe host, with local ad-hoc build/install. Follow [release scopes](../../RELEASE-SCOPES.md) and [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md). Require full native/browser/extraction/control/lifecycle behavior applicable to this setup, real barcode/geometry/fault evidence and direct-thermal/tear-off option rejection.

Cutter/peeler/ribbon physical tests do not apply to this installation and remain open for suitable S2 hardware. Simulated generic coverage is not physical evidence; raw TCP or Intel compilation does not qualify those combinations. Do not require the maintainer to obtain an Apple Developer account, older Mac or cutter to complete S1. Keep global M3/M6 status and scope-level evidence separate so a baseline pass cannot close generic finishing gates.

Source-build/local delivery can be qualified with explicit local-signing constraints. Trusted-public notarized binaries are optional deferred S3. Per-item approval behavior and clean-host limits must be disclosed, not hidden behind `codesign --verify`.

## Related documents

Read [acceptance](ACCEPTANCE.md), [instructions](INSTRUCTIONS.md) and [validation](VALIDATION.md). Shared [contracts](../../CONTRACTS.md), [sprint baseline](../../SPRINT-BASELINE.md), [local signing](../../LOCAL-SIGNING.md), [release scopes](../../RELEASE-SCOPES.md) and [validation policy](../../VALIDATION-PLAN.md) apply.

## Primary references

[R05](../../REFERENCES.md#r05), [R06](../../REFERENCES.md#r06), [R16](../../REFERENCES.md#r16), [R17](../../REFERENCES.md#r17), [R18](../../REFERENCES.md#r18), [R25](../../REFERENCES.md#r25), [R26](../../REFERENCES.md#r26), [R27](../../REFERENCES.md#r27), [R28](../../REFERENCES.md#r28), [R29](../../REFERENCES.md#r29), [R30](../../REFERENCES.md#r30), [R31](../../REFERENCES.md#r31). Documentation supports APIs/model facts, not unperformed runtime or physical tests.
