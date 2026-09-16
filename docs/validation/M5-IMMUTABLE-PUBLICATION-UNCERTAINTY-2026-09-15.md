# M5 immutable publication uncertainty — 2026-09-15

**Scope:** native source and regression evidence for review finding R13 at
`f42226d`, including directory-barrier remediation at `f4bb7f8` and `c4798ef`.
This is a local persistence result contract, not installation,
scheduler, delivery, or physical-printer acceptance.

## Corrected boundary

Workflow profiles, unattended-use qualifications, printer profiles, and
virtual queue definitions now use one descriptor-relative immutable publisher.
The publisher writes and syncs a private temporary regular file, publishes it
with an exclusive rename, and requires a successful target-directory barrier
before returning success. Publication then requires a barrier on the stable
store root so a newly created category entry is also durability-acknowledged,
then a verified barrier on the directory containing that root so the root's own
entry is acknowledged. An identical retry repeats all barriers rather than treating visible byte
equality as durability acknowledgement.

Exact visible bytes are reconciled before a retry creates or syncs another
temporary file. A known ambiguous publication therefore cannot be downgraded to
an ordinary pre-commit failure merely because redundant staging fails.

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
- a successful category barrier followed by a failing store-root barrier
  returns uncertainty, with an identical retry required to complete both; and
- a successful category/root sequence followed by a failing containing-parent
  barrier also returns uncertainty, after verifying the reopened root inode;
- an identical uncertain retry does not enter injected fallible staging before
  re-establishing the required barriers; and
- a conflicting retry remains a conflict and cannot replace the visible
  immutable winner.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 64 passed;
- LabelCore — 165 passed in debug and release;
- LabelMac — 121 passed in debug and release;
- focused workflow/profile/queue stores — 26 passed;
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
