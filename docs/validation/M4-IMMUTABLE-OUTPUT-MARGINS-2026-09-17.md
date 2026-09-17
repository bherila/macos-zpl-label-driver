# Immutable output margins — 2026-09-17

Evaluated local unpublished source 5464ebe0cb587e6517d9473418835202f3d43bbe.

## Requirement and independent constraints
M4 output margins now bind to immutable workflow definitions and each planned label. Schema v3 requires four finite nonnegative millimeter margins; legacy v2 remains zero-margin with unchanged JSON round-trip bytes. Definitions reject physically empty inset stock. Draft correction, page/region edits, valid stock edits, store correction and definition import preserve schema and margins. Invalid stock/margin edits fail before replacing the draft. Fresh imports still receive fresh identity and revision, without qualification evidence.

Nearest independent constraints are legacy serialization compatibility, immutable revision reconstruction, stock-change atomicity and original-source render admission. Tests exercise these combinations and strict missing/wrong-type/negative fields. Both native render parents explicitly reject nonzero margins before parsing or worker launch: the private worker contract does not yet carry margins. Queue/job schema-v3 reference admission remains disabled. This slice does not claim usable margin printing or measured calibration.

## Actual validation
- 309 Core debug tests passed; final accelerator debug repeats the strengthened valid-stock-edit assertion.
- Final 309 Core release tests passed, own exit0: /tmp/zpl-margin-profile-core-release-final.log.
- 87 focused native tests passed debug and release, own exits0: /tmp/zpl-margin-profile-native-{debug,release}.log. Covers render rejection, stores/imports, editor/bootstrap/document opening.
- Accelerator debug passed106Python/309Core,132strict/180compression/2privacy/12CLI/15ABI/14filter/1discard cases: /tmp/zpl-margin-profile-accelerator.log. Finite300s-per-command wrapper terminal exit0.
- Repository preflight and diff check passed. Initial new JSON planning fixture omitted expected page2 and correctly failed missingSourcePage(2); corrected fixture includes every expected page. No before-fix product failure claimed.

Full native/signature/packaging/accelerator-release/Linux/GUI/VoiceOver/scheduler/administrator/physical validation NOT RUN for this slice. Existing full380native and frozen Linux305Core snapshot remain historical at77de47c. No oracle/fixtures modified, acceptance ledger refresh, push, merge, stack registration, publication or device I/O. Frozen PartB candidate unchanged.

## Next step
Carry margins through strict private worker requests and original-PDF rendering with exact packed blank-area tests and parent byte equality. Then widen queue reference admission and add reviewed UI controls. Keep zero legacy behavior and fail closed until the complete render path supports margins.

## File SHA256
- `Packages/LabelCore/Sources/LabelCore/ExtractionPlan.swift`: `9970aff3b25c640eac190d31fa6230019d14dfdcadd3c2a6e6bc869635a73093`
- `Packages/LabelCore/Sources/LabelCore/WorkflowProfileDraft.swift`: `0763d6b3ebc870f2cf18b36ee59812bc49ba855e3871f303128c36815f5188a6`
- `Packages/LabelCore/Sources/LabelCore/WorkflowProfileJSON.swift`: `bf547ad847ee725c1dc36514c0a4f9b4a4bafeb56f63f05ac4c7e4eef07431c0`
- `Packages/LabelCore/Tests/LabelCoreTests/WorkflowProfileDraftTests.swift`: `ef50cf24407fb277c069e387da5ba18da2bf1dcf2330615ee9fcb535e6f8f42b`
- `Packages/LabelCore/Tests/LabelCoreTests/WorkflowProfileJSONTests.swift`: `dc61c5677a7c29b69885780784ce9d89a2d1811def77fb98b2612c2f125a4cc9`
- `Packages/LabelMac/Sources/LabelMac/OfflineExtractionWorker.swift`: `21f93c8ab45f14dec2922f29b1d4d96d2252b927bc2b46d2f56f1879839793f0`
- `Packages/LabelMac/Sources/LabelMac/QuartzPlannedExtraction.swift`: `01408a8a97d2f3c813cef6e1969b1a528013161f1b9ff497ef1e52a038089d57`
- `Packages/LabelMac/Sources/LabelMac/WorkflowProfileStore.swift`: `301ffc965763ab99230c4e38322612faeda6f566dbe9f5e37de92886104eeb73`
- `Packages/LabelMac/Sources/LabelMac/WorkflowProfileTransfer.swift`: `5b89c9dcb118d59527b70a23ffe7db9ef4d28ef978f98bff9e2fb9ff1620dd71`
- `Packages/LabelMac/Tests/LabelMacTests/QuartzPlannedExtractionTests.swift`: `844a3f820e610486a1969715888746265bc325ed2059b0d004a60a97d88455a0`
- `Packages/LabelMac/Tests/LabelMacTests/WorkflowProfileTransferTests.swift`: `5ccd1177951d0bb591b529229ac24c7de67f8dfc08782f0aea4c952bdaff780a`
