# PDF page-box finite extents regression — 2026-09-17

Evaluated local unpublished source `2507d2c00983bcd6d542ee7288096c42ad2a8baa`. PDFPageBox now reuses PDFSourceRect finite, positive extent admission. Finite components with overflowing X/Y corner sums are rejected before rotation/UserUnit validation. Finite negative origins remain admitted. Derived rectangle transformations and public API are unchanged.

Nearest independent constraint: page boxes and external source rectangles share finite corner admission, independently of valid rotation and UserUnit. The new regression failed with eight assertions before the fix (exit 1), then passed for all four rotations and both overflowing axes, with finite negative-origin controls.

Validation: Core 302 tests debug/release; native QuartzPDFRendererTests and OfflineLayoutWorkerTests 38 tests debug/release; before/after accelerator checks; repository preflight and diff check. Every final command exited 0. Logs `/tmp/zpl-page-extents-*`. No full native CI, Linux, GUI, installed queue, privilege, printer I/O or physical evidence claimed. Previous full baselines and Linux snapshot remain historical/frozen. No ledger refresh, merge or publication.

Implementation digests:
- `Packages/LabelCore/Sources/LabelCore/PDFPageGeometry.swift`: `ddc670078c653f174e9d53fec29d81a230882756a8bd8c99fe9d6a455784cf64`
- `Packages/LabelCore/Tests/LabelCoreTests/PDFPageGeometryTests.swift`: `ad3e4ba6780b1a9f24293141401f5af486d9edbc5dc1d4ec5ceb8d2a6429a835`
