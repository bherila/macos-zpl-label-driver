# M2 nonblocking regular-file open — 2026-09-15

**Scope:** macOS source and subprocess evidence for bounded file ingestion at
`88fb87e`.

## Corrected boundary

Every prospective regular-file read now uses one shared open rule:
read-only, nonblocking, no-follow, and close-on-exec. Path-based PDF/ticket
ingestion and descriptor-relative immutable-store reads therefore obtain a
descriptor without waiting for a FIFO peer, then retain their existing checks
for file type, owner, link count, permissions, size, and stable metadata.

Regular files retain their previous bounded read behavior. Directories,
symbolic links, hard-linked private artifacts, oversized inputs, and changing
metadata continue to fail closed.

## Regression evidence

Native subprocess tests impose a two-second hard deadline and verify rejection
of FIFO names both with and without a writer. The names cover CLI PDF/ticket
inputs and the state, prepared-payload, workflow, printer-profile, queue, and
active-selection record classes. Separate real CLI subprocesses verify that a
FIFO PDF or ticket exits as input failure before the render worker starts.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- repository preflight — passed;
- Python suite — 60 passed;
- LabelCore — 164 passed;
- LabelMac — 107 passed;
- independent encoder round trips — 132 passed;
- backend ABI — 15 passed;
- filter ABI — 10 passed;
- inert filter-to-discard pipeline — 1 passed.

## Evidence limits

This closes the source-level R14 blocking-open defect. It does not establish
scheduler intake, installed-spooler behavior, hostile filesystem power-loss
semantics, transport, or physical-printer acceptance. No queue, protected
system path, scheduler job, or printer was accessed.
