# Successful worker result bound to immutable request canvas

Implementation checkpoint: `0315fbc236f1f553e13bb6a3e4e5f910133ab46c` (local unpublished). Advances immutable job-input geometry and automated worker-output admission; full M3-AC12/privacy and privileged integration acceptance remain open.

A canonical worker preview/ZPL pair could previously report a different canvas from the job ticket. A finite actual parent-worker regression reproduced three accepted mismatches (three expected assertion failures, own exit 1): 8.5 mm at one dot/mm requires width 9 rather than reported 8; requested height 2 rather than 1; and independent Y resolution requiring height 2. Each returned artifact was internally valid, so the earlier bitmap/ZPL binding oracle alone could not detect request substitution.

Nearest independent constraints: preserve canonical packed preview/ZPL equality and round-once geometry from original physical units with independent X/Y resolution; do not resize or reinterpret already rounded output dots. Three positive controls preserve exact bytes for 8x1 mm at one dot/mm, fractional 8.49x1.49 mm rounding to 8x1, and 4x1 mm with X/Y resolution 2/1 yielding 8x1. The parent now reconstructs the expected DotCanvas from the immutable ticket Data staged for this child and compares both returned dimensions. This is verification of the same physical inputs, not applying an extra scaling/rotation/copy transform.

The check runs only on the successful result path. Existing child-reported failure/deadline/cancellation classification remains ahead of it; invalid successful artifacts map to invalidResult without underlying private descriptions. No schema, encoder bytes, document source, stock, controls, finishing policy or device admission changed.

The preceding substitution regression's positive fixture was corrected to request its actual 8x1 canvas. Its final artifact cases now request each case's reported dimensions, keeping changed pixels, bad header dimensions and padding failures independent of the new request check. This tightens fixture coverage rather than weakening rejection criteria. The extraction caller's existing expected canvas check remains as an independent typed boundary.

Validation: 55 selected native cases across WorkerBitmapBindingTests, OfflineRenderWorkerTests, OfflineExtractionWorkerTests, QuartzPDFRendererTests and ProfileBoundFinishingJobPlanTests passed debug/release, zero failures, own exit 0. This includes real original-PDF rendering, ordinary CLI conversion/overwrite/rollback and qualified finishing preparation. After final fixture-only tightening, both actual parent regressions passed again: two tests debug/release, zero failures, own exit 0. The broader 55-test results precede only that fixture tightening, not a product-code change. Preflight and 106 Python tests passed own exit 0; diff/disclosure review passed with synthetic material. Logs: /tmp/zpl-worker-canvas-before.log, /tmp/zpl-worker-canvas-{debug,release,preflight,python}.log and /tmp/zpl-worker-canvas-final-{debug,release}.log.

The inert fixture workers establish request/result admission behavior, not faithful rendering of a PDF by an arbitrary supplied executable. Original-document rendering fidelity remains covered separately by actual renderer fixtures, not by claiming a malicious worker can be trusted because dimensions agree. Full current Core/native CI-equivalent baseline, packaging/signatures, Linux, GUI, scheduler/admin, USB, physical printer and release validation were NOT RUN for this slice. Earlier full baseline and Linux snapshot remain historical/frozen; no ledger acceptance was refreshed. Frozen Part B candidate and all manual/hardware gates are unchanged. No printer I/O, queue modification, privilege, merge or publication occurred.

Next: reconcile the remaining automated privacy scope and current manual gate state, then prepare coherent source integration into PR81 with appropriate current CI/review evidence.

## Tested file hashes

Packages/LabelMac/Sources/LabelMac/OfflineRenderWorker.swift: 32cb2a065ce22dba95b575988cf712cd136fe0e8e98d550a61105a009e723643

Packages/LabelMac/Tests/LabelMacTests/OfflineRenderWorkerTests.swift: 4e60a31f5410c6da3dfd9cfc85706b654ba06b8c5e9ba42ee498fc295addcdf0

