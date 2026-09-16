# M3 idempotent acceptance durability — 2026-09-15

**Scope:** native source and regression evidence for review finding R12 at
`1e51a8b`. This is accepted-bundle namespace durability handling, not a claim
of unconditional power-loss persistence or scheduler acknowledgement.

## Corrected boundary

An identical `AcceptedJobStore.save` retry no longer returns success solely
because canonical ticket/source bytes and lifecycle identity are visible. Both
the first-publication and existing-identical-bundle paths require a successful
sync of the accepted-jobs parent directory. Failure after the exclusive rename,
or failure to confirm an existing identical publication, returns
`commitUncertain`.

The identical retry path reads but never replaces `state.json`. A lifecycle
that has already advanced to `prepared` remains advanced while repeated
durability confirmation fails and after a later successful retry.

## Regression evidence

The tests inject the actual parent-directory sync operation rather than a Swift
exception after rename. They cover:

- a first publication whose rename succeeds but parent sync fails;
- persistent sync failure on identical retries;
- later successful recovery through the same idempotent save;
- preservation of an already advanced lifecycle state;
- two identical writers where the first pauses after rename and the second
  performs a successful parent barrier before acknowledging success.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 64 passed;
- LabelCore — 164 passed;
- LabelMac — 112 passed;
- focused accepted-job store — 23 passed;
- independent encoder round trips — 132 passed;
- backend ABI — 15 passed;
- filter ABI — 10 passed;
- inert filter-to-discard pipeline — 1 passed.

## Evidence limits

The implementation uses the platform directory `fsync` barrier and reports its
failure conservatively. It does not describe ordinary `fsync` as a universal
device power-loss guarantee. R13 remains open for the other immutable reference
stores. No scheduler, administrator, transport, USB, or printer path ran.
