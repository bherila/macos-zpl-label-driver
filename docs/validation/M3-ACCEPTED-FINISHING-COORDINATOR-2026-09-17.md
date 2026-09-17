# Accepted finishing inert coordinator — 2026-09-17

Partial M3/M5 software only. InertAcceptedFinishingDelivery accepts a sealed framing value,
derives its simulator device domain from the retained accepted geometry, and acquires an
acceptance-ID kernel lease before checking intent. The job lease remains held through the
existing device lease and every framed file/status wait. All output is discarded; status is
explicitly synthetic. No transport or device query is performed.

A single finite monotonic deadline covers accepted-record validation, intent publication and
all simulator steps. Under both leases, the first file event rechecks missing intent and
publishes potential attempt before allowing any discard observation. Uncertain publication
throws before discard. Recorded intent blocks later admission even after cold reopen or
synthetic successful completion. Pre-attempt stop/cancellation creates no intent. Deferred
lease release covers error paths. The store's idempotence is never a new sending permission.

Nearest independent constraints: accepted job identity must serialize all framed versions;
lease ownership must include status waits; durable uncertainty must veto fresh admission.
Twenty focused native cases passed exit0, including the prior17 and three coordinator cases:
intent-before-discard, competitor job/device leases during waits, replay after success,
zero-byte failure, directory-sync uncertainty before callbacks and pre-attempt stop/cancel.
Replay-veto omission failed exit1 with three expected assertions; early job-lease release
failed exit1 with eight expected assertions. Exact restored source passed20 cases exit0.
Full finite900-second Mac gate session32086 completed FULL_GATE_EXIT0:104Python,
281Core and344Mac debug/release,132 strict and180 ASCII oracle cases per mode, finite
benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc
signatures, Developer-ID negative and packaged-worker PBM/ZPL equality. Local artifact:
artifacts/setup-app.0aX201.

Next: durable accepted-job cancellation/lifecycle recovery. This coordinator is a finite
inert integration, not a production adapter. No true cross-process product queues, discovered
unit correspondence, installed scheduler, retail installation or physical output is qualified.
Those prescribed I/H/R gates remain NOT RUN. Frozen Part B remains unchanged. No printer I/O,
administrator action, merge or binary publication occurred. Source commit pending.
