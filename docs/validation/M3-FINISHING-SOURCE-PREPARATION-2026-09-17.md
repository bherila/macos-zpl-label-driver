# Original-source finishing raster preparation — 2026-09-17

Partial M3 integration only; no mechanical command or transmission authority.
FinishingRasterPreparation renders actual original PDF bytes through the existing
isolated worker, retains their SHA256/byte count, the complete validated extraction
plan (including expanded copy order and accounted non-label pages), canvas and
monochrome conversion, and binds the resulting actual packed rasters to the exact
immutable finishing job. No downstream copy expansion occurs. Whole-plan equality
retains crop, rotation, source/output identity and workflow revision semantics.
A source-wide isolated analysis checks page count before rendering; unexpected
source pages fail instead of being silently discarded. Each extraction worker
also checks expected source geometry and exact returned canvas/padding/encoding.

Source input is bounded to100MiB. Packed geometry, pixels and complete estimated
byte count are checked before launching workers, with reporting-overflow arithmetic.
The finite total preparation deadline is positive and at most the existing60s
production budget; each worker receives only the remaining monotonic budget.
Cancellation is shared through analysis, rendering and packed-input binding.
A final budget/cancellation check covers source hashing before return. The result
retains actual immutable rasters, rather than pairing arbitrary bytes with a hash.

Canvas resolution is an explicit caller value, not model/pitch qualification.
This helper does not bind an accepted scheduler ticket, configured queue revision,
physical-device identity or qualified wire boundaries. It does not enable profile8
ordinary encoding, cut schedules or peel waits. Physical stock suitability remains
an installation declaration; geometry rendering is not physical verification.

## Focused evidence

Eight native focused cases passed ownexit0, including original child rendering,
exact repeated-copy worker equality, complete source/plan/canvas/conversion binding,
pre-worker count and byte-budget rejection, cancellation and unexpected-page rejection.
A same-size source mutation is independently rejected. Removing source-hash equality
made that assertion fail ownexit1; source restored byte-for-byte SHA256
bc78843d68cd035315441db3b158800fac00fffdfcf75d5360dfa4a920052fed.
Restored focused/full finite checks are next; no terminal full result claimed.
No printer, administrator, GUI, merge or binary publication action. Frozen B unchanged.

Restored eight focused cases passed ownexit0. Finite900s full gate is live under
session77319, log `/tmp/zpl-finishing-source-full.log`; poll that same process.

## In-progress full-gate observation

The same finite session77319 completed89Python,270Core debug/release and323Mac
debug with zero failures. Native release/build/package stages remain live; no full
pass claimed. Manual source review and tracked/new-file disclosure scan passed;
restored source hash remains unchanged. Hosted35226005783 for published186a76f
was freshly observed in progress, not successful.

## Terminal full gate

Full finite900s session77319 completed ownexit0:89Python/270Core/323Mac debug/release, independent strict and ASCII oracles, finite benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable Developer-ID negative and packaged-worker PBM/ZPL equality. Artifact artifacts/setup-app.0bWZBw. No printer accessed.
Manual source review and tracked/new-file disclosure scan passed. No installed scheduler, GUI, physical stock fit, model pitch or mechanical-wire qualification inferred.
