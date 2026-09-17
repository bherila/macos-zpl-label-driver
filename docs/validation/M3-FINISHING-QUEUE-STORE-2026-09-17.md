# Private offline finishing queue persistence — 2026-09-17

Partial M3 software only. FinishingQueueStore uses a distinct finishing-queues namespace
and FinishingQueueReference, not an ordinary queue selector. Canonical records are bounded
16KiB and256 records, with the shared descriptor-relative immutable publication primitive,
cross-process catalog lock, idempotent exact bytes and conflict rejection. No replacement,
active selection, installed scheduler queue or accepted finishing ticket is provided.

Before saving, exact canonical printer bytes must resolve through PrinterProfileStore.
The workflow reference must match stored schema/digest and have an exact qualification.
Full snapshot revalidation prevents same-reference altered values from publication. Loading
first verifies complete archive digest, then resolves both independent stores, reconstructs
through FinishingQueueJSON and checks queue identity/revision. Unknown profile facts are
not replaced. Uncertain publication returns commitUncertain with the exact typed reference
for explicit cold readback, never success or physical retry authority. Public domain errors
map shared storage failures; filesystem permissions and namespace safety stay shared.

Nearest independent constraints: full snapshots and each independent canonical digest must
remain bound before policy becomes trusted. Five focused/restored tests passed exit0 with
cold reopen, batch remainder ordering, explicit zero retention, idempotence/conflicts,
printer/workflow digest mismatches, changed complete snapshot, no premature publication,
missing qualification, wrong archive reference, tampered bytes, symlink rejection and
injected durability failure carrying the exact cold-recoverable reference. Initial fixture
qualification correctly rejected missing structural checks; the synthetic fixture was
corrected to include a border expectation, never weakening production validation.
Removing snapshot, workflow-digest or queue-digest checks independently failed exit1;
exact source bytes restored and five cases passed exit0. Logs
/tmp/zpl-finishing-queue-store-focused.log, /tmp/zpl-finishing-queue-store-snapshot-fault.log,
/tmp/zpl-finishing-queue-store-workflow-digest-fault.log,
/tmp/zpl-finishing-queue-store-queue-digest-fault.log and
/tmp/zpl-finishing-queue-store-restored.log.
Source SHA256: dccbc085735942e6a8d6c4414a4455505b3cde194a4231d5fa4453ffda5ddc41.
Full finite900s gate session41257 completed FULL_GATE_EXIT0:104Python/279Core/329Mac
in debug/release plus strict/ASCII oracles, finite inert ABI/filter/pipeline checks,
ARM/min26 metadata, nested local signatures and packaged-worker PBM/ZPL equality.
Log /tmp/zpl-finishing-queue-store-full.log; artifact artifacts/setup-app.KNUte4.
Existing native CI includes the new library/tests. Source publication pending.

Next: accepted finishing ticket binding original source, exact expanded order, qualified
pitch/device identity and durable lifecycle. Real status, scheduler/root admission,
physical delivery and minimum-runtime retail evidence remain open. Frozen Part B unchanged.
No administrator, printer I/O, merge or binary publication action.
