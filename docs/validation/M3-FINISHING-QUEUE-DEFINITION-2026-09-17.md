# Offline finishing queue definition — 2026-09-17

Partial M3 control/admission software, not installed queue or accepted device authority.
FinishingQueueDefinition is a distinct typed offline policy. It retains immutable workflow/
printer references plus complete workflow/printer values for subsequent exact snapshot
revalidation. It requires workflow2/profile8 identity/revision shapes, safe queue identity,
reported nominal media matching workflow output stock, and consistent default mode choices.
A default one-label plan validates mode/accessory/stock/schedule and all effective controls
before the definition is retained. A real engine-expanded count is resolved later; this
layer never expands copies or changes label order.

Selection overrides replace the complete mode/schedule pair. Conflicting explicit finishing
requests fail rather than being overwritten. Other controls use the existing job/workflow/
configured precedence, preserving explicit zero. Every later resolve requires exact full
workflow and printer snapshots, not merely matching IDs/revisions or resulting output.
Ordinary VirtualQueueDefinition/ResolvedJobTicket/encoder admission remains unchanged;
no scheduler queue name, installation, reference-digest verification or accepted ticket is
manufactured. Future private storage must verify canonical reference bytes independently.

Nearest independent constraints: complete immutable snapshots cannot be substituted even
with identical cut boundaries; mode overrides cannot discard a conflicting explicit choice;
workflow stock cannot differ from declared output media. Five focused cases passed across
all modes, batch remainder, whole-selection replacement, same-revision changed policy/
conversion, invalid counts/schedules/defaults/legacy roles, unverified stock, stock mismatch
and explicit zero. The initial synthetic fixture correctly failed unknown thermal support;
only fixture declarations were corrected, never production validation. Removing snapshot,
selection or stock validation independently failed exit1; byte-restored five cases passed
exit0. Restored source SHA256:
b8ade8c1cad313994c5fb71167367f13138a0a9d050f34cf2db481440e813c9d.
Logs /tmp/zpl-finishing-queue-snapshot-fault.log, /tmp/zpl-finishing-queue-selection-fault.log,
/tmp/zpl-finishing-queue-stock-fault.log and /tmp/zpl-finishing-queue-restored.log.
Full finite900s gate session76703 completed FULL_GATE_EXIT 0:104 Python,277 Core and324
native tests in debug/release, independent strict/ASCII oracles, bounded inert pipeline,
ARM/minimum26 metadata, local signatures and packaged-worker PBM/ZPL equality.
Log /tmp/zpl-finishing-queue-full.log; artifact artifacts/setup-app.gfdEKb.
New library/tests are included by existing CI. Source publication remains pending.

Next: bounded canonical private queue persistence verifying actual profile/workflow digests,
then separate accepted finishing ticket/source/output/pitch/device binding and lifecycle.
M1 privileged/backend assumptions, real status, scheduler admission and hardware remain
unqualified. Current source assessments are stale until reevaluated for this source change.
Frozen B unchanged. No administrator, printer, merge or binary publication action.
