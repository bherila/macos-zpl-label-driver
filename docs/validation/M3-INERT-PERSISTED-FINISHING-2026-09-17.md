# Inert durable-intent integration — 2026-09-17

Partial M3-AC09 software implementation; discard-only and synthetic status throughout.
InertPersistedFinishingDelivery composes the existing framed coordinator with the exact
archive/context intent store. Under the coordinator's kernel device lease, the first file
attempt checks for previous intent and durably publishes intent before any discard callback.
Existing intent rejects another run and requires review. A separately namespaced artifact
lease serializes the same exact archive across caller-provided simulator device aliases.
Both leases are nonblocking and span the complete scoped operation, including status waits.
They release on completion, rejected restart, publication failure and thrown callbacks.

Stop/cancellation before an attempt leaves no intent. A zero-byte attempted failure remains
uncertain. Even successful synthetic completion leaves persisted intent uncertain: simulated
status is not a physical completion receipt. Publication uncertainty stops before caller
callbacks or discarded-byte accounting; cold reopen still finds the intent. No clear/reset,
actual transport, printer commands, accepted-job admission or automatic replay is introduced.

Nearest independent constraints: intent must precede byte accounting; persisted intent must
veto another run even with zero accepted bytes; lease ownership covers persistence and waits.
The nine focused original-source cases exercise all four modes, no-attempt stop/cancellation,
zero-byte failure, competing device/artifact aliases, complete synthetic waits, cold-reopen
rejection, post-publication sync failure and lease release. Expanded nine cases passed exit0.
Publication and replay-veto omissions independently failed exit1; byte-restored nine
focused cases passed exit0. Restored source SHA256:
e41b0e9ddfef16a6e7d35b871c5b392c7cf8029291e4f99dae4edca14a42cbc2.
Logs /tmp/zpl-persisted-finishing-publication-fault.log,
/tmp/zpl-persisted-finishing-replay-fault.log and /tmp/zpl-persisted-finishing-restored.log.
Finite 900-second full gate session64896 completed FULL_GATE_EXIT 0:
103 Python / 272 Core / 324 native tests in debug/release, 132 strict and 180 ASCII
oracle round trips per mode, finite benchmark/inert ABI/pipeline checks, ARM/minimum26
metadata, nested local ad-hoc signatures, unavailable Developer-ID negative and packaged
worker PBM/ZPL equality. Log /tmp/zpl-persisted-finishing-full.log; local artifact
artifacts/setup-app.thCaUD. No printer accessed. Implementation source 42a4caec2fb28ce8e752860cf494ddf9c37c6b69; committed locally, hosted coverage pending.

Accepted finishing ticket/device identity, authoritative status, durable progress/completion,
real scheduler retry semantics and cross-process installed ownership remain open. These
simulator checks do not pass M3-AC07/08/09 integration or accessory hardware acceptance.
Frozen B unchanged. No administrator, printer, merge or binary publication action.
