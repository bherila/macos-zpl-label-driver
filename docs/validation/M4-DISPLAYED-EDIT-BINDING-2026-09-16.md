# Displayed-region edit binding

Complete implementation gate at `308f1c9` passed exit 0: 67 Python/173
LabelCore/233 LabelMac debug/release, both accelerators, 132 independent round
trips, 15/10/1 inert ABI/pipeline cases, local executable/app/nested-worker
signatures and packaged-worker PBM/ZPL equality. This supersedes pending local
gate status below. Own hosted/review and the finite native interaction procedure
remain pending. Parent #61 run 35096482907 passed exact `9b66565`; first review
is clean at unchanged base `6234f06`/head `9b66565`, with no inline findings.

Partial M4-AC06/12 source and automated evidence only. No native interaction,
application/scheduler, printer or physical-label acceptance is added.

## Reproduced defect

The existing measurement binding captured one displayed region's values, then
dispatched through the current-selection model setter. A synthetic two-region
regression captured that callback, changed selection without changing the draft,
and invoked it. The pre-fix test exited 1 with three assertions failing: no
rejection, changed profile, advanced edit generation. It edited the newly
selected region. This reproduces the source callback path, not a physical GUI
timing experiment; no private PDF or device was used.

## Correction

Native displayed numeric/rotation/reorder/add/remove controls capture an
in-memory region ID and edit generation. Model validation rejects mismatches
before draft mutation, revision allocation or review invalidation. Drawing
captures the same binding at gesture start alongside its viewport, and rejects
an intervening edit before commit. Generation binding also rejects edit/undo
returning to an identical profile value. Measurement callbacks retain their
displayed physical page size rather than force-unwrapping a later profile's page.

Immediate trusted current-selection APIs remain available for programmatic use;
their optional displayed binding is not an authorization token or persisted
schema. The actual native region controls always supply the binding. No encoder,
renderer, profile JSON, bitmap, oracle or fixture contract changes. Saving,
page-policy confirmation and qualification keep their separate existing gates;
this increment does not claim all UI lifecycle actions are snapshot-bound.

## Validation

43 focused native editor/document-opening/bootstrap tests passed, including
the corrected selection-change reproduction and stale numeric/rotation/reorder/
add/remove/draw model actions after edit/undo. Current binding still admits an
ordinary edit; rejected actions preserve profile, selection and generation.
Full combined local gate, own hosted/review and native interaction are pending.
Parent #61 hosted 35096482907 and first review remain live at `9b66565`.

## Finite native procedure — NOT RUN

Leave physical confirmations unchecked. Open a committed synthetic PDF and add
a second label region. Edit millimeter fields with keyboard, including rapid
multi-character input, and verify only the selected region changes. Change
selection while a field is active and while drawing, then verify no wrong-region
or obsolete-geometry commit. Check rotation/reorder/add/remove, save/reopen and
exact packed preview after a valid edit. Record rejected legitimate input or
focus problems as failures, not acceptance. Check VoiceOver separately. Do not
install, submit scheduler jobs or print; source tests cannot pass this procedure.
