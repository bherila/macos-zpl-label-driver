# Qualified motor speed persistence and inert delivery — 2026-09-17

Additional partial M3-AC02/03/11, M2-AC08, M4-AC12 only. No physical state
isolation, scheduler or installed control qualification is established.

## Implementation

Feed and backfeed have separate qualified choice sets with distinct unknown,
unsupported and supported facts. Profile construction rejects unsupported/unknown
nonempty choices, supported empty choices, supported unobserved evidence and
values outside the implemented2..12 ips subset. GC420d reference facts remain
unknown; neither ordinary setup nor legacy persisted files are promoted.

Version3 private profiles store both facts/choices and nullable defaults.
Version2 virtual queues store nullable choices. Version3 tickets capture resolved
values, retaining profile/queue revision and hash references. Version1/2 profile,
version1 queue and version2 ticket canonical formats remain unchanged and reject
new fields. No automatic migration or revision rewrite. Missing, Boolean,
duplicate, extreme, unsupported and downgraded data fails closed.

Explicit job choices override workflow defaults, which override configured
device defaults per field. Selecting either motor speed requires all three
resolved values. The ordinary typed encoder then emits `^PRp,s,b` with no omitted
parameters. R45 records primary semantics and persistence; the existing print
speed2/3/4 encoder subset remains enforced. Other unqualified ordinary controls
stay unavailable. Profile qualification is a supplied declaration, not evidence
that an installed unit supports a declared rate.

Immutable prepared labels and complete jobs retain both resolved values. Mixing
same-length labels with different feed settings on the same profile revision
fails controlsMismatch. The native inert pipeline now hands the same workflow
choices into ticket acceptance and final preparation. Two synthetic regions
produce two complete formats with the workflow tuple, not the different printer
default tuple, and the persisted job retains those values through inert delivery.
The native fixture uses hypothetical speed qualification with documented GC420d
pitch, explicitly not observed feed/backfeed support. The production model/pitch
guard remains unchanged; an unknown model is not admitted to that pipeline.

## Tests and root causes

210 Core debug tests passed, including seven motor integration tests and the new
complete queue/ticket case. New native pipeline case passed before fault
injection. Its missing-workflow-handoff variant reproduced preparationFailed
(one failure, exit1), proving the nearest independent constraint: ticket and
encoder must receive the identical immutable effective controls. Source restored.
The version2 preliminary-reference reader variant reproduced unsupportedSchema
(one failure, exit1); the corrected reader matches full decoding. These are
feature development regressions, not physical simulation passes.

Two old unsupported-future-version tests now use version4 because version3 is
implemented; strict version3 required-field tests were added. No input-validation
acceptance was removed. An initial full native gate passed89Python/209Core/274Mac debug/release and
oracle/signature/packaged checks before the secondary-state refinement. Its own
exit was0; it is not proof for later source.

A further two-test regression reproduced three failures: legacy print-only
metadata wrongly promised unchanged secondary speeds, and dropping both effective
speeds from a version3 ticket survived validation. `ResolvedMotorSpeed` now
separates explicit values from notExplicitlyControlled. Old wire bytes remain
unchanged. New ticket modes preserve that uncertainty; decoding must match full
resolution against the immutable queue/profile defaults. All210 Core tests pass.
Full `bash scripts/ci-swift.sh` for the refined source passed its own exit0 with
a finite900second deadline:89Python/210Core/274Mac debug/release,132 original
and180 compression independent round-trips, twelve benchmark CLI cases, inert
ABI/pipeline cases, native builds/nested local-ad-hoc signatures/ARM/minimum26
metadata and packaged-worker exact PBM/ZPL equality. Actual local runtime27.0;
no Tahoe26 runtime, scheduler, USB or physical evidence inferred. Tested source
was the complete new feature tree above52168e1 before committing it; publication
SHA is recorded in handoff after successful push. No new product outside CI.

## Remaining gates

Actual unit-specific feed/backfeed qualification, UI/system-dialog propagation,
production scheduler adapter, USB lease/delivery and alternating physical labels
remain NOT RUN. Darkness/tracking/geometry and finishing coverage are still
incomplete; M3-AC03 stays unchecked. Frozen B candidate and its one-job budget
unchanged. No queue, administrator action, printer I/O, merge or binary release.
