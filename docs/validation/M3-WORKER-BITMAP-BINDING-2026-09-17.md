# Shared parent packed-bitmap binding

Implementation checkpoint: `b424d61cfacc63e6dd74ff3be0c0c7d3b3f910cf` (local unpublished). Advances the exact packed-preview invariant and automated worker-output admission; M3-AC12 remains open for its complete privacy/permission assessment.

Ordinary readRenderOutput accepted substituted preview/ZPL artifacts when metadata byte counts agreed. The actual finite parent-worker regression reproduced three expected failures before the fix (own exit 1): same-length changed pixel, metadata/header dimension mismatch, and nonzero unused row-padding bits. Its valid positive control preserved exact preview/ZPL bytes. Fixture workers use owned private files and no printer or network operation.

Named independent constraint: every parent render route must admit only a canonical packed PBM matching the diagnostic ZPL bytes, independently of declared byte counts; extraction additionally must match its immutable expected canvas. WorkerBitmapBinding now provides the shared oracle. It checks schema/counts and bounded dimensions against the encoder's existing 32000-dot envelope, payload caps, bounds-checked layout/allocation, canonical header and exact packed length, MonochromeBitmap padding, then regenerated diagnosticFormat equality. Ordinary admission maps all failures to invalidResult; extraction retains expected-canvas checks and invalidWorkerBitmap errors and delegates to the same implementation. Original documents, typed controls, finishing qualification and encoder bytes are unchanged. No new protocol semantics, dependency, queue or raw-ZPL fallback was introduced.

Before creating the packed array, metadata dimension/size checks and preview length/header admission run. Tests enumerate Int.max axes, zero, 32001 and an over-budget 32000-square layout, plus an exact four-byte valid packed budget and three-byte rejection. Existing extraction tests retain truncated/extra PBM bytes, wrong headers, padding, ZPL substitution and canvas rejection. Ordinary Quartz/CLI tests preserve real original-PDF output, conversion and overwrite/rollback behavior. Finishing preparation still uses the same separately qualified route after the worker returns its diagnostic raster envelope.

Final validation: WorkerBitmapBindingTests, OfflineRenderWorkerTests, OfflineExtractionWorkerTests and QuartzPDFRendererTests executed 45 XCTest tests, zero failures, own exit 0 debug/release. Separate ProfileBoundFinishingJobPlanTests executed nine tests, zero failures, own exit 0 debug/release. Total 54 distinct selected native cases per mode; this is not a full 372-case suite claim. Repository preflight and 106 Python tests passed own exit 0. Disclosure scan/diff check passed and manually reviewed fixture material is synthetic. Logs: /tmp/zpl-worker-bitmap-before.log, /tmp/zpl-worker-bitmap-{debug,release,preflight,python}.log and /tmp/zpl-worker-bitmap-finishing-{debug,release}.log.

Parent re-encoding adds bounded validation work and transient allocations. No current performance/memory budget qualification is inferred from the focused tests. The invariant establishes preview/encoder correspondence, not proof that an arbitrary fixture worker faithfully rendered the original PDF or that ordinary result dimensions are independently bound to every request field; those are separate audit questions. Extraction's expected canvas remains checked. The full baseline at the preceding source is historical after this code change; current full Core/native CI-equivalent, packaging/signatures, Linux, GUI, scheduler/admin, USB, physical printer and release tests were NOT RUN for this slice. The existing Linux archive remains the frozen preceding evaluated source, not this implementation checkpoint.

No ledger acceptance was refreshed; no physical printer, queue modification, privilege, merge or publication occurred. Frozen Part B candidate is unchanged. Next: audit ordinary result-to-request binding and finish the remaining automated privacy scope, then perform source integration into existing PR81 with appropriate current CI/review evidence.

## Tested file hashes

Packages/LabelMac/Sources/LabelMac/WorkerBitmapBinding.swift: 2dbaafc73d4d4be0f3255f89010a8a8cec5e02b1f6407f99945221ba42482ce2

Packages/LabelMac/Sources/LabelMac/OfflineRenderWorker.swift: e12b848644a4fe734b6feab643f0ded1fd7c8ba334455dbd8e90539522249176

Packages/LabelMac/Sources/LabelMac/OfflineExtractionWorker.swift: d2c73fdf5fc27d34fac433c63b2abf4a8f0f8695086a71c6074e8e0db676e7d3

Packages/LabelMac/Tests/LabelMacTests/WorkerBitmapBindingTests.swift: d5a2e947e3a8adfeb03b7a866cd77898d5605f1874327d638a7cf2f8eb1ca17a

Packages/LabelMac/Tests/LabelMacTests/OfflineRenderWorkerTests.swift: ee8c789980ffbeab2d19f9f7fba6f420de09664a74d1e7b92a8e13ab89a4917a

