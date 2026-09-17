# Immutable utility defaults save/reopen — 2026-09-17

Partial implementation evidence for M5-AC04/05/07/10 and M3-AC11. Current
unpublished source connects native draft editing to the existing private immutable
printer-profile store. No installed scheduler/queue/device claim or acceptance pass.

## Independent constraint

Saving must capture the complete validated effective default combination once,
preserve model/media/connection qualification and all older immutable revisions,
and change the utility's selected model only after exact canonical reference
readback. Invalid drafts and uncertain publication cannot silently replace the
current draft. Historical reopening must save beyond every observed revision.

## Native behavior and storage

The application uses a user-owned `printer-defaults-v1` store beneath its private
application-support directory. The new save/reopen view provides current revision,
bounded available revisions, save, explicit historical reopen and refresh actions.
Startup reads the highest canonical saved revision; no document or printer data is
uploaded. Reopening explicitly replaces the draft and resets hardware confirmations.
Refresh updates the list without replacing a pending draft with another editor's
new revision. Draft changes propagate to containing save/readiness controls.

Save validates the ordinary control encoder, snapshots effective fields once, uses
the highest observed revision plus one with overflow rejection, and preserves
capabilities/installed hardware/media/connection. Factory schema1 defaults become
schema2; existing higher schema qualification is retained. The descriptor-relative
private store publishes immutable canonical bytes; exact digest/schema/revision
readback and a matching catalog entry precede replacing the utility model. Concurrent
publication may conflict safely: catalog inspection is not a revision reservation.
No automatic retry occurs on uncertain publication or conflicting bytes.

Catalog reads are capped at256 records,32KiB each and8MiB total across the private
printer namespace. One exact profile ID is selected by its hashed prefix; selected
records must have exact canonical filenames and byte encoding. Misnamed, malformed or noncanonical selected-family candidates fail; unsafe or
over-budget records fail in the shared namespace reader before filtering. Other
profile families are not selected or treated as configured defaults for this ID. Symlink substitution fails
in the underlying protected descriptor reader. Publication admission is capped
at256 records with the existing shared publication lock; a full namespace still
permits exact idempotent existing-record reconciliation. Old references/queue
bindings/job snapshots are not repointed or removed.

## Validation

15 focused macOS tests passed ownexit0: seven editing-model and eight profile-store
cases. New coverage includes save/restart/historical reopening and monotonically
fresh revisions; immutable prior records; invalid draft preservation; overflow and
wrong reference; observable nested draft changes; injected uncertain post-rename
sync outcome without state replacement; refresh without draft replacement; and
schema6 geometry/offset/motor/darkness-zero persistence together.

Catalog cases cover exact-ID filtering, canonical names/bytes, revision mismatch,
unsafe symlink substitution, finite read budget and full256-record admission with
preserved/idempotent old records. Existing conflicting writers and post-rename
recoverable-identity tests remain. Synthetic fixtures only; no real printer identity
or customer payload appears. Full finite 900-second `bash scripts/ci-swift.sh` gate passed ownexit0:89 Python/242 Core/306 Mac debug/release,132 original and180 ASCII independent round trips,finite benchmark/inert ABI/pipeline harnesses,ARM/minimum26 native products,nested ad-hoc signatures and exact packaged-worker PBM/ZPL equality. Local artifact:`artifacts/setup-app.RlqxU1`.

## Remaining gates

These are utility revisions in private user storage, not privileged protected
spooler publication or installed queue/default management. Existing accepted jobs
bind their original immutable references. Production adapter/helper identity,
authorized install/update/uninstall and system-dialog exposure depend on M1 evidence.
Full keyboard/VoiceOver and GUI save/reopen walkthrough are NOT RUN. Actual sensing,
unit limits, USB and alternating physical output remain prescribed hardware gates.
Thermal/finishing policy integration remains independent work. B's frozen approved
candidate stays unchanged. No administrator/queue/printer action, merge or binary release.
