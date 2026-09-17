# Durable conservative finishing intent — 2026-09-17

Partial M3-AC09 software implementation; no installed scheduler or printer evidence.
FinishingAttemptStore persists an immutable potential-attempt marker tied to the exact
FinishingArtifactReference. Publication and reopen first verify the stored bounded archive
against independently supplied complete framed context. Four bounded binary records reuse
the private immutable directory's exclusive publication, namespace validation, permissions,
locking and durability checks. Identical publication is idempotent persistence, never
fresh-send authorization. There is no clear/reset API or automatic replay.

A cold reopen with a marker returns uncertainAfterRecordedIntent, including a crash
between publication and the first send call with zero known accepted bytes. Missing intent
returns only noRecordedIntent: it cannot prove another sender never transmitted or authorize
retry. Corruption, changed context, unsafe storage and failed reads fail closed. An uncertain
commit stops the caller; cancellation after publication is also uncertain.

Nearest independent constraint: durable intent must survive a restart even without any
transport-byte callback. The focused original-source pipeline covers all four finishing
modes, cold reopen before send, exact idempotence, changed context, pre-cancellation,
corruption, and post-publication sync failure. Initial/restored nine focused native cases
passed. Independent omission of the recovered intent failed 12 assertions in the focused suite (exit1); the
byte-restored nine cases passed (exit0). Restored source SHA256:
ad2da3dcbe8c671cdb501a4d806757da0e19f52b1e01b6afedeb089d841f4b5e.
Logs /tmp/zpl-finishing-intent-fault.log and /tmp/zpl-finishing-intent-final-focused.log.

This is offline storage, not accepted ticket/device binding or sender authority. Future
integration must publish intent before external attempts, retain validated physical ownership
through every file/status wait, and bind accepted identity and lifecycle. Correlated status,
accepted durable progress/completion, restart recovery and scheduler retry evidence remain
open. No administrator, device, merge or binary publication action. Finite 900-second full gate session87410 completed FULL_GATE_EXIT 0:
103 Python / 272 Core / 324 native tests in debug/release, 132 strict and 180 ASCII
oracle round trips per mode, finite benchmark/inert ABI/pipeline checks, ARM/minimum26
metadata, nested local ad-hoc signatures, unavailable Developer-ID negative and packaged
worker PBM/ZPL equality. Log /tmp/zpl-finishing-intent-full.log; local artifact
artifacts/setup-app.PozJuX. No printer accessed. Implementation source 3c96e68acdeeef4152aa5381f77be6e9dbd3d9c5; committed locally, hosted coverage pending.
