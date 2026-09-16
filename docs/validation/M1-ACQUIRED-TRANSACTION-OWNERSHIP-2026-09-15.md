# M1 acquired transaction ownership — 2026-09-15

**Scope:** unprivileged source and fault-injection evidence for the inert M1
discard-queue transaction at `c9a652e` with acquisition-edge remediation at
`92606bb`.

## Corrected boundary

Automatic rollback is now distinct from explicit `--remove` recovery. It is
eligible only after this invocation successfully creates the protected root,
and it requires the protected intent's random transaction identifier to match
the identifier held by this invocation. A process that loses root creation
does not inspect or remove the winning invocation's root, record, filter, or
queue.

Queue removal during automatic rollback additionally requires a successful
queue-creation response and immediate exact discard-URI readback. If the late
absence check finds a queue, or queue creation returns an ambiguous failure,
the queue and all recovery evidence are retained. Explicit `--remove` still
requires the complete protected record and exact discard URI and remains
queue-first.

Catchable signals are deferred across successful root creation until rollback
eligibility is recorded, closing the post-creation/pre-flag window. Explicit
recovery accepts the exact immediately preceding eight-line schema-2 record as
well as the new nine-line schema-3 record; only schema 3 can satisfy automatic
invocation-bound rollback.

## Regression evidence

The shell-function harness covers:

- a losing invocation racing a competing empty protected root;
- a losing invocation racing a completed transaction;
- a same-name queue appearing at the late absence check;
- an effective queue creation whose command reports failure;
- TERM immediately after effective protected-root creation;
- exact schema-2 and schema-3 explicit-recovery shapes, with mixed shapes
  rejected;
- every existing post-mutation checkpoint, changed URI, failed deletion,
  unavailable authorization, scheduler-query failure, and TERM path.

The four new contention cases leave the competing or ambiguous state intact
and perform no destructive cleanup against it.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 62 passed;
- LabelCore — 164 passed in debug and release;
- LabelMac — 105 passed in debug and release;
- independent encoder round trips — 132 passed;
- backend ABI — 15 passed;
- filter ABI — 10 passed;
- inert filter-to-discard pipeline — 1 passed;
- local ad-hoc command products and setup app — built and signature-verified.

## Evidence limits

No administrator authorization was used. No queue, protected path, scheduler
job, system setting, or printer was changed. This closes a source-level
transaction-ownership defect only; M1-AC01 through M1-AC13 remain unchanged
until their required integration evidence is recorded.
