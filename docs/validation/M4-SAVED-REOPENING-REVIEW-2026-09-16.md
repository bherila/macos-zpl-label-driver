# Saved reopening first-review remediation

Additional partial M4-AC01/06/12 automated implementation only. PR #56's first
review at `ef26682` found three genuine P2 defects; all are fixed on that branch,
not deferred to an unrelated PR. Original hosted run 35085759520 passed, but
that did not establish these corrections or GUI acceptance.

1. Historical correction now copies the selected definition into a revision
   beyond the latest observed stored revision of the same logical profile.
   The trusted store verifies the selected canonical snapshot and derives the
   next revision using its existing bounded catalog. Opening, explicit reload
   and post-save editing reuse that method. Old records/qualifications remain
   unchanged. This is not a reservation: two editors can observe the same latest
   revision, and immutable publication still fails a conflicting save rather
   than overwriting. Catalog limits/failures remain explicit; pagination is future.
2. The setup checks the configured pre-cut stock identity as well as physical
   dimensions. Equal-size continuous or foreign stock is not an alias for the
   configured reference. Records are rejected, never clamped or rewritten.
3. Non-border expectations fail with an explicit unavailable-layout-detector
   error before worker admission. The current analyzer supports borders only;
   valid future barcodeLike/darkBlock schema values are not proof of implemented
   detectors, nor evidence that an unchanged PDF has a different layout.

52 focused native tests passed: 13 document-opening, 16 workflow-store,
12 bootstrap and 11 editor. New regressions reopen revision 1 with revision 2
present, edit/save revision 3, advance a stale saved editor to revision 4 and
reload old history as revision 5 while preserving all old definitions. A store
test copies revision 1 beyond latest revision 7 without adopting its changed
coordinates or an unrelated profile's revision 99. Equal-size foreign-stock and
same-ID wrong-dimension tests independently discriminate the setup checks.
Both unsupported detector kinds fail before an intentionally unavailable worker
can be admitted. Existing original-source preview, stale/cross-store, canonical,
resource, FIFO and qualification regressions remain intact.
At implementation `4d430c376c35f5990498e50606b3d7f607a52dd3`, the full local
CI-equivalent sequence reached its final verified-app completion: 67 Python,
171 LabelCore and 208 LabelMac tests passed in debug/release; both accelerator
runs passed 132 independent round-trips plus inert checks. Local ad-hoc executable,
app and nested-worker signature checks and packaged-worker PBM/ZPL equality passed.
The original process handle expired before its exit status could be read; these
results are confirmed from the complete fail-fast script log, not a recovered
exit-code claim. Corrected exact-head hosted CI and second review remain pending.

No queue, job, printer, privilege or physical output used. No new schema or
transport retry authority added. Complete GUI/VoiceOver, install/scheduler and
hardware acceptance remain unproven. The subsequent readiness slice corrects
the earlier AXWindows observation: its element had AXApplication role and menus,
not a verified AXWindow. No GUI pass is inferred from that probe.
