# M3 isolated layout analysis — 2026-09-16

The synthetic descriptor intake path now performs original-PDF page-box and
requested structural-border analysis in the existing bounded native worker,
before initial acceptance and during retry plan validation. It reuses
`QuartzPDFRenderer.documentPageBoxes`, `QuartzStructuralAnalyzer` and the
unchanged portable extraction planner. No thumbnail becomes a print source.

The fixed analysis operation shares private source staging, admission,
deadline/cancellation and owned-child termination with raster preparation.
The parent checks exact source digest, schema, page count, finite positive
box endpoints, physical geometry, rotations/UserUnit, requested anchor presence,
border-only kinds and normalized rectangles. Unperformed (`nil`) and observed
empty analysis remain distinct. Limits: 100 MiB input, 1,000 pages, 64 KiB
request, 2 MiB result, 256 anchors/page and 4,096 anchors/job. Over-limit analysis
is rejected, not truncated or silently dropped.

Real-child tests compare exact page boxes and structural facts for the supplied
native-vector, letter-one and layout-changed fixtures. Malformed/encrypted input,
out-of-range analysis pages, duplicate/invalid request pages, wrong source
binding/schema/geometry/kinds/presence, observed-empty facts and aggregate
anchor limits are covered. Shared existing render/extraction and connected
intake tests remain passing. An unavailable analysis worker now rejects before
accepted publication, preparation or send intent rather than parsing in-process.

Focused validation passed 25 worker/layout/intake tests. Full local
`bash scripts/ci-swift.sh` completed with exit 0: 67 Python, 166 Core and 163 Mac
tests in debug/release, 132 independent round trips, 15 backend and 10 filter
ABI cases, one inert pipeline case, and local ad-hoc command/app signatures.
Hosted exact-head CI and independent review remain pending.

This advances automated M2-AC09/M3-AC12 evidence. Each child has a 60-second
deadline, not a whole-job deadline. Source staging repeats per operation.
The setup UI's analysis calls are outside this intake change. Worker execution
is not a sandbox or a proved production identity/access contract. Scheduler
intake, privileged installation, USB and physical quality remain unverified.
