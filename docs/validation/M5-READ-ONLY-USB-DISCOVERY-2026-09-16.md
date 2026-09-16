# User-initiated native read-only USB discovery

Integrated checkpoint `7ee1212`: 38 focused reader/model/setup/store/transfer
tests passed. The actual product reader was compiled directly with a narrow
count-only native harness and executed once under a hard ten-second timeout.
It succeeded with zero scanned interfaces, unreadable classes and printer
observations. No device connection or command occurred. This exercises the
native empty-match path, not positive device metadata or GUI operation.
The complete combined gate is pending.

Parent capacity correction `a1cf439` is now integrated from pushed head
`6234f06`: public workflow saves serialize bounded capacity admission and rename
without increasing the 256-record catalog cap. Its full local 67/173/223 gate
passed. Corrected parent hosted 35095948906 and second review remain live.
The discovery combined gate is pending; older pre-fix hold statements below
are superseded by this integration checkpoint.

Partial M5-AC01/09/10 implementation only. No model/transport/identity,
installation, GUI, scheduler or hardware acceptance is added.

Setup now exposes a user-initiated registry scan and a session-only interface
observation picker. Native IOKit matching handles successful null iterators as
empty. Iteration is capped at 4096 interfaces, cancellation is checked between
operations, and the iterator must remain valid before accepting a snapshot.
Missing class metadata is counted as unknown, not silently treated as non-printer.
Only printer-class interfaces trigger bounded parent inspection (at most eight
parent hops), vendor/product/interface-number reads and a private registry ID.
No serial, name, URI, path or complete property table is collected. Every native
entry/parent/iterator handle is released. No USB service connection is opened.

Observations carry fresh session IDs and redacted descriptions; a registry ID
is not a durable physical identity. Multiple interfaces may belong to one device;
the picker explicitly lists interfaces, not unique qualified printers. Selection
does not modify the immutable printer profile or enable installation. Current
reference-profile identity remains unobserved and physical confirmations remain
separate. Refresh clears old observations/selection; stale or cancelled results
cannot replace the current snapshot. Empty/unavailable/changed/limit/unreadable
outcomes have distinct messages without embedding raw errors or private metadata.
Kernel calls themselves do not have a promised wall-clock deadline.

Native products built successfully. Thirteen focused tests passed (five reader,
three discovery model, five reference setup), covering null-iterator no-call
behavior, class filtering/unknown metadata, handle cleanup on limit/change/error,
strict numeric decoding, redacted descriptions, selection without installation
authority, stale completion/cancellation and incomplete scans.
Complete combined gate and actual GUI/positive-device metadata checks are pending.
The preceding finite native preflight exposed no matching registry objects here;
this does not prove disconnection or exercise positive device resolution.

Publication is held while parent PR #59 finding 4025900013 is fixed on its branch:
workflow imports must not publish beyond the catalog capacity, including under
concurrent writers. Integrate that correction and run the combined gate before
opening the discovery PR. Do not weaken the catalog bound or bypass review.

API provenance: [R35](../REFERENCES.md#r35), public installed SDK IOKit/USB host
headers. No third-party implementation is copied or bundled. No change to the
supplied bitmap, encoder, independent oracle, fixtures, renderer or transport.

Finite manual validation remains NOT RUN: leave physical confirmations unchecked,
launch locally built setup, perform one read-only scan, inspect the appropriate
empty/unavailable/observed message, refresh once and confirm selection is cleared.
Check keyboard/VoiceOver independently. Do not install queues or print. Positive
candidate inspection requires a host exposing the actual device; do not infer
GC420d support from a printer-class interface or vendor/product identifiers.
