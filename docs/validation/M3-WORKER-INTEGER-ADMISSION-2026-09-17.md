# Fractional integer admission at worker protocol boundaries

Implementation checkpoint: `81f41cba1c28402aa3d51b26a5a08221d73ad4e8` (local unpublished). Advances M3-AC12 input validation without claiming the full privacy/permission criterion.

The actual render parent accepted six synthetic fractional integer fields after Foundation rounding: schemaVersion, widthDots, heightDots, zplBytes, previewBytes and workerMaximumResidentBytes. An inert finite worker emitted one-byte artifacts and metadata with one fractional field per invocation. All six expected rejection assertions failed before the fix (own exit 1). A separate conversion-ticket regression reproduced four rounded fractional fields: schemaVersion, pageNumber, conversion.cutoff and extraction.rotation (four expected failures, own exit 1).

Named independent constraint: fractional numeric tokens must never enter integer protocol fields, including nested array elements, while fractional geometry and optional null values retain their distinct meanings. WorkerProtocolJSON now performs bounded token-preserving admission before Codable decoding at five message routes:

| Message | Integer sites |
|---|---|
| Conversion ticket | schemaVersion, pageNumber, conversion.cutoff, extraction.rotation |
| Render result | schemaVersion, widthDots, heightDots, zplBytes, previewBytes, optional workerMaximumResidentBytes |
| Sanitized failure | schemaVersion |
| Layout request | schemaVersion, optional maximumPages, every structuralPages and barcodePages element |
| Layout result | schemaVersion and every pages element's rotation |

All seventeen declared paths are covered by the enumerated direct admission/actual ticket tests; the real render-boundary regression also verifies that no payload is returned on rejection. Missing fields, optional nulls and container requirements remain checked by Codable. Existing caller size caps apply before private-file decoding; shared traversal additionally bounds bytes, depth, nodes and tokens and rejects duplicate decoded keys. The current layout limits (1000 pages and 4096 aggregate anchors) fit the shared traversal node budget. Integers are checked mathematically from original number tokens without a Double admission step. Integral decimal/exponent spellings remain admitted, optional null remains optional, and geometry uses the existing Double decoding path. This slice rejects fractional integer inputs; it does not claim general integer-identity repair across all Codable consumers or canonicalize the decoded wire format.

Final validation: WorkerProtocolJSONTests, OfflineRenderWorkerTests and OfflineLayoutWorkerTests together executed 26 XCTest tests, zero failures, own exit 0 in both debug and release. Includes real original-PDF render/layout/barcode children, unchanged geometry/binding checks, finite deadline/cancellation cases, all declared integer paths, boolean/string/overflow/duplicate rejection and fractional geometry preservation. Earlier 25-test results preceded conversion-ticket integration and are not the final checkpoint. Repository preflight and 106 Python tests passed own exit 0. Source/diff disclosure scans found no key/token/email matches; manually reviewed material is synthetic. Logs: /tmp/zpl-worker-integers-before.log, /tmp/zpl-worker-ticket-integers-before.log, /tmp/zpl-worker-integers-final-{debug,release,preflight,python}.log.

Full current-source Core/native CI-equivalent baseline, packaged signature/fidelity, GUI, scheduler/admin, USB, physical printer, clean retail minimum-runtime and release validation were NOT RUN for this slice. Prior exact-source ledger results remain historical; no acceptance was refreshed. M3-AC12 remains unchecked. Other Codable consumers such as accepted-job archive manifests and scratch ownership records are not covered by this helper and require their own assessment. Production privileged IPC and installer admission remain unimplemented/qualified separately. No printer I/O, queue modification, privilege, merge or publication occurred; frozen Part B candidate remains unchanged.

Next: run a complete current-source native baseline and continue auditing worker result/artifact binding and remaining private-record admission; prepare source integration into existing PR81 without merging or binary publication.

## Tested file hashes

Packages/LabelMac/Sources/LabelMac/WorkerProtocolJSON.swift: 64e37e1111482e7fb24d3c4608d44a6c6af4bf17b7310064cc0bdcbdcbcf3fc7

Packages/LabelMac/Sources/LabelMac/OfflineRenderWorker.swift: d5f281bb9ca71ee059155f17913add089d498fe4ca103a7103ca4102ed0a611d

Packages/LabelMac/Sources/LabelMac/OfflineLayoutWorker.swift: 83884b359e3a20241c596d6d727e74cac81e660072aede8b3ab2e21584f98262

Packages/LabelMac/Sources/LabelMac/OfflineConversion.swift: 7e4ed87f476c3f885c233f840ced76793cd161958b3cfc7e320bf94a5a2a4bd4

Packages/LabelMac/Tests/LabelMacTests/WorkerProtocolJSONTests.swift: 1dd3aac3d2d766dc682decb8e435d02dc549f5a75da3858ec431249727ca4726

Packages/LabelMac/Tests/LabelMacTests/OfflineRenderWorkerTests.swift: 5d11458524fe3055666ff4edcc786643382bc0439f15df59c67053a3fc279f3c

