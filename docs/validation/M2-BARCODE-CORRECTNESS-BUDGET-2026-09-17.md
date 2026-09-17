# Separate barcode correctness from short-deadline enforcement — 2026-09-17

The native barcode integration tests supplied an arbitrary five-second success
budget. Repeated local full gates on macOS27 failed in the parent worker wait,
while unchanged focused cases passed in about1.3–1.7seconds. The exact cause of
slow runs is not established. A temporary60-second diagnostic passed, and its
source was byte-restored; that run does not prove improved performance.

The production contract already specifies a60-second render cap, and
OfflineRenderWorkerProcess.defaultDeadlineSeconds is60. The two barcode correctness
cases now use that existing bounded default for analysis and complete synthetic
preparation, retaining all assertions for nonempty independently located QR bounds,
repeat equality, original-source prepared-byte equality and changed-anchor rejection.
This changes the test success budget from5 to60 explicitly. It does not relax a
production deadline, establish a five-second latency guarantee, change Vision revision
or bypass timeout handling. No hardware or scheduler evidence is substituted.

Dedicated owned-worker0.05-second timeout and synthetic preparation0.1-second deadline
cases remain unchanged, along with cancellation/parent-death/resource-limit tests.
The layout-worker, synthetic-pipeline and render-worker suites are running before a
new finite900-second full gate. Exact terminal results remain pending. Do not claim
that the platform/framework timing cause was repaired merely from a green run.

## Focused terminal evidence

Layout-worker9, synthetic-pipeline16 and render-worker11 tests passed ownexit0.
Dedicated short-deadline/cancellation cases passed alongside the real barcode
correctness assertions. Full gate remains live under session67662; no full-pass
claim. Previous published stock-plan checkpointa8c8db3 hosted35221905583 passed
at its exact source, and does not cover these new changes.

## Terminal combined validation

Finite900-second `bash scripts/ci-swift.sh` passed ownexit0 with the explicit
correctness-budget restructure:89 Python/270 Core/314 Mac debug/release,132 original
and180 ASCII oracle round trips per mode, finite benchmark/inert ABI/pipeline
harnesses, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable
Developer-ID negative and packaged-worker PBM/ZPL equality. Local artifact
`artifacts/setup-app.FwiqW0`. Earlier failures remain recorded; their timing cause
is not established. Automated results do not establish installed/GUI/physical
acceptance or five-second barcode latency.
