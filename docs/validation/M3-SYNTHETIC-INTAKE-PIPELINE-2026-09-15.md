# M3 synthetic descriptor-intake pipeline — 2026-09-15

**Scope:** native automated evidence at `5a34971` with review remediation at
`6e11d16`. This connects an already
opened synthetic PDF to immutable configuration resolution, accepted-job
publication, original-document rendering, complete prepared-byte publication,
persisted lifecycle, the shared device lease, and the in-memory discard sink.
It is not installed scheduler, transport, USB, or physical-printer acceptance.

## Implemented boundary

`BoundedRegularFile` can read an already-open regular-file descriptor with
bounded `pread` calls. It does not resolve the pathname again, change the
caller's shared offset, or accept a changing file. The existing no-follow path
API now uses the same descriptor-relative implementation.

`SyntheticInertJobPipeline` then:

1. reads the submitted PDF through that descriptor under the 100 MiB cap;
2. resolves the active immutable queue, workflow, qualification, and printer
   profile chain;
   the workflow output stock must exactly match the observed loaded label face;
3. analyzes the original PDF and rejects geometry, structural, or unexpected-
   page mismatches before publishing an accepted bundle;
4. records upstream ownership of already-applied copies and page ranges in the
   accepted ticket;
5. renders every planned region from the retained original PDF at the GC420d's
   documented 8 dots/mm reference pitch and the workflow's physical stock;
6. uses the production typed control and graphic encoders to build one complete
   ordered prepared payload while reducing the remaining encoder budget after
   every label, so eager preparation cannot exceed the 64 MiB aggregate cap;
7. publishes that payload before delivery becomes eligible; and
8. uses the persisted lifecycle and ticket-derived device lease to send only
   to the bounded in-memory discard sink.

The fixed reference pitch is model documentation, not measured printable-area
or placement evidence. The class rejects other printer models rather than
silently applying that pitch to them.

An exact retry first resolves the existing accepted bundle by immutable ticket
references, checks the supplied source and cancellation capability, and repeats
the accepted-bundle durability barrier. Prepared and waiting jobs reuse their
validated stored payload, even if the active queue selection has advanced.
Terminal or ambiguous states remain non-deliverable through this entry point.

## Regression evidence

The native end-to-end regression opens the committed vector PDF, replaces its
pathname with different bytes, and proves that acceptance retains and hashes
the originally opened descriptor. It verifies upstream copy/page-range
ownership, scheduler provenance, nonempty production-format prepared bytes,
and the final persisted `transmitted` state. That state means only local
discard-sink completion.

A separate regression submits a multi-page fixture to a one-page qualified
workflow. The unexpected page is rejected before any accepted bundle is
published. The descriptor reader regression independently proves pathname
replacement stability and an unchanged caller offset.

Review regressions additionally prove that a two-label job stops at a reduced
400,000-byte test budget without publishing prepared state, both `prepared`
and `waiting` retryable states resume through the public pipeline entry point,
a wrong cancellation capability cannot resume a job, an accepted job remains
bound to its original immutable queue after the active selection advances, and
a workflow/loaded-stock mismatch is rejected before acceptance. Optional bundle
lookup returns nil only for absence; an unsafe present bundle remains an error.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 64 passed;
- LabelCore — 165 passed in debug and release;
- LabelMac — 137 passed in debug and release;
- focused descriptor/pipeline/store suite — 12 passed;
- independent encoder round trips — 132 passed;
- backend ABI — 15 passed;
- filter ABI — 10 passed;
- inert filter-to-discard pipeline — 1 passed;
- local ad-hoc command products and setup app — signatures verified.

## Evidence limits and next boundary

This is additional partial automated M3-AC02/09/12 evidence. It does not close
the required integration levels. Rendering remains in the unprivileged test
process; this slice does not establish the production worker deadline,
scheduler exit/retry mapping, restart reconciliation, retention, multi-process
service identity, or installed access permissions.

No CUPS API, administrator path, queue, protected installation location,
network endpoint, USB device, or printer was accessed. The next production
boundary is a reviewed process/IPC contract that preserves the same immutable
bindings and uncertainty rules; the authorized M1 discard experiment remains a
separate finite installed-scheduler observation.
