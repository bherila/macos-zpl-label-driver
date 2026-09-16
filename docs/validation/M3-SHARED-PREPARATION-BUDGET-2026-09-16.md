# M3 shared preparation budget — 2026-09-16

Synthetic intake now accepts a bounded processing deadline (positive, finite,
at most 60 seconds) and processing-cancellation object. One monotonic budget
is created before input admission and reused by initial/retry layout analysis
and every label renderer; subsequent labels cannot renew it. Preparation and
pre-delivery boundaries check it. Each child receives only the remaining time.
Worker deadlines now start before executable inspection/source staging and are
checked before child launch, after exit and after result reads. Owned-child
termination remains the same bounded mechanism.

Processing interruption reports distinct cancellation/deadline errors. It is
not an authorized persisted job cancellation, does not invent a terminal job
state, and does not authorize automatic replay. Existing accepted/prepared
artifacts remain subject to their validated lifecycle/recovery contracts.

Deterministic monotonic-clock tests prove deadline nonrenewal and explicit
invalid-limit/cancellation errors. Connected tests prove pre-cancellation
precedes descriptor reading, and analysis timeout/live cancellation publish
neither acceptance nor send intent. Existing rendering, extraction, retry,
uncertain-no-replay and complete-preparation tests pass: 29 focused tests.
Full local `bash scripts/ci-swift.sh` completed with exit 0: 67 Python, 166 Core
and 167 Mac tests in debug/release, 132 independent round trips, 15 backend and
10 filter ABI cases, one inert pipeline case and ad-hoc command/app signatures.
Automatic hosted run `35075349804` passed exact code head
`769f0c6a5cbd83cba0760938335044ad004e5746`, with all three required jobs green.
Inspected logs confirm the full 67/166/167 debug/release suites, independent
checks and ad-hoc signatures. Independent review completed cleanly at the same
head with a completed summary, thumbs-up and no inline findings.

The preparation deadline is cooperative across filesystem/configuration calls:
those calls are checked when they return, not forcibly interrupted. Native
child work is interruptible. This is not an unconditional wall-clock guarantee,
not transport cancellation arbitration, and not an installed scheduler result.
No administrator, queue, USB or printer operation occurred.
