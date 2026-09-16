# Baseline control encoder speed boundary

Issue #78; automated defense for M3-AC02/13, not hardware qualification.
The public profile/resolution path allows a caller to declare arbitrary positive
speed choices. At parent `7d54fe3`, declaring 5, 99 or Int.max produces resolved
controls accepted by the GC420d-baseline encoder, contrary to its documented
2/3/4-ips subset (protocol table/R11). One old-code test reproduced three failed
rejection assertions. It uses public profile constructors and resolveControls,
not an inaccessible memberwise initializer or physical transport.

The baseline encoder now independently rejects unsupportedPrintSpeed(value)
outside 2/3/4. It does not clamp, silently omit, qualify a new model, or rely on
caller capability declarations to authorize a wider protocol subset. Existing
leave-unchanged behavior remains unchanged. Exact-output tests cover all three
documented speeds. The 19 focused control-resolution/profile/encoding tests
passed exit0. Full local gate at `bff05f438b151d2bfe44ba4bf3bd9461a98eb96d`
passed exit0 under a finite1200sec limit: 82 Python/180 Core/264 Mac debug/release,
both accelerator configurations (132 independent round trips, backend15/filter14/
pipeline1 per mode), local-ad-hoc ARM/minimum26 signatures and exact packaged
worker PBM/ZPL equality. Local app artifact:
`artifacts/setup-app.UU2cv9/Label Printer Driver Setup.app`; it does not replace
the separately pinned maintainer GUI artifact. Own hosted/review gates remain
pending. Later publication changes only evidence/manifest, not source.

Before-edit accelerator baseline is the unchanged source of PR77's full8ac3bbe
gate and latest7d54fe3 hosted35126325040: both independent/inert configurations
passed. The core bitmap, writer, planner, oracle and fixtures are not rebuilt.
No printer or scheduler was accessed by these tests. The private M1 snapshot's
original copied bytes are retained; new build products are never silently
substituted under an older signature/hash. Actual administrator, scheduler,
manual GUI and physical validation remain NOT RUN.
