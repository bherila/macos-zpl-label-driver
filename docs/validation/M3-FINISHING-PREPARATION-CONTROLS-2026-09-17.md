# Effective controls retained by finishing preparation — 2026-09-17

Partial M3 integration; no mechanical encoder or ordinary profile8 admission.
FinishingRasterPreparation now resolves controls against the retained immutable
profile and complete finishing plan before worker admission, then retains those
actual validated effective controls with original-source provenance and packed
rasters. Job/workflow/configured precedence uses the shared core resolver. A mode
is not inferred from the plan: effective request/default finishing must match it.
Invalid normal settings fail before a worker can run. validateControls re-resolves
against only the retained profile/policy and rejects changed effective controls,
even when source/raster inputs are identical. New drafts/revisions cannot replace
that stored profile through this API.

Every returned bitmap is checked against qualified controlled geometry and known
home/shift/top offsets using the existing core containment calculation. The public
qualification-aware validateRaster method adds an optional offsets parameter and
forwards it to the same bounded calculation used by ordinary encoder paths.
Default callers are unchanged. Unknown coordinates/device state remain unknown;
necessary containment is not physical fit proof. The synthetic native finishing
fixture independently declares thermal/media/ribbon, darkness, geometry and offsets;
it does not widen GC420d reference facts or qualify another physical model/pitch.

Nearest independent constraints: identical packed inputs cannot permit an effective
control substitution, and home plus shift must be evaluated together at the new
preparation boundary. Eight focused native cases pass with unchanged engine copy
count/original-child bitmap equality, retained cut/direct/zero/speed controls,
changed-speed rejection, invalid darkness before an inert worker, known right-edge
clipping rejection and positive home1/shift1 combination fitting the exact width.
Removing effective-control equality failed ownexit1. Removing offset forwarding
failed ownexit1 on the positive combination. Both restored byte-for-byte; eight
restored cases passed ownexit0. Source hashes:
preparation1e5d29ac4862b18501e2d572cc589337d11e18c5582fb986119be63c96a4863b;
geometryb29333ea2a299d67ffbf0c4eb8b9f7e3a2b0b75341e4c835e46b4463cc013271.
Finite900s full gate follows; no full terminal pass claimed yet.

Accepted queue/ticket/device identity, generic pitch qualification, normalized
mechanical commands/output file boundaries/cut schedules, peel waits and lifecycle/
manual/physical acceptance remain open. No printer/admin/GUI/merge/binary publication.
Frozen Part B unchanged.

Full finite900s gate is live under session25902, log
`/tmp/zpl-finishing-controls-preparation-full.log`; poll the same handle until terminal.

## Reviewed in-progress gate

Manual source review and tracked/new-file disclosure scan passed; both recorded
restored source hashes are unchanged. Same finite session25902 passed272Core
debug/release and independent oracle checks; inert/native/package stages remain
live. No full terminal pass claimed. Published1b88fb7 hosted35227758314 was freshly
observed in progress.

## Terminal full gate

Full finite900s session25902 completed ownexit0:89Python/272Core/323Mac debug/release,132 strict and180 ASCII oracle round trips per mode, finite benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable Developer-ID negative and packaged-worker PBM/ZPL equality. Artifact artifacts/setup-app.yFKWag. No printer accessed.
Manual source review and tracked/new-file disclosure scan passed; both restored hashes unchanged. No mechanical, installed, GUI or physical acceptance inferred.
