# M5 immutable publication uncertainty — 2026-09-15

**Scope:** native source and regression evidence for review finding R13 at
`f42226d`. This is a local persistence result contract, not installation,
scheduler, delivery, or physical-printer acceptance.

## Corrected boundary

Workflow profiles, unattended-use qualifications, printer profiles, and
virtual queue definitions now use one descriptor-relative immutable publisher.
The publisher writes and syncs a private temporary regular file, publishes it
with an exclusive rename, and requires a successful target-directory barrier
before returning success. An identical retry also repeats that barrier rather
than treating visible byte equality as durability acknowledgement.

Failure before rename returns an ordinary write error and removes the temporary
record. Failure of the actual directory-sync operation after rename returns
`commitUncertain` through each public store API. That error includes the exact
logical ID, schema version, revision, and canonical SHA-256 digest whose bytes
may already be visible. Callers therefore need not infer publication state from
a generic write error.

## Regression evidence

Native tests establish that:

- an injected pre-rename failure leaves no final or temporary record;
- persistent directory-sync failure returns the same exact uncertainty on a
  first publication and an identical retry;
- workflow and qualification, printer-profile, and queue APIs expose the
  canonical identity and digest of the uncertain revision;
- exact visible bytes remain loadable and a later successful identical retry
  completes the required barrier; and
- a conflicting retry remains a conflict and cannot replace the visible
  immutable winner.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 64 passed;
- LabelCore — 165 passed in debug and release;
- LabelMac — 119 passed in debug and release;
- focused workflow/profile/queue stores — 24 passed;
- independent encoder round trips — 132 passed;
- backend ABI — 15 passed;
- filter ABI — 10 passed;
- inert filter-to-discard pipeline — 1 passed;
- local ad-hoc command products and setup app — signatures verified.

## Evidence limits

The tested barrier is the host filesystem `fsync` contract. This evidence does
not claim an unconditional device-level power-loss guarantee, restart recovery
UI, retention policy, installed scheduler acceptance, or printer behavior. No
administrator path, scheduler queue, network transport, USB device, or printer
was accessed.
