# Evidence — M4 bounded local structural analysis

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `5ae58ea`
- Related requirement and acceptance IDs: F11, M4-AC04
- Evidence level: A
- Status: PASS
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: LabelMac Core Graphics analysis raster feeding the portable
  LabelCore border analyzer and extraction planner
- Printer/transport/stock: no printer, transport, queue, or physical stock was
  accessed
- Fixture/profile revision: committed `letter-one.pdf` and
  `layout-changed.pdf`; synthetic workflow revision 1
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelCore \
  --filter StructuralAnchorAnalyzerTests
swift test --package-path Packages/LabelMac \
  --filter QuartzStructuralAnalyzerTests
bash scripts/ci-swift.sh
```

## Expected and observed results

Five focused portable analyzer tests and three focused native fixture tests
passed. The complete CI-equivalent sequence passed 121 LabelCore tests and 53
LabelMac tests in both debug and release configurations, 56 Python tests, 132
independent graphics round trips, 15 backend ABI cases, ten filter ABI cases,
one inert pipeline, and local ad-hoc signature checks.

The analysis path renders an original PDF page into a private, aspect-correct
grayscale raster of at most 1024 by 1024 pixels. Its input bytes, source-page
count, pixels, detected line runs, candidate count, and pair-comparison work are
bounded. The portable analyzer handles padded rows and nonzero-index `Data`
slices, reports only typed normalized border rectangles, and exposes neither
analysis pixels nor document content to the final-render API.

The analyzer found the intended synthetic label border in `letter-one.pdf`
within 0.01 normalized-coordinate tolerance. An immutable profile built from
that observation planned the original fixture, while `layout-changed.pdf`
failed with `missingAnchor(page: 1, anchorID: "outer-border")` before a plan or
payload existed. Existing planner regressions separately distinguish missing
analysis, no match, shifted anchors, and competing candidates.

## Artifacts

- `Packages/LabelCore/Sources/LabelCore/StructuralAnchorAnalyzer.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/StructuralAnchorAnalyzerTests.swift`
- `Packages/LabelMac/Sources/LabelMac/QuartzStructuralAnalyzer.swift`
- `Packages/LabelMac/Tests/LabelMacTests/QuartzStructuralAnalyzerTests.swift`
- `Fixtures/generated/letter-one.pdf`
- `Fixtures/generated/layout-changed.pdf`

## Limitations / next action

This closes M4-AC04 at automated level. The first analyzer deliberately
recognizes rectangular borders only; barcode-like and dark-block adapters are
not qualified. It validates an existing profile and does not discover, save,
approve, or deliver a new profile, so no automatic confirmation bypass was
introduced. Offline behavior on the installed product path, teach-once user
confirmation, editor interaction, browser capture, queue integration, and
physical output remain unverified. The next safe slice should add an explicit
confirmation/qualification model before candidate discovery is connected to UI
or unattended matching.
