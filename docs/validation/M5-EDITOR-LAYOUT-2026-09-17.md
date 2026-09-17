# M5 — issue #80 extraction editor layout correction

## Failure and independent constraint

The maintainer's manual GUI test on 2026-09-17 observed setup text and controls
painting over the extraction editor after selecting a PDF, covering **Show Source
Page**. GUI acceptance is FAIL/BLOCKED, not a successful launch or preview check.
The broken preview release and GitHub tag were explicitly authorized for removal;
both were removed and independently read back absent. Issue #80 now records the
withdrawal and blocker instead of recommending the broken download.

The nearest independent constraint is that a native split editor embedded in a
vertical scrolling setup must reserve a finite useful height for both panes;
its detail content must scroll inside that allocation rather than overlap
neighboring setup sections. The old view's native offscreen `fittingSize.height`
was **0**, reproducing an allocation failure. The fixed view reserves a 720-point
viewport and scrolls details independently. A native regression tests useful
finite allocation at widths 820, 900 and 1200. Persistent visible millimeter
labels identify the populated crop fields; their edit/snapshot bindings are
unchanged. No rendering, ticket, profile or printer-control semantics change.

## Validation

- Old-code native layout regression: one test, one assertion failure (height 0).
- Corrected native layout regression: PASS at three widths.
- `swift test --package-path Packages/LabelMac --filter WorkflowEditor`: exit 0,
  31 tests, no failures; includes bootstrap, native allocation and stale-edit /
  exact original preview behavior.
- Corrected `bash scripts/build-local-app.sh`: exit 0; app/worker signatures,
  ARM architecture, deployment minimum 26 and packaged-worker PBM/ZPL equality
  passed. Local artifact directory `artifacts/setup-app.N8tFGX`; this artifact
  is separately identified for the maintainer retest and is not a public release.
- Full debug/release local gate and hosted checks: pending correction validation.
- Actual on-screen Show Source Page/crop/Preview and accessibility retest: NOT RUN.
  The offscreen allocation regression is not an interactive GUI acceptance pass.

Actual test host: macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a), Swift 6.4;
minimum deployment remains 26.0. Do not infer new Tahoe support evidence.
Partial M5-AC10 / M4-AC01 implementation only. No physical or privileged I/O.

## Finite maintainer retest

Quit the old app. Open the specifically identified corrected local artifact or
build the pinned corrected branch after publication; do not use the withdrawn
preview. Keep both hardware confirmations unchecked. Follow issue #80 section A
with the committed synthetic Letter PDF. Scroll inside the editor if needed.
Require separate non-overlapping setup/editor sections, a clickable **Show Source
Page**, visible field labels and a nonempty exact packed Preview. Report runtime
and artifact identity plus observed results. Do not approve, install or print.
