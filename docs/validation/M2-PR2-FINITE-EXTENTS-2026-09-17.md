# PR2 finite PDF page-box extents

Source 2e56f2e3a38f80555cd6a81170adbfac97fe1f7a. Finite origin/size components can produce infinite original-coordinate corners. Admission now checks both summed corners after existing positive/finite component checks. Nearest independent constraints: all four rotations, UserUnit conversion, valid negative origin preservation and existing original-coordinate mapping. New test reproduces8overflow acceptances before fix and passes after fix; all four rotations preserve full negative-origin mapping. No later source-rectangle validator API is imported into this early slice.

Before targeted test exit1: /tmp/zpl-pr2-finite-extents-before.log. After targeted exit0: /tmp/zpl-pr2-finite-extents-after.log. Full scripts/ci-swift.sh finite900second wrapper exit0: /tmp/zpl-pr2-full-native.log;57Core debug/release, native scaffold Core Graphics tests both, both accelerator modes132cross-language/15inert ABI, ARM/min26 metadata/local-ad-hoc diagnostic signing passed.34Python/preflight/diff passed. No GUI/scheduler/administrator/printer/retail-runtime26 evidence. No acceptance completion manufactured.

This fix is additive on PR2's existing branch. Main advanced through separately authorized PR1 squash merge, so native stack82 needs cascading rebase/reconciliation and fresh exact-head CI before merging. Later implementation finite-extents fix uses a shared validator unavailable here; reconcile overlapping fixes when unpublished source is integrated. No shared branch force-push or physical I/O.

## File SHA256
- `Packages/LabelCore/Sources/LabelCore/PDFPageGeometry.swift`: `ca2d6e40242ee383e4cad224961bbbae1b5c7b4390eb71dd8d45cd300a57d932`
- `Packages/LabelCore/Tests/LabelCoreTests/PDFPageGeometryTests.swift`: `9fdaaa7b8b61aec1d440e1e171ba21c5c1961246e8b3cdcd171654eb1cf8827f`
