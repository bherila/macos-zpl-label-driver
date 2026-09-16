# Explicit Quartz physical placement

## Scope and failure

The bounded original-document barcode feasibility check exposed a shared
renderer failure at parent `4a39317e9abecd74a10c22faa3cee1455a8158f3`:
the original 288×432-point supplied page occupied a centered raw-point-sized
rectangle inside the requested 683×1024-dot analysis canvas. Detection succeeded,
but its candidate failed the independently expected artwork placement. The
barcode adapter is paused; its success is not claimed by this record.

Two direct analytic regressions reproduced the renderer defect before correction:
`testEnlargementUsesPlannedDotRectangleForFitAndActualSize` and the strengthened
`testFitPreservesPhysicalAspectAtNonSquareResolution` failed with 12 assertions
across two tests. They discriminate enlargement and the full vertical extent,
not merely equality between two fitted pages or a central scanline.

The additional `testOddTrailingMarginMatchesCanonicalTopDownPlacement` failed
once before its correction: Quartz's bottom-up target used the planner's
top-down Y offset, putting an odd spare dot on the leading rather than trailing
edge. This is a separate coordinate-direction discriminator.

## Implementation and reuse

The existing portable physical planner, PDF geometry, Quartz renderer, bitmap
packing, ZPL graphic writer, extraction planner, fixtures and independent oracle
remain the implementation. No alternate renderer or regenerated goldens are added.

Quartz's public drawing transform retains its page rotation and crop/media
intersection. The renderer measures the transformed rectangle and composes an
explicit mapping to the independently rounded planned X/Y dot extent. All affine
operations happen before the one final original-PDF rasterization. Finite and
nondegenerate transforms are required before allocating the output buffer.
Top-down planned Y is converted to Quartz bottom-up Y before clipping/rotation.
No intermediate raster scaling, threshold policy, preview, profile schema,
encoding, delivery or printer-setting change is introduced.

Apple documents the page-box intersection, page rotation and rectangle mapping
in [CGPDFPage drawing transforms](https://developer.apple.com/documentation/coregraphics/cgpdfpage/getdrawingtransform(_:rect:rotate:preserveaspectratio:))
and [Quartz PDF transforms](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_pdf/dq_pdf.html).
The observed prior call is not generalized into a claim about every OS/API path.

## Validation

Observed runtime: macOS 26.6.2 build 25G83, Apple Silicon; Xcode 26.6,
SDK 26.5, Swift 6.3.3; minimum deployment remains macOS 26.0.

- PASS: 34 focused native tests: 25 renderer, six planned-extraction and three
  structural-analyzer tests. Existing rotation/origin/UserUnit/annotation cases
  remain green; no acceptance criterion or golden is weakened.
- PASS: supplied `native-vector.pdf` frame position at documented 8 dots/mm.
  Two independent whitespace scanlines require the actual artwork edges at
  x=10 and x=278 on its 288×432-point page, mapped to printer-dot coordinates.
- PASS: complete original fixture visually inspected with Poppler, then the
  corrected actual Quartz image inspected at 813×1219 dots. The centered
  raw-point-sized image is no longer present. This is screen/source evidence,
  not barcode scan or physical-label acceptance.
- PASS: before-work offline accelerator suite, including 132 independent
  round trips, 15 inert backend ABI, ten filter ABI and one discard-pipeline case.
- PASS: implementation `38fcee11c5bfec4cdd400a22be1760fd85043127`
  completed the full local gate exit 0: 67 Python, 173 LabelCore and 237 LabelMac
  tests in debug/release, both accelerator configurations, independent round
  trips, inert ABI/pipeline checks, local-ad-hoc signatures and packaged-worker
  PBM/ZPL equality. Repository preflight is repeated after evidence-only edits.
- PENDING: own hosted exact-head CI and review.
- NOT RUN: actual GUI interaction, network-disabled Vision, administrator
  installation, installed scheduler, USB delivery, physical printing/scanning,
  clean-host installation and public distribution.

Supplied source hash (unchanged):
`24af4c33cd98b4373048c3fdf88085a1da098e7cebc97b147d051fd99ecf5c61`.
It is original MIT synthetic artwork, not a real shipping label. Diagnostic
images/logs remain local and are not committed. The temporary PNG-writing test
diagnostic was removed; ordinary tests do not export source images.

This is additional automated M2-AC01/02/05/13 and M4-AC02/07 evidence, not
completion of PDF integration, local assistance or hardware acceptance.
Saved anchor definitions made using the former underscaled analysis are not
silently migrated or requalified. A layout mismatch requires explicit correction
as a new immutable revision. Already-prepared artifacts retain their exact bound
bytes; this change does not replay them or substitute a newly rendered payload.

## Next action

Publish this locally validated focused placement fix for review,
then restore the paused barcode worker integration and re-run its independent
artwork-location discriminator. The administrator M1 experiment remains a
separate finite, authorized operation; no printer commands or queue changes
occurred during this slice.
