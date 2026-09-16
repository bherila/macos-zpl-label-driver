# M3 descriptor-bound job lifecycle — 2026-09-15

**Scope:** native source and regression evidence for review finding R11 at
`5a1d04a`. This is persistence and authorization binding evidence, not scheduler
intake, delivery, or physical-printer acceptance.

## Corrected boundary

`AcceptedJobStateStore` is now constructed from one validated
`AcceptedJobStore` capability. It no longer accepts an independently selected
accepted-job store on each transition. The repository keeps a descriptor for
the validated private `accepted-jobs` directory, duplicates that descriptor for
operations, locks the selected bundle, and loads the immutable ticket and
mutable lifecycle state through that same bundle descriptor.

Lifecycle schema 2 binds every state record to the SHA-256 digest of the exact
canonical accepted ticket. Initial publication writes that binding atomically
with the ticket and source. Loads, prepared publication, ordinary transitions,
and cancellation all require the state, expected record, locked bundle, and
ticket digest to agree. Cancellation checks its bounded capability only after
the exact bundle has been locked and loaded.

## Regression evidence

Native tests cover two independent valid repositories with the same acceptance
identifier but different tickets and cancellation capabilities. A capability
from repository A cannot cancel repository B, an expected state from A cannot
advance B, neither failure modifies B, and B's own capability still cancels B.

A separate path-replacement test binds a state store, renames the repository,
creates a different valid repository at the old pathname, and proves that the
bound store continues to load and update the original descriptor-selected
bundle while leaving the replacement empty.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 64 passed;
- LabelCore — 164 passed;
- LabelMac — 109 passed;
- focused lifecycle store — 20 passed;
- independent encoder round trips — 132 passed;
- backend ABI — 15 passed;
- filter ABI — 10 passed;
- inert filter-to-discard pipeline — 1 passed.

## Evidence limits

The state format is an atomic current-record CAS with a predecessor marker, not
a retained audit journal or rollback-detection log. Publication-durability
findings R12 and R13 remain open in later slices. No administrator path,
scheduler queue, network transport, USB device, or printer was accessed.
