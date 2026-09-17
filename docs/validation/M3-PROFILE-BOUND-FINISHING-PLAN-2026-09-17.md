# Finishing intentions bound to a private profile revision — 2026-09-17

Partial M3-AC02/03/11 work. No ordinary mechanical output or physical acceptance.

PrinterProfileStore.finishingPlan loads and verifies the caller's full immutable
reference through the existing private canonical store. Only profile8 with a
finishing configuration can produce a plan. It uses that exact revision's model,
installed accessories, media/stock declarations and schedule limits to construct
a bounded FinishingJobPlan. No latest-revision substitution, copies expansion,
queue edits or commands occur. All four modes can be planned on a synthetic
matching configuration; primary GC420d/no-cutter constraints are unchanged.

ProfileBoundFinishingJobPlan retains the full reference and profile snapshot.
validateBinding rejects different ID/schema/revision/digest, output count, mode,
schedule size or final partial-batch policy. Later acceptance must supply its
independently bound values. This binds these planning inputs only: it does not
bind prepared raster order/bytes, prove the caller expanded copies correctly or
authorize delivery. Ordinary profile8 resolution/encoding remains rejected.

## Evidence

Four native focused cases passed own exit0: cold-store planning for all modes;
every reference/count/mode/schedule substitution; newer revision versus old batch
limits and immutable plan; missing configuration, legacy version and forged digest.
Removing the full-reference comparison made the substitution test fail own exit1
with four assertions, one per reference component. Source restored byte-for-byte,
SHA2567b4b32a833991b37fb3b844bfeaaa7fac756162c81820b0d519d489a58a8545c;
all four restored focused cases passed own exit0. Finite900-second full gate is
live under session87489; no full result claimed before its terminal output.

## Remaining gates

Queue/ticket option precedence, ordinary original-PDF preparation and encoder
normalization, ordered prepared-label bindings, qualified cut/file boundaries,
peel label-removal waits and physical faults/isolation. Native mechanical editing,
M1 privileged identity/lifecycle, installed dialog/default management, accessibility,
USB and actual printing remain open. Declarations are not authenticated sensing.
No printer/admin/merge/binary publication. Frozen Part B unchanged.

## Terminal full validation

Finite900-second `bash scripts/ci-swift.sh` passed ownexit0:89 Python/270 Core/318
Mac debug/release,132 original and180 ASCII oracle round trips per mode, finite
benchmark/inert ABI/pipeline harnesses, native ARM/minimum26 metadata, nested local
ad-hoc signatures, unavailable Developer-ID negative and packaged-worker PBM/ZPL
equality. Local artifact `artifacts/setup-app.w04t7p`. Disclosure marker scan of
tracked/new files and manual source diff review passed. This is automated evidence
only; ordinary mechanical integration and prescribed physical gates remain open.

## Source checkpoint

Implementation `7c97afa8df33852f181bcd30f0fc0b59ec6f958e` contains the validated profile-bound planning
slice. Exact publication/hosted validation remains a separate observation.
