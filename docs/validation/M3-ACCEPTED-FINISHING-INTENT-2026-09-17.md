# Accepted finishing framing and attempt intent — 2026-09-17

Partial M3/M5 software evidence. AcceptedFinishingFramedJob retains the exact durable
acceptance reference, complete accepted preparation and qualified ordered framed output.
It has no public initializer and cannot substitute original source or controls.

AcceptedFinishingAttemptStore reopens the exact accepted record and requires full equality
with the independently supplied accepted job before either publication or recovery.
Intent keys use acceptance ID only, never artifact names. Records bind the accepted digest,
are immutable and bounded to four 1024-byte records in a separate private namespace.
Idempotent publication is persistence, not authorization to send. Missing intent is not
proof of no previous transmission. Recorded intent always recovers as uncertain, including
zero-byte attempts, crashes, artifact renaming and synthetic successful delivery. There is
no clearing, completion upgrade or replay API. Publication barrier failure remains uncertain.
Finite deadlines and cancellation cover validation and storage operation boundaries.

Nearest independent constraints: job-level uncertainty must survive artifact renaming and
synthetic success; identical acceptance IDs do not permit substituting copy/order context.
Seventeen focused native cases passed, including actual original-PDF preparation/framing,
two artifact names, cold recovery, exact-context rejection and a directory-sync failure.
Independent recovery/context guard omissions each failed exit1 through expected assertions;
exact restored source passed all17 cases exit0.
Full finite900-second Mac gate session76633 completed FULL_GATE_EXIT0:104 Python,
281 Core and341 native tests in debug/release;132 strict and180 ASCII oracle cases per
mode, finite benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local
ad-hoc signatures, Developer-ID negative and packaged-worker PBM/ZPL equality. Local
artifact: artifacts/setup-app.8Cbhfj. Source commit/publication pending.

Next: coordinate accepted-job intent and a job lease through every inert file/status wait,
then durable cancellation/lifecycle recovery. A future coordinator must hold a job lease
before checking missing intent and publishing it, through delivery; the store alone does
not atomically authorize admission. Installed scheduler, identified unit correspondence,
retail policy and physical printing remain NOT RUN. Frozen Part B is unchanged. No printer
I/O, administrator action, merge or binary publication occurred.
