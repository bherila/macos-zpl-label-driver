# PR #69 crop/media intersection review remediation

Date: 2026-09-16. Evidence A, additional M2-AC01/03 and M4-AC02/07 coverage.
Correction/full-gate SHA: `68264a6464e1eeb403d32c8f250d46fec05119a5`.
No installed application/scheduler or physical acceptance.

First review finding
[4027048607](https://github.com/bherila/macos-zpl-label-driver/pull/69#discussion_r4027048607)
at head `03ea2fc8234c71597d64a56d4f161a1daa15f092`, base
`4a857a4f8a70768a3d54cad754402eb6f3d9db59`, correctly identified a selected-region
transform using declared CropBox bounds outside MediaBox. The previous native
geometry lookup also exposed those larger bounds to analysis and profile input.
Apple's transform defines its effective rectangle as the box/media intersection
[R08](../REFERENCES.md#r08); this is API provenance, not runtime acceptance.

## Native reproduction and fix

The existing analytic PDF helper now accepts a test-only explicit crop declaration.
Its original vector artwork and MediaBox stay fixed. CropBox `[-10 -10 20 20]`
extends beyond the 10x10-point MediaBox. Two pre-fix native tests failed with
seven failures (one unexpected): geometry reports the larger declared crop,
full versus full-region rendering differs, and an expected effective-space
half-region fails source validation. Initial compile-only harness errors were
corrected before this reproduction; they are not runtime evidence.

Native geometry now computes the effective intersection before upright rotation
and UserUnit conversion. Analysis, editor/planner page input, source validation
and final drawing therefore use the same origin/extent. The selected rectangle
is also intersected with the native effective rectangle before correction;
empty intersections fail. This retains direct selected-rectangle mapping and
does not restore the extra full-sheet expansion that caused the 35-dot variation.

Three permanent regressions require exact every-dot results:

- Expanded crop: effective 10x10-point geometry, full and full-region output
  both have the independently expected white top/black lower half.
- Half-region: effective original-space 0/0/5/10 selection renders the expected
  5x10-dot half-page without out-of-media bounds or source mismatch.
- Partial non-square overlap: crop `[5 -10 30 30]` retains effective origin 5/0,
  extent 5x10 and correct physical aspect in both full and selected rendering.
  A disjoint crop rejects with `invalidPageGeometry` rather than a fake page.

PASS: 49 focused native renderer/extraction/pipeline tests, exit 0, including all
three regressions, existing rotation/origin/UserUnit/near-zero bounds and the
complete native/Letter/A4 immutable prepared/inert matrix. Native environment:
macOS 26.6.2 build 25G83, Apple Silicon, Swift 6.3.3.
PASS: corrected full local `bash scripts/ci-swift.sh` at the correction SHA,
exit 0, bounded to 1200 seconds. 67 Python, 178 Core and 253 Mac tests
debug/release, both accelerator modes, 132 independent round trips per mode,
inert backend/filter ABI and discard pipeline checks, local-ad-hoc ARM/minimum-26
executable/app/nested-worker signatures and packaged-worker PBM/ZPL equality.
Publication evidence-only edits undergo repository preflight; no corrected
hosted/second-review pass is claimed before publication.
Original hosted 35106871876 passed at `03ea2fc`, with 178 Core/250 Mac tests
debug/release, signatures and packaged-worker PBM/ZPL equality verified in logs.
That result did not cover this edge case and is not a corrected-head pass.

## Boundaries

No fixture corpus, independent decoder or golden bitmap is changed. Previously
prepared artifacts remain immutable and are not rewritten or replayed. A saved
profile based on invalid out-of-media geometry must fail fresh validation and be
corrected/reviewed, not silently migrated. Normal contained-box workflows retain
their geometry and exact bitmap/byte checks. M2 semantics I, actual GUI, normal
application/browser intake, installed scheduler, USB, physical alignment/scanning
and release remain unproven. The maintainer's pinned GUI procedure is unchanged.
