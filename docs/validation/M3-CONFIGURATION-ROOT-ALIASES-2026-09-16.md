# Immutable configuration root spelling

Partial automated preparation for M3-AC12 only; installed configuration access,
administrator installation, scheduler and physical acceptance remain NOT RUN.

Issue #76 records the pre-existing shared configuration-store gap separately
from M1 filter PR #75. On parent `cb86196`, a native test in owned UUID temporary
directories checks final-dot and final-dot-dot roots through WorkflowProfileStore,
PrinterProfileStore and VirtualQueueStore. All six expected rejections failed.
The test touched no scheduler/device/user configuration. Source inspection of
the containing-directory barrier explains why a retained dot spelling can select
the root itself as parent. This is not a power-loss or APFS-loss reproduction.

PrivateImmutableDirectory now rejects those reserved final path components before
mkdir/open, mapping through existing public unsafeStoreDirectory errors. It does
not normalize a configured root, add recursive provisioning, alter immutable
record bytes or change post-publication uncertainty. This aligns configuration
root naming with the accepted-job store's PR #74 guard. An owned-directory
contents check confirms constructor rejection adds no records/subdirectories.

The corrected focused native suite passed exit 0: 35 workflow/printer/virtual-queue
store tests, retaining ordinary-root round trips, publication uncertainty and
conflicting/idempotent retries. Before-edit accelerator baseline is the unchanged
source of PR #75's full `ead620c` gate: both independent/inert runs passed; the
parent's later publications changed only evidence/manifest. Full new local and
own hosted/review gates are pending. No supplied bitmap, graphic writer, ordering
planner, independent decoder or fixture is rebuilt.

This slice does not change the frozen M1 filter/script/PPD/PDF bytes. The finite
discard experiment remains pending its actual OS administrator session and
baseline; configuration library success is not installed-spooler evidence.
