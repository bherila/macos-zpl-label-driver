# Revision 3 — implementation accelerator

**Baseline unchanged:** GC420d USB, 4x6 pre-cut stock, tear-off/no cutter, Tahoe
26 minimum, Apple Silicon first, MIT, account-free local ad-hoc signing.

This revision adds actual reusable code, synthetic inputs and validation tools.
It does not implement a usable driver or close the Mac/hardware gates. Review and
extend the supplied components rather than replacing them with another scaffold.

## Start with one offline command

From the repository root, with Swift 6 and Python 3 available:

```sh
python3 scripts/run-accelerator-checks.py
python3 scripts/run-accelerator-checks.py --configuration release
```

The command runs repository/fixture checks, Python tests, Swift tests/builds,
132 Swift-to-Python bitmap/ZPL round-trips, and 15 finite inert-probe ABI tests.
It also verifies that the lab refuses an existing output directory. Temporary
vectors are cleaned up. It needs no imaging packages, root access, Apple account,
GitHub connection, printer, simulator or network rendering service.

On Mac, continue to use `bash scripts/ci-swift.sh` for the full Mac-package and
local diagnostic-signature checks as well. The revised script includes the
accelerator in both debug and release configurations. The Linux integrity job
checks committed fixture hashes but does not claim to exercise Apple frameworks.

## What Codex can reuse immediately

| Component | Location | Responsibility and limit |
|---|---|---|
| Canonical monochrome value | `Packages/LabelCore/Sources/LabelCore/MonochromeBitmap.swift` | Validates count/stride/padding; thresholds already-flattened grayscale; exports exact PBM. Color/alpha processing is not implemented. |
| Banded graphics writer | `Packages/LabelCore/Sources/LabelCore/ZPLGraphicEncoder.swift` | Streaming uncompressed ASCII `^GF`; decoded-size limits; y offsets; preflight output budget; sink failure propagation. No printer state or transport. |
| Copy/order planner | `Packages/LabelCore/Sources/LabelCore/LabelOrderPlan.swift` | Select source pages before copy expansion; collated/uncollated ordering; explicit upstream-expanded mode; no deduplication or device quantities. |
| Inert Swift backend probe | `Packages/LabelCore/Sources/LabelCaptureProbe/main.swift` | CUPS ABI, bounded filename/stdin consumption, safe enumerated option observations, privacy and cancellation. Discard destination only. |
| Offline vector CLI | `Packages/LabelCore/Sources/LabelCoreLab/main.swift` | Produces deterministic analytic PBM/ZPL pairs. No PDF input or printer operation. |
| Independent test decoder | `scripts/zpl_oracle.py` | Strictly decodes only the emitted diagnostic subset; compares reconstructed pixels to PBM and independent analytic pattern. Not a general interpreter. |
| Concrete fixture corpus | `Fixtures/generated/` | 18 original PDFs / 28 pages and 3 original HTML files; regions, boxes, rotations, hashes, form policy and barcode payloads in the manifest. |
| M1 descriptor candidates | `experiments/cups-probe/` | Three original PPD candidates plus manual experiment instructions. Not installed or Tahoe-qualified. |

## Do not confuse diagnostic output with a prepared production job

`writeGraphicFields` deliberately does not reset origins/orientation, set stock,
choose speed/darkness, change media tracking, or expand copies. M3 owns those
validated choices. `diagnosticFormat` wraps fields in ONE format for offline
reconstruction, but inherited printer state can still affect actual output.
Do not connect this convenience envelope directly to a user's production queue.
The encoder cannot certify a bitmap's physical page placement or barcode quality.

The default 32 KiB decoded band budget is a project choice, not measured device
memory. Width/height command-coordinate limits are distinct from profile bounds.
Profile-specific margins, memory, media and resolution validation remains required.
A sink may throw after receiving part of a stream; callers must stage/discard
partial prepared output, not blindly replay device writes.

PBM is the exact-data developer preview [R32](REFERENCES.md#r32), not the final
SwiftUI preview implementation. `ProbeOptions` parses only this experiment's
enumerated choices; it is not a production replacement for CUPS option parsing.
No new public profile/wire format is implied by the test-vector JSON.

## How this changes the sprint

| Slice | Start from | Remaining work |
|---|---|---|
| M0.1–M0.3 | Full revision 3 package / reviewed revision-2 patch | Reconcile actual remote state; run native ARM CI; confirm full Mac builds and local signing. |
| M1.1–M1.2 | `labelprobe`, original PPD candidates and synthetic HTML/PDFs | Safe supported Tahoe placement, scheduler invocation, option UI and actual conversion-chain evidence. |
| M1 fidelity work | Manifest corner/region ground truth | Add bounded opt-in synthetic capture and native PDF inspection. Signature/byte count alone is insufficient. |
| M2.1 | Existing GC420d arithmetic tests, fixture geometry metadata, copy planner | Implement physical/page transforms and prove M1 ownership. |
| M2.2 | Concrete PDF corpus | Implement native Quartz renderer, input security/resource handling and real semantics. |
| M2.3–M2.4 | Packed bitmap, PBM, graphic writer, decoder and tests | Integrate rendering; validate state/profile contracts; real preview; accept criteria only with full evidence. |
| M2.5–M2.6 | Finite vector generation and stream API | Compression, real performance benchmarks, product CLI and proven filter integration. |
| M4 | Multiple-region and mismatch fixtures | Matching, teach-once UI, layout validation, workflow persistence and exact extraction. |

M3 controls/coordinator, M5 installer/UI and M6 qualification remain substantial.
Do not use this head start to bypass the M1 architecture gate or narrow the product.

## Corpus boundaries and a useful renderer finding

The fixture catalog remains partially covered. Encrypted/damaged PDF cases,
forms/annotations, adversarial IPC/status, real courier layouts and real browser
capture evidence are still outstanding. Source Code128/QR symbols are synthetic,
not labels that should be submitted to a courier.

During source checks, this environment's Poppler produced 2000x3000 pixels for
UserUnit=1 and 1000x1500 for the half-sized UserUnit=2 page at the same nominal
500-DPI flag, despite equal encoded physical face dimensions. Treat those raster
dimensions as an observation, not a desired geometry oracle. The Mac implementation
must establish its UserUnit semantics independently. This is exactly why a nominal
DPI command and a visually plausible page are insufficient evidence.

See [fixture instructions](../tools/fixtures/README.md), the
[probe experiment](../experiments/cups-probe/README.md), and
[preparation validation](ACCELERATOR-VALIDATION.md).

## First instruction to Codex

```text
Use revision 3. Read START-HERE.md and docs/ACCELERATOR.md, then the existing
M0/M1 instructions. Review and preserve the new regression tests and concrete
fixture corpus. Run the offline accelerator suite first, then native Mac CI.

Reuse the tested bitmap/graphic writer/order planner instead of generating
placeholder equivalents. The probe is discard-only and its PPDs are candidates,
not a working printer. Do not install or print without the existing explicit
consent boundaries. Prove the real Tahoe scheduler and local-signing path next.
```
