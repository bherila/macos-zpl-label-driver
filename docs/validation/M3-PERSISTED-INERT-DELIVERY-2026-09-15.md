# M3 persisted inert delivery — 2026-09-15

**Scope:** automated native evidence at `c2e6e53` with review remediation at
`297c6aa` and `e977b33`, restacked with immutable-publication remediation
`c4798ef`, connecting a validated
immutable prepared-job bundle to its persisted lifecycle and shared
physical-device lease. The sink discards bytes in memory. This is not scheduler,
network, USB, or physical-printer acceptance.

## Implemented boundary

`InertPersistedDelivery` accepts only an acceptance identifier resolved through
one descriptor-bound accepted-job repository. Before acquiring a lease or
changing lifecycle state it reloads and verifies the canonical accepted ticket,
immutable configuration references, prepared payload, payload digest, byte
count, output order, resolved controls, and printer-profile snapshot.

Delivery derives the opaque lease identity only from the verified ticket's
immutable physical-device coordination domain; no caller-supplied alias can
select a different lock. It then acquires the common `PhysicalDeviceLease` and
advances the persisted lifecycle from `prepared` through `waiting`. Before the first possible
sink side effect it commits `transmitting(..., bytesAccepted: 0)`. Bounded
discard chunks advance only monotonically. Completion records `transmitted`,
which is explicitly not device confirmation. Injected zero-byte or partial
ambiguity records terminal `uncertain` state and never authorizes automatic
replay. A failure classified before send records `failedBeforeTransmission`.

Invalid states, oversized ambiguity offsets, contradictory fault scenarios,
and lease contention produce no sink action. Any lifecycle publication error
stops the simulator; commit uncertainty is preserved rather than converted into
a retry authorization.

A durably published `waiting` state is safe to resume: by contract no sink
action can precede the later `transmitting` commit, and the ticket-derived lease
excludes a still-live prior worker. Lease contention is therefore classified as
automatically retryable while leaving the prepared or waiting state untouched.

## Regression evidence

Eight new native cases establish:

- transmitting intent is the first observed delivery event and precedes every
  discarded byte;
- bounded short chunks total exactly the immutable prepared payload and end in
  persisted `transmitted` state;
- zero-byte and three-byte ambiguity persist exact progress and are not
  automatically retryable;
- a pre-transmission failure has no sink event and retains its distinct
  retryable classification;
- a competing lease in the ticket-bound device domain leaves the prepared
  lifecycle unchanged and is safely retryable;
- a job stranded after the durable `waiting` transition resumes under the same
  lease, persists send intent, and completes without replaying prior bytes;
- an out-of-range fault plan is rejected before lifecycle mutation, and a
  completed job cannot be delivered a second time; and
- contradictory fault controls are rejected during scenario construction.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 64 passed;
- LabelCore — 165 passed in debug and release;
- LabelMac — 129 passed in debug and release;
- focused accepted-job suite — 33 passed;
- independent encoder round trips — 132 passed;
- backend ABI — 15 passed;
- filter ABI — 10 passed;
- inert filter-to-discard pipeline — 1 passed;
- local ad-hoc command products and setup app — signatures verified.

## Evidence limits and next boundary

This is partial automated M3-AC05/07/08/09/12 evidence only. It does not close
their required integration evidence. The simulator is not connected to CUPS,
TCP, USB, a daemon, a scheduler exit/retry mapping, recovery UI, or a printer.
It does not establish actual cross-process output serialization or restart
reconciliation. Production integration must retain the same ordering while
persisting send-attempt intent before a potentially effective transport call,
and must reconcile state-publication uncertainty without blind replay.

No administrator path, queue, protected installation location, network
endpoint, USB device, or printer was accessed.
