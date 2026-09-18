# M2 extraction-aware isolated worker ticket — 2026-09-16

Offline conversion ticket schema 1 retains its existing full-page fit/actual-size
behavior. Schema 2 requires an extraction object with a normalized upright
region, expected original-PDF source rectangle, and rotation 0/90/180/270.
It permits uniform fit only. Schema 1 rejects extraction fields; schema 2
rejects missing extraction; unknown versions remain rejected. Expected source
rectangles require finite positive extents with finite endpoints.

The existing renderer/worker are reused. Original PDF bytes, selected region,
rotation, and expected source rectangle reach `QuartzPDFRenderer` directly;
no thumbnail or replacement renderer is introduced. The worker still returns
only its bounded diagnostic ZPL and exact packed-bitmap PBM, not production
controls or transport authority. Invalid external geometry now preserves the
worker's sanitized geometry-invalid classification.

Native regressions run the real worker against the committed native-vector
fixture. Its rotated top-half region matches direct native conversion exactly
for PBM and diagnostic ZPL, and differs from the unrotated result. A mismatched
expected source rectangle fails as geometry-invalid. Contract regressions
reject schema-1 extraction, schema-2 omission, invalid rotation, and unknown
schema 3. Core tests reject NaN, empty extents, and endpoint overflow.

Local `bash scripts/ci-swift.sh` completed with exit 0 on Tahoe ARM:
repository preflight, 67 Python tests, 166 Core and 156 Mac tests in debug and
release, 132 independent round trips, 15 backend and 10 filter ABI cases,
one inert pipeline case, and ad-hoc command/app signatures passed. The focused
worker suite passed 11 tests. Automatic hosted run
[35072850127](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35072850127)
passed exact `e8ae1fd6b049028ee07aa802f6efe884672d905d`; inspected logs confirm
the 67/166/156 suites, oracle/ABI/inert cases, and ad-hoc signatures.
Independent PR #46 review completed cleanly at the same head, with a thumbs-up
and no inline findings. These are source/automated results, not installed acceptance.

This advances automated M2-AC02/09 only. Persisted synthetic intake still uses
in-process extraction; it must next bind/serialize its exact planned region
into this worker contract and validate the returned packed bitmap before
production encoding. No scheduler job, administrator action, USB, physical
printer, installation, or release occurred.
