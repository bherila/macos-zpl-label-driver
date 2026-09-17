# Portable output-margin placement — 2026-09-17

Evaluated local unpublished source2711a3f5b65e1fc5150fc7ce96d43cc7fd1b3e2d.

## Requirement and independent constraints
M4SPEC requires output margins/printable-region placement. OutputMargins describes finite nonnegative user-requested blank space in millimeters relative to nominal stock, not measured printer calibration or barcode-readability qualification. PagePlacementPlanner now accepts margins (default zero), uniformly fits physical source into the inset physical area, converts each reserved margin using original independent dot pitch and clips visible content to the inset dot area. Actual-size mode retains source dimensions and reports clipping. Defaults preserve the previous geometry contract.

Both fit and actual-size paths are exercised with asymmetric margins and non-square pitch. Hand-derived fit24×48dots is physically square at4×8dots/mm; actual40×80target clips to40×48within reserved bounds. Tests enumerate negative/nonfinite input at all4margin sites, physically empty and positive-but-quantized-empty areas across both policies, default/explicit-zero equivalence and overflowing actual-size target corners. Permissive huge geometry is checked without allocating a bitmap; checked addition rejects overflow rather than trapping.

## Actual validation
- 307 Core tests passed debug and release, own exits0; /tmp/zpl-output-margins-core-{debug,release}.log.
- Accelerator debug passed106Python/307Core plus132strict/180compression/2privacy/12CLI/15ABI/14filter/1inert discard cases, own exit0; /tmp/zpl-output-margins-accelerator.log.
- 35 native QuartzPDFRendererTests/QuartzPlannedExtractionTests passed debug and release, own exits0; /tmp/zpl-output-margins-native-{debug,release}.log. These preserve existing zero-margin original-document rendering; no explicit margin profile is carried into native rendering yet.
- Finite300second per-command wrapper completed; diff check passed. Existing full106Python/305Core/380native baseline at77de47c is historical after this source change.

New feature, no before-fix behavioral failure run claimed. Full native/accelerator-release/signature/packaging/Linux/GUI/VoiceOver/scheduler/administrator/physical tests NOT RUN for this slice. No fixtures, encoder or independent oracle changed. No acceptance ledger refresh or media/hardware qualification.

## Remaining implementation
Carry margins through immutable workflow profile/schema, planned labels, strict private worker request and original-source rendering, then expose editable/reviewed UI controls and test packed blank margins using actual workers. Preserve legacy zero-margin roundtrip/output and stock-change atomicity; reject margins that become invalid when stock changes. Keep requested content area distinct from unknown measured calibration. This foundation API does not complete profile/output-layout acceptance.

Published-head hosted CI remains separate. Frozen Linux77de47c snapshot predates margins; do not call it current. Frozen PartB candidate52ba93f and manual/physical gates unchanged. No source push, stack registration/rebase, merge or publication.

## File SHA256
- `Packages/LabelCore/Sources/LabelCore/PhysicalGeometry.swift`: `abbc389da0c262efa525f3a1a8c29f05d6cc06d147206c65c6bfb1ab557d845a`
- `Packages/LabelCore/Tests/LabelCoreTests/PhysicalGeometryTests.swift`: `11060d2f7e6159f0eca00621b7905c6cacd0bd3fb3971b9a425545e07040bb22`
