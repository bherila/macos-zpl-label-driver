# Editor output margins — 2026-09-17

Evaluated local unpublished 304a392fccbcbc0b6cb8df5158d229a83a2f93a8.

WorkflowEditorModel.setOutputMargins binds edits to displayed generation/region, prepares immutable draft and quantized placement before mutation, cancels prior preview and clears review/save state. Saved revisions remain unchanged; corrected profile preserves schema3/margins. Stock editing also validates current margins against its proposed canvas before committing, so physically positive but dot-empty inset areas reject atomically. Native view exposes labeled left/top/right/bottom millimeter fields in two rows using existing measurement controls; no selection disables margin editing. Copy distinguishes reserved blank area from unmeasured printer calibration and requires a new exact preview.

Nearest independent constraints: saved revision immutability, stock dot rounding, review invalidation, displayed callback freshness and delayed subprocess completion. New tests cover saved correction, page-rule preservation, stale margin binding, physically positive quantized-empty margin/stock changes retaining profile/preview/generation/review, save/reload preservation, and real worker completion barrier proving obsolete margin preview cannot overwrite newer output. Worker calls and barrier arrival use finite5second deadlines. Initial test compile omitted three required margin initializer fields; corrected before actual passing runs, no runtime before-fix proof claimed.

Actual validation:23focused editor tests passed on final view/source debug and release, own exits0 (/tmp/zpl-editor-margins-debug-ui-final.log, /tmp/zpl-editor-margins-release.log).106Python passed (/tmp/zpl-editor-margins-python.log); preflight/diff passed. build-local-app.sh terminal exit0 (/tmp/zpl-editor-margins-app.log), ARM/min26 metadata and local ad-hoc app/nested executable signatures verified, packaged worker synthetic PBM/ZPL equals release worker. Local app artifacts/setup-app.Ab82hG/Label Printer Driver Setup.app is not frozen PartB52ba93f candidate. No printer accessed.

Core unchanged; preceding309Core both-mode evidence remains scoped. Full native/accelerator/current Linux/GUI/keyboard/VoiceOver/retail runtime26/scheduler/admin/physical validation NOT RUN. App build/signatures do not establish visual, Gatekeeper, installation or printer acceptance. No acceptance/ledger refresh, push, merge, publication, queue/device/privileged mutation. Frozen Linux77de47c archive remains historical.

Next: enable workflow3 references coherently across queue/job/finishing snapshot admission and reconstruction with compatibility tests; run integrated native gate before current whole-source claims. Manual M4-AC06 remains open.

## File SHA256
- `Packages/LabelMac/Sources/LabelMac/WorkflowEditor.swift`: `578b0fdf168ced0201be984c579c8e0afcdc38be94d1f04cb7ad79487ef282f5`
- `Packages/LabelMac/Tests/LabelMacTests/WorkflowEditorTests.swift`: `4d5c505914c202ce159951d7a1ca816ee7dad50ec50d06bacfb6bfb582658b46`
