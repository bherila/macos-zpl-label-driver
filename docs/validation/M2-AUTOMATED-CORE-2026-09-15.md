# Evidence — M2 automated imaging core

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `3ad4bf07c22e9f177d8ee6913edf479e36aab366`
- Related requirement and acceptance IDs: F07, M2-AC01, M2-AC02,
  M2-AC04, M2-AC05, M2-AC06, M2-AC09, M2-AC13
- Evidence level: A
- Status: PASS
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: portable LabelCore engine, native LabelMac Quartz renderer,
  private offline render worker, and offline `label-driver` CLI
- Printer/transport/stock: no printer or transport was accessed; GC420d
  geometry is a documented arithmetic oracle only
- Fixture set: committed generated fixture manifest, 19 PDFs / 29 pages and
  three HTML fixtures; hashes are fixed by `Fixtures/generated/manifest.json`
- Profile/job-ticket revision: version-1 offline ticket and typed GC420d
  reference geometry; no installed profile was read
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

The clean exact commit above was exercised with the repository's macOS
CI-equivalent command:

```sh
bash scripts/ci-swift.sh
```

That command ran repository and fixture preflight, all Python tests, LabelCore
debug and release tests, the independent Python ZPL/PBM/analytic oracle, the
inert backend/filter ABI checks, the inert pipeline check, LabelMac debug and
release tests, product architecture/minimum-OS checks, and local ad-hoc
signature verification.

## Expected and observed results

The complete sequence passed at the cited commit:

- Repository preflight and fixture integrity passed for 19 PDFs / 29 pages and
  three HTML fixtures.
- 56 Python tests passed.
- LabelCore passed 98 tests in both debug and release configurations.
- 132 independently decoded ZPL/PBM/analytic round trips passed.
- The inert checks passed 15 backend ABI cases, ten filter ABI cases, and one
  filter-to-discard pipeline case.
- LabelMac passed 44 tests in both debug and release configurations.
- All three command products were arm64, declared macOS 26, and passed local
  ad-hoc signature verification.

The acceptance mapping is:

- **M2-AC01:** `PDFPageGeometryTests`, `PhysicalGeometryTests`, and native
  Quartz regressions exercise crop-box origins, all right-angle rotations,
  `/UserUnit`, independent X/Y pitch, fit/actual-size placement, clipping, and
  nearest-dot rounding. The quantization bound is at most half a dot and thus
  within the one-dot criterion.
- **M2-AC02:** `QuartzPDFRendererTests` passes original PDF bytes directly to
  Core Graphics, `QuartzPDFToMonochrome` renders that original source into the
  final dot canvas, and `OfflineConversion` passes the resulting pixels to the
  selected monochrome policy. No thumbnail participates in that path.
- **M2-AC04:** `BitmapLayoutTests` and `MonochromeBitmapTests` verify top-down,
  MSB-first, 1=black packing, exact stride, zero tail bits, and widths 1, 7, 8,
  9, 811, 812, and 813.
- **M2-AC05:** the canonical PBM preview contains the bitmap's exact packed
  payload; preview expansion excludes tail padding. The independent oracle
  decodes the ZPL and requires equality among encoder input, PBM payload, and
  its own analytic bitmap for every vector.
- **M2-AC06:** `ZPLGraphicEncoderTests` enforce field-coordinate, row-size,
  output-budget, and chunk bounds. The independent strict decoder rejects
  unsupported syntax, origin/stride/count mismatches, invalid hex and padding,
  and reconstructs every band with the expected row sequence. The 813x1219
  reference splits into 321/321/321/256 rows with 124,338 bytes total.
- **M2-AC09:** geometry, packed-bitmap, PDF byte/page/pixel, ticket, output, and
  worker-artifact limits have boundary and overflow coverage. Concrete
  malformed and encrypted PDFs, annotation policy failures, worker deadlines,
  task cancellation, CLI SIGTERM cancellation, symlink/type/identity drift,
  and failed final-output creation are rejected without final prepared output
  or default delivery.
- **M2-AC13:** independent physical arithmetic fixes 8 dots/mm as the geometry
  source and produces 813x1219 dots, 102 bytes per row, 124,338 packed bytes,
  three white tail bits, and the complete band reconstruction. Tests keep
  nominal DPI, media face, head width, gap, and liner concepts distinct.

## Artifacts

- `Packages/LabelCore/Tests/LabelCoreTests`
- `Packages/LabelMac/Tests/LabelMacTests`
- `scripts/zpl_oracle.py` and `scripts/tests/test_zpl_oracle.py`
- `Fixtures/generated/manifest.json`
- GitHub exact-head run for the immediately preceding implementation head:
  <https://github.com/bherila/macos-zpl-label-driver/actions/runs/35033301182>

## Limitations / next action

This evidence closes only the seven automated rows named above. It does not
establish the M2 PDF visual integration contract (M2-AC03), compression
(M2-AC07), M1-integrated copy ownership (M2-AC08), installed filter behavior
(M2-AC10), physical image quality (M2-AC11), scheduler admission, USB delivery,
or printer acceptance. Uncompressed diagnostic encoding remains intentional
until the simple physical path is independently validated. The already-recorded
performance baseline separately closes M2-AC12 for its declared offline scope.
