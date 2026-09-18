# Synthetic barcode decoding from final printer-dot bitmaps

Additional automated M2-AC02/05 and M4-AC13 regression evidence only.
M2-AC11 physical image-quality acceptance remains open. No scheduler, queue,
device, GUI, barcode certification or release acceptance is established.

The existing three-reference complete inert pipeline test now independently
decodes both Code128 and QR from each final 813 x 1219 canonical bitmap.
Inputs remain the supplied MIT synthetic native-vector, letter-one and a4-one
original PDFs. The supplied generator defines both symbols' expected payload
as `LPD-TEST-A-001`; source fixtures and hashes are unchanged.

Each final packed buffer is expanded through its exact grayscale preview: one
pixel per meaningful printer dot, white padding excluded. CGImage interpolation
is disabled. Apple Vision revision 3 is limited to Code128 and QR; the test
requires exactly one observation of each and exact synthetic payload equality.
There is no source-PDF decoding, analysis-thumbnail reuse, crop, upsampling,
photographic enhancement or tolerance relaxation. A blank bitmap at the same
geometry must produce no observations. Payload access is test-only; production
barcode analysis continues to read locations/symbologies only. See R36.

Existing assertions bind this bitmap to its exact PBM and complete encoded bytes,
and compare those bytes with the immutable prepared artifact consumed by the
persisted inert delivery path. Letter/A4 agree at every dot. This new oracle
supplements rather than replaces the supplied independent strict ZPL decoder;
that decoder and its 132 round trips are unchanged.

## Checks and limits

Before affected edits, `python3 scripts/run-accelerator-checks.py` passed exit 0:
132 independent round trips, 15 backend ABI, 10 filter ABI and one inert pipeline.
The initial native test failed to compile because importing Vision exposed its
own NormalizedRect type. Explicit LabelCore qualification corrected the test
namespace; no product implementation was changed. The subsequent single matrix
test passed exit 0 and decoded all six expected synthetic symbols at final
resolution. All 15 SyntheticInertJobPipelineTests then passed exit 0, including
the blank negative control. The full debug-release gate is pending at this
implementation checkpoint and will be recorded after execution.

Final full local gate at `c9f58fb8000ca3800b685047d80bf73cd091d625`:
`bash scripts/ci-swift.sh` passed exit 0 under a finite 1200-second outer limit.
67 Python, 178 LabelCore and 258 LabelMac tests passed in debug/release; both
accelerator configurations, 132 independent round trips and finite inert cases
per mode passed. Local-ad-hoc ARM/minimum-26 executable/app/nested-worker checks
and packaged-worker PBM/ZPL equality passed. The new local app artifact is
`artifacts/setup-app.veFrR6/Label Printer Driver Setup.app`, not a replacement
for the maintainer's separately pinned manual-check artifact. Publication edits
are documentation/manifest only. Own exact-head hosted CI awaits publication;
no extra correctness review is requested for this test/documentation-only slice.

Observed host: macOS 26.6.2 build 25G83, Apple Silicon, Swift 6.3.3,
Xcode 26.6 / SDK 26.5, project minimum 26.0. No 26.0 runtime pass is inferred.
Earlier 500-DPI Poppler/ZBar source checks are distinct historical evidence.
Digital decoding cannot prove thermal dot gain, label alignment, darkness,
physical dimensions or real scanner performance on the GC420d.

Next: hosted gate, then retain the finite physical scanner gate
under explicit named-device/label-budget consent. The administrator M1 admission
procedure remains separately prepared, NOT RUN.
