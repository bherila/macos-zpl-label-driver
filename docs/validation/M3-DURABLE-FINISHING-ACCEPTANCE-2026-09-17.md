# Durable original-document finishing acceptance — 2026-09-17

Partial M3/M5 unprivileged software only. AcceptedFinishingJobStore publishes one binary
record containing a canonical manifest and exact original PDF in accepted-finishing-jobs.
AcceptedFinishingReference is separate from ordinary ticket/queue/artifact references.
The record begins AFJOB001 plus an unsigned little-endian metadata length. Metadata is
bounded16MiB, source100MiB, total116MiB+16bytes; at most four immutable records use the
shared catalog lock, exclusive publication, directory barriers and binary record counting.
Exact republishing is idempotent; changed context under an existing identity conflicts.
Uncertain publication returns the exact typed reference for explicit cold readback.

Load verifies full record digest, magic, bounded lengths and canonical Codable manifest
before resolving references. Canonical round-trip rejects unknown/duplicate/alternate
JSON encodings. Strict enum/optional combinations retain copy/range ownership, whole cut
selection, explicit control requests, native pitch provenance and exact private references.
Original-source acceptance reconstructs through verified stores and finite isolated worker
analysis. Complete recorded context must match: source hash/size/page count, ordered region
identity/index/crop/source coordinates/rotation/scaling/stock/profile, selected non-label
accounting, complete canonical queue/workflow/printer bytes, canvas dimensions, normalized
control bytes, finishing mode and cut boundaries. Metadata separately binds pitch evidence,
coordination domain, cancellation digest and ownership. Cold reinterpretation fails closed.
The aggregate load deadline includes read/hash/reference work and reconstruction; cancellation
is checked before reading and before return. No renderer status or physical completion is
manufactured, and recovery does not clear intent or authorize transmission/replay.

Nearest independent constraints: exact archive digest and full independently reconstructed
context must remain required even when references and original PDF remain valid. Fourteen
focused/restored native cases passed exit0, including prior acceptance/geometry/store cases
and four durable cases: cold reopen equality, idempotence, changed order conflict, wrong
reference digest, rehashed stale context, unsigned maximum length before a nonexistent
worker, binary symlink rejection, and injected post-publication durability failure carrying
an exact cold-recoverable identity. Removing archive digest or context comparison independently
caused expected assertions to fail exit1; exact source restored and fourteen passed exit0.
Logs /tmp/zpl-accepted-finishing-store-focused.log,
/tmp/zpl-accepted-finishing-store-context-fault.log,
/tmp/zpl-accepted-finishing-store-digest-fault.log and
/tmp/zpl-accepted-finishing-store-restored.log.
Source SHA256: 056b5be9c7e7aa1e0d055b7d9ec81768fbb1b8579289b8665fff51c34ade87bd.
Full finite900s gate session6450 completed FULL_GATE_EXIT0:104Python/281Core/338Mac
in debug/release plus strict/ASCII oracles, finite inert ABI/filter/pipeline checks,
ARM/min26 metadata, nested local signatures and packaged-worker PBM/ZPL equality.
Log /tmp/zpl-accepted-finishing-store-full.log; artifact artifacts/setup-app.svfO7x.
Existing native CI includes new source/tests. Implementation checkpoint f878bf6729428c32791b7dbe394c47e114c22f3d; source publication pending.

Next: accepted identity binding into prepared framing and attempt intent, durable cancellation/
lifecycle recovery and authoritative progress. Installed scheduler/privileged admission,
actual unit correspondence/status, retail policy and hardware remain open. Frozen Part B
unchanged. No administrator, printer I/O, merge or binary publication action.
