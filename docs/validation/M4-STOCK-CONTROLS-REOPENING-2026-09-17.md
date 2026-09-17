# Native stock controls and reopening — 2026-09-17

Source evaluated: `ed5040780794acab12254839a0253bdaf5fe3c21` (local, unpublished).

Editor exposes width/height with explicit millimeter labels and accessibility names using existing numeric field handling. Displayed callbacks bind selected region/edit generation and preserve the other stock dimension. Changes use the validated model API and custom-stock identity. Guidance requires separate physical stock/printer-limit verification. Source-page geometry remains distinct.

Saved-workflow bootstrap now admits an offline changed-stock candidate under existing finite DotCanvas budgets and configured8dots/mm preview pitch, rather than requiring exactly4×6. Supported detector checks, original-PDF analysis, immutable correction revision, planner checks and new-session review remain required. Production queue/finishing stock qualification checks are unchanged; offline preview geometry is not printer qualification. Oversized stock is rejected before launching a child.

Regression reproduced unsupportedOutputStock when reopening an editor-saved changed stock:1test/1failure, own exit1, /tmp/zpl-stock-reopening-before.log. Final reopening regression uses original Letter PDF,2×3 stock, immutable saved revision, unreviewed correction and real worker exact406×610 packed preview. Added oversized80,000dot saved-stock rejection with nonexistent executable to establish pre-child admission.

Final35native editor/bootstrap tests passed debug/release, own exits0: /tmp/zpl-stock-controls-final-debug.log and /tmp/zpl-stock-controls-release.log. Earlier34debug passed before final oversized regression.106Python and repository preflight passed own exits0. Diff check passed. Finite300seconds per command wrapper completed successfully. Local app build/nested ad-hoc verification and packaged-worker PBM/ZPL fidelity passed own exit0: /tmp/zpl-stock-controls-app.log, artifact artifacts/setup-app.ngHpWz/Label Printer Driver Setup.app. This does not replace frozen Part B candidate.

Full native/Core/accelerator/Linux suites NOT RUN for this native UI/bootstrap slice. Visual GUI layout, numeric typing/keyboard interaction, VoiceOver, actual runtime26, clean installation, scheduler/administrator and physical printing NOT RUN. No acceptance ledger refresh, hardware qualification, queue/device write, merge or publication. Next: current integrated source validation, native UI manual checklist and whole media/privacy requirement reconciliation.
