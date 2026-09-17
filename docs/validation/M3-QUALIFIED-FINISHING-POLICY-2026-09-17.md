# Qualified finishing modes and cut intentions — 2026-09-17

Partial M3-AC02/03/11 implementation; no new acceptance completion.

## Independent constraint

Model support does not prove an accessory is installed or enabled for this
configuration. `FinishingControlQualification` checks each explicitly enabled
mode against its own supported evidenced fact. Cut/peel/rewind additionally need
installation-reported true cutter/peeler/rewinder observations respectively.
Unknown, absent, model-documented presence and unobserved support fail separately.
Tear-off needs no accessory, but still requires explicit mode support/enabling.
Supplied facts are declarations, not authenticated sensor observations or consent
to perform physical tests. Default policy admits no mode and does no device I/O.

The bounded offline encoder maps tear/cut/peel/rewind to literal ^MMT/^MMC/^MMP/
^MMR fragments. Existing R45 public ^MM table (printed305–306) is provenance.
These are mode-only inspection fragments, not complete ordinary jobs: no copies,
cut intervals, prepeel normalization, delayed trigger, format envelope or hardware
completion is claimed. Existing ordinary profile7/queue6/ticket7 remains tear-off
only. GC420d absent-cutter/disabled-peeler/rewind rejection remains unchanged.

## Cut scheduling intentions

`CutSchedulePlanner` plans indices in the complete ordered engine-expanded output
label list. Every-label and end-of-job are separate evidenced capabilities. Batch
requires its own supported evidenced fact and positive model maximum at most10000.
Batch requests name final-remainder behavior explicitly. Full batch boundaries
are retained; final partial stock is cut only when requested. All indices are
monotonic, bounded and computed with division before multiplication; label counts
are1..10000 and invalid/overflow-sized inputs fail before allocation.

Mode support/installed cutter cannot substitute for schedule qualification. This
planner does not own copies/ranges, issue ^PQ, concatenate ~JK, transmit bytes or
release device ownership. R45 ^MM notes that delayed cutting requires a separate
file, and ^PQ controls quantities/group pauses/cuts. Those interactions must be
bound to a qualified delivery contract rather than treating a mode fragment or
TCP write boundary as proof of per-label/batch/job-end physical behavior.

## Automated evidence and remaining work

Six focused `FinishingControlQualificationTests` passed own exit0: all four exact
mode fragments; each separate enabled/model/accessory gate including unknown versus
false; finite output limits/destructive/copy/trigger absence; all schedules with
explicit partial remainder and maximum-size order; per-schedule/installed-cutter
independence; invalid batch/count/declaration bounds. Full finite900-second
CI-equivalent `bash scripts/ci-swift.sh` gate passed own exit0:
89 Python/262 Core/313 Mac debug/release, 132 original and180 ASCII independent
round trips per mode, finite benchmark/inert ABI/pipeline harnesses, native ARM
and minimum26 metadata, nested ad-hoc signatures and packaged-worker PBM/ZPL
equality. Local artifact: `artifacts/setup-app.WHQGAp`. This is automated
evidence, not mechanical/GUI/scheduler/physical acceptance. Deliberately allowing
model-documented accessory presence to stand in for installation observation
made the accessory test fail own exit1 with three assertions, one per accessory.
Source restored byte-for-byte (SHA256
dfe6af24932d35864d2184b6cb40af86df9649d310ce54ab4cf5db949592f036);
all262 restored Core tests passed own exit0.

Ordinary finishing/schedule profile/queue/ticket binding, prepared-label mechanical
normalization, stock compatibility and qualified wire/file boundaries remain work.
Peel label-removal waits/status, accessory-specific physical fault handling and
alternating-workflow isolation need prescribed evidence. Native controls and real
finishing need separately verified accessory configurations and finite physical
consent; the reference remains tear-off/no cutter. M1/privileged identity/lifecycle,
installed/default/dialog, keyboard/VoiceOver, USB and actual output remain open.
No printer/admin/merge/release/binary publication. Part B frozen bytes unchanged.
