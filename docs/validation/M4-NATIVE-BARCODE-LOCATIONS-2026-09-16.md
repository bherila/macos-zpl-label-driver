# Bounded native barcode-location integration

## Scope

This is a location-only Apple Vision adapter connected to the existing
deadline-supervised original-PDF analysis worker, saved-workflow reopening and
synthetic immutable accepted/prepared/inert-delivery path. It is not a shipping
label finder, decoder/replacement engine or physical scanner qualification.
Primary API provenance is [R36](../REFERENCES.md#r36).

The first actual-raster fixture placement check failed before the shared Quartz
placement fix. That failure is retained in the
[separate imaging evidence](M2-EXPLICIT-QUARTZ-PLACEMENT-2026-09-16.md).
This adapter requires placement parent `f1912b3c8ff5d976c32be5e2f964932b3c76c01a`;
it does not alter fixtures or expected artwork to conceal the failure.

## Contracts and reuse

- The existing Quartz renderer supplies a bounded grayscale analysis image from
  the original PDF. Borders keep their existing 512 maximum-dimension path;
  barcode analysis uses at most 1024 on either axis and 1,048,576 pixels.
- Production Vision work executes in the existing unprivileged analysis child.
  Its synchronous framework request has no claimed in-process wall-clock bound;
  the child-owned deadline and parent cancellation/termination mechanism bound it.
- Revision 3 is selected before setting the narrow Code128/QR symbology set;
  unavailable API/model/perform results return sanitized detector-unavailable
  failure, never border-only fallback or an invented successful observation.
- Missing results are unavailable; a performed request returning an empty array
  is observed empty. Nonfinite, empty or out-of-range locations fail, not clamp.
- At most 64 barcode locations per page, 256 combined anchors per page and 4096
  total anchors enter the existing 2 MiB checked source-digest-bound result.
  Locations are sorted by canonical Y/X/extent; ambiguity is not deduplicated away.
- Only explicitly requested pages may return `barcodeLike` anchors. Barcode page
  numbers must be sorted/unique/in-range and included in structural analysis.
  Explicit barcode requests/results use private protocol version 2; border-only
  protocol version 1 remains supported. Old border-only results cannot acknowledge
  a version-2 request. This is not a new public profile/ticket schema.
- Payload strings/data and barcode descriptors are never accessed or serialized.
  Bounds are candidate checks, never inferred full-label crop regions.
- Reopening a saved profile requests barcode facts only where its immutable rules
  require them. Dark-block detection remains unsupported and explicitly rejected.
  New/default assistance remains border-based; manual opening is still explicit.
- The existing extraction planner validates requested location expectations.
  Final preparation uses the original document and unchanged crop/monochrome
  policy, not the detector bitmap. Reopened revisions require fresh bounds review;
  imports and detector observations do not create unattended qualification.

No bitmap, writer, ordering planner, independent decoder, renderer or concrete
fixture is replaced. The small shared analysis-raster extraction preserves the
supplied border analyzer's exact default behavior.

## Native validation

Observed: macOS 26.6.2 build 25G83, Apple Silicon, Xcode 26.6, SDK 26.5,
Swift 6.3.3. Minimum deployment remains 26.0; exact 26.0 runtime is not tested here.

PASS: 37 focused native tests: nine analysis-worker, one pure barcode-coordinate,
15 document-opening and 12 synthetic pipeline tests. These include:

- Actual child Vision detection from unchanged supplied `native-vector.pdf`.
  At least one location lies within the independent QR artwork quiet-zone square
  at (182,151), size 84, on the 288×432-point source, with a top/bottom discriminator.
  Repeated same-host results compare equal; border facts remain unchanged.
- A requested instructions page has an observed empty barcode array while the
  unrequested label page remains unobserved (`nil`), not falsely negative.
- Explicit request/version/page/result-kind/observation-count validation;
  unsupported dark blocks remain rejected. Pure coordinate tests include a valid
  top-edge rectangle, NaN/infinity/negative/empty/out-of-range negatives.
- Saved barcode-checked profile reopens through the real child as a fresh revision
  requiring review. Its packed preview equals explicit manual full-page preparation
  from the same original PDF; the earlier immutable record is unchanged.
- Two independent synthetic accepted/prepared/inert jobs using border versus
  barcode checks emit identical final ordered bytes from the original source.
  A wrong barcode-location expectation fails before publishing acceptance.
- Existing finite timeout, cancellation, stale-result and malformed-result cases
  remain exercised; detector-unavailable classification is sanitized. The native
  unavailable-framework branch itself is not forced by a fake production pass.

Supplied native source hash (unchanged):
`24af4c33cd98b4373048c3fdf88085a1da098e7cebc97b147d051fd99ecf5c61`.
Original MIT synthetic fixtures only; no customer labels, payload exports or
diagnostic screenshots are committed.

PENDING: full combined local gate, own exact-head hosted CI and review.
NOT RUN: external-network-disabled session, exact 26.0 runtime, positive Code128
qualification, carrier/template/browser matrix, actual GUI interaction, installed
scheduler, USB output, physical label alignment/scanning or clean-host distribution.
Code128 is deliberately selected but is not claimed accepted from enumeration or
the positive QR-location case.

This advances partial M4-AC04/07/09/12 and M2-AC02/09 evidence only. M4-AC09
remains unchecked: normal-network native API execution is not offline acceptance.

## Finite offline follow-up (NOT RUN)

On a test Mac, explicitly make external networking unavailable using the normal
OS controls or an isolated host; do not modify CUPS security or unrelated queues.
Record OS/build, exact commit and worker identity privately. Run once:

```sh
swift test --package-path Packages/LabelMac --filter OfflineLayoutWorkerTests.testRealBarcodeChildUsesOriginalQuartzRasterAndCanonicalFixturePlacement
```

Each owned native child has a five-second deadline. Inspect the expected positive
QR-location/independent-placement/repeated-result assertions; unavailable is an
explicit failure to record, not a reason to hide or skip the test. Restore only
the network state changed for this finite session. Then perform a separate manual
saved-profile reopen with no unattended approval: review candidate versus actual
label bounds and packed preview. Do not install a queue or print. Neither this
software procedure nor location detection replaces physical barcode scanning.
