# Canonical offline finishing queue codec — 2026-09-17

Partial M3 software only. FinishingQueueJSON defines a separate offlineFinishingQueue
kind/schema1, bounded16KiB, exact field sets, immutable reference shapes, complete
control defaults and whole mode/schedule selection. Decode reconstructs through
FinishingQueueDefinition against independently supplied workflow/printer snapshots.
Reference extraction is only a preliminary lookup, never profile verification or admission.
A future store must load exact canonical profile/workflow references and validate full
queue bytes before publication. Ordinary queue schemas/admission remain unchanged.

Nearest independent constraint: untrusted bytes may not gain a canonical identity through
JSON parser normalization. Decode requires exact re-encoding equality, rejecting duplicate
keys and noncanonical encodings. Numeric fields exclude booleans; remainder requires an
actual JSON boolean. Shared geometry/offset codecs retain all defaults and explicit zero.
Seven focused cases passed exit0: every mode, batch remainder false, exact round trips,
reference extraction, ordinary role rejection, duplicate keys, boolean numeric fields,
numeric remainder, invalid batch size/kind, trailing whitespace and oversize input.
Removing canonical-byte equality caused two assertions to fail exit1. Exact source bytes
were restored and all seven cases passed exit0. Logs /tmp/zpl-finishing-codec-focused.log,
/tmp/zpl-finishing-codec-canonical-fault.log and /tmp/zpl-finishing-codec-restored.log.
Source SHA256: 5f46b72f5720c6722c78931aea3b8f7c172c39a05113de67adbe500909a980fa.
Initial unpublished compilation failure was a missing try; corrected before testing.
Full finite900s gate session28149 completed FULL_GATE_EXIT0:104Python/279Core/324Mac
in debug/release plus strict/ASCII oracles, finite inert ABI/pipeline checks, ARM/min26
metadata, local nested signatures and packaged-worker PBM/ZPL equality.
Log /tmp/zpl-finishing-codec-full.log; artifact artifacts/setup-app.jnBpy5.
Existing Core CI includes the new library file and tests. Publication pending.

Next: private immutable finishing queue persistence with independently verified digests,
then accepted source/order/pitch/device/lifecycle binding. No installed queue, administrator,
real status, physical delivery, merge or binary publication. Frozen Part B unchanged.
