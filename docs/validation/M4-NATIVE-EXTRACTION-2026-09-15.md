# Evidence — M4 native planned-region rendering

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `69dd2f5`
- Related requirement and acceptance IDs: F11, F12, M4-AC02, M4-AC07
- Evidence level: A
- Status: PASS
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: LabelMac Core Graphics renderer fed by an immutable
  LabelCore extraction plan
- Printer/transport/stock: synthetic PDF input and in-memory 72-dpi-equivalent
  canvases; no printer or transport was accessed
- Fixture/profile revision: generated 20-by-10-point vector PDF, including a
  `/Rotate 90` variant; synthetic workflow profile revision 8
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelMac \
  --filter QuartzPlannedExtractionTests
bash scripts/ci-swift.sh
```

## Expected and observed results

All six focused native extraction tests passed. The complete CI-equivalent
sequence also passed LabelCore and LabelMac in debug and release configurations,
the independent graphic oracle, backend/filter ABI tests, the inert pipeline,
and local ad-hoc signing checks.

The renderer re-derives the source page box, origin, rotation, and `/UserUnit`
from the original PDF. It verifies the planned source rectangle against that
geometry, clips the selected normalized region, applies only the existing
physical uniform-fit policy, and draws the original PDF page directly into the
final dot canvas. Tests establish exact selected-region packed bytes, all four
right-angle output rotations, upright normalized coordinates on a PDF page with
`/Rotate 90`, rejection of stale plan geometry and mismatched output stock, and
rejection of a near-zero region that would require an unbounded Quartz
transform.

The preparation API accepts the original PDF rather than an analysis bitmap.
Its PBM preview serializes the same `MonochromeBitmap` value passed to the ZPL
encoder. Structural analysis remains a separate typed-anchor input to the
planner, so analysis pixels cannot become print pixels through this API.

## Artifacts

- `Packages/LabelCore/Sources/LabelCore/ExtractionPlan.swift`
- `Packages/LabelMac/Sources/LabelMac/QuartzPDFRenderer.swift`
- `Packages/LabelMac/Sources/LabelMac/QuartzPlannedExtraction.swift`
- `Packages/LabelMac/Tests/LabelMacTests/QuartzPlannedExtractionTests.swift`

## Limitations / next action

This closes M4-AC02 and M4-AC07 at automated level. It does not prove native
analysis generation, teach-once UI behavior, application or browser capture,
scheduler integration, installed queue behavior, USB delivery, or physical
label quality. The next safe slice should generate bounded structural
observations from original-page analysis rasters and retain an explicit user
confirmation boundary for new matches.
