# Finishing stock declarations and complete output plans — 2026-09-17

Partial M3-AC02/03/11 implementation; no physical finishing acceptance.

`FinishingStockQualification` binds per-mode suitability declarations to an exact
immutable `MediaConfiguration`. Unknown, explicit false, model documentation and
unobserved evidence cannot admit a mode. Only true reported-installation
suitability for the requested mode is accepted. Another mode's declaration,
installed accessories and pre-cut form are not substitutes. This is a supplied
installation declaration, not authenticated sensing or observed mechanical proof.
No liner/adhesive/printable dimensions or tracking observations are fabricated.

`FinishingJobPlan` validates the complete engine-expanded output count (1–10000),
exact media equality, explicit enabled/model/accessory gates, and stock suitability
before retaining the immutable inputs and planned cut boundaries. Cutting requires
an explicit independently qualified schedule. Other modes reject a supplied cut
schedule rather than discard it. Copies/ranges remain owned by the engine; this
planner neither expands them nor transmits commands. Mode fragments and separate
file/delayed-cut contracts are still distinct, per R45 ^MM/^PQ provenance.

## Validation

Four focused tests passed own exit0: all four independent stock declarations with
unknown/false/missing/model-only negatives despite installed accessories; changed
media rejection and preserved unknown geometry; mandatory cutting schedules and
non-cut schedule rejection; output bounds and installed-accessory independence.
Full finite900-second `bash scripts/ci-swift.sh` gate failed own exit1.
Python89 and Core266 debug/release passed, with independent oracle and inert
harness stages. Native debug313 had one failure: the existing barcode changed-anchor
pipeline test expected layoutRejected but reached preparationDeadlineExceeded.
A focused recheck failed own exit1 with OfflineRenderWorker.timedOut instead.
No Mac release/native signing/packaged-worker pass is claimed for this slice.
The failures occur in existing five-second worker/preparation waits; these new
planner types are not called by that test. Timing is a hypothesis, not an
established root cause. Do not weaken deadlines or treat either failure as a pass.

Removing exact-media equality deliberately made the changed-stock regression fail
own exit1 (missing expected throw). Source restored byte-for-byte, SHA256
c9182de39d3fd268f9f13ceff22d0c4cb0e19834d55c283746b6b2b26c8fc084;
all266 restored Core tests passed own exit0. Source remains local and unpushed
pending native failure diagnosis and a successful full gate. Logs are private
local evidence and are not committed as full system dumps.

## Remaining gates

Ordinary profile/queue/ticket schema integration and prepared-label normalization
remain tear-off only. Qualified cut wire/file boundaries, peel label-taken waits,
stock-specific physical behavior, faults and alternating-workflow isolation are
not established. Native queue/default management, M1 privileged identity/lifecycle,
GUI/accessibility, USB and actual printing remain open. No printer commands,
administrator actions, merges or binary releases. Frozen Part B is unchanged.

## Worker diagnosis follow-up

With unchanged source and five-second deadlines, all nine debug layout-worker
tests subsequently passed own exit0 (2.36-second test execution). The original
barcode pipeline case passed release own exit0 (1.35 seconds), then debug own
exit0 (1.72 seconds). This contradicts a deterministic failure but does not
establish the cause of the two previous timeouts. No deadlines or assertions
were changed. A new finite900-second full gate is live; no terminal result yet.
Source remains local and unpushed pending that gate.

## Terminal full recheck

The subsequent finite900-second `bash scripts/ci-swift.sh` recheck passed own
exit0:89 Python/266 Core/313 Mac debug/release, independent132 original/180 ASCII
round trips per mode, finite benchmark and inert ABI/pipeline harnesses, native
ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable Developer-ID
negative and packaged-worker PBM/ZPL equality. Artifact `artifacts/setup-app.DaVytl`.
No source/deadline/assertion change was made between native diagnosis and this
recheck. Earlier failures remain recorded; their cause is not established. This
is automated evidence, not installed scheduler/GUI/physical acceptance.

## Source checkpoint

Implementation `c1a0ff7e1b7000674eb1b96c415890af9f8afbe5` contains the validated stock-plan slice.
Exact hosted validation for its publication checkpoint remains separate.
