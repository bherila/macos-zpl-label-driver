# Native reserved margin rendering — 2026-09-17

Evaluated local unpublished 1c5ab7b2c706bd2af293efa3fba84e2d05307b60.

QuartzPDFRenderer.Request now carries typed output margins (default zero) into the physical placement planner. Drawing clips to the planner's visible rectangle, converted from top-down dots to Quartz coordinates. Clipping to the oversized actual-size target alone would allow content into reserved blank margins; clipping must use the inset intersection while the original drawing transform still uses the target.

The nearest independent constraints are physical uniform scale with non-square dot pitch, actual-size clipping, packed preview identity and zero-margin compatibility. A synthetic original solid-black square PDF at20×40dots with asymmetric margins must produce exactly the independently assembled packed rectangle x2..<16/y8..<36 for both fit and actual-size. Every packed blank/padding bit is checked; implicit and explicit zero renders must be identical for both policies.

Actual results:30native renderer debug tests passed (/tmp/zpl-margin-render-debug-final.log);37native renderer/planned-extraction release tests passed (/tmp/zpl-margin-render-release.log);106Python tests passed (/tmp/zpl-margin-render-python.log); repository preflight/diff passed. Own command exits0. Initial test compile mismatch between Data and [UInt8] was corrected before the passing runs; no before-fix runtime failure claimed.

Core source unchanged, latest309Core both-mode evidence belongs to the preceding immutable-definition slice. Full native/accelerator/signature/packaging/Linux/GUI/VoiceOver/scheduler/administrator/physical checks NOT RUN for this slice. This is an original-PDF renderer API foundation, not end-to-end margin workflow acceptance: both extraction parents still reject nonzero margins pending strict private ticket and worker propagation. Queue schema-v3 admission remains disabled. Next extend OfflineConversion ticket validation/render request and real subprocess tests, then remove parent guards together and add reviewed UI. No push, merge, publishing, device/queue/privilege operations; frozen PartB/Linux snapshots unchanged.

## File SHA256
- `Packages/LabelMac/Sources/LabelMac/QuartzPDFRenderer.swift`: `643e18d382242beaf14706dee0f78906a7ce7fad7b0fccbdcbf92963089d95da`
- `Packages/LabelMac/Tests/LabelMacTests/QuartzPDFRendererTests.swift`: `bb2d7a18f38b6836a1b01d59f82e72872108df118ba733848ecd944a99d95f8c`
