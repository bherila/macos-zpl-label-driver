# Private-safe localized editor action errors — 2026-09-17

Evaluated local unpublished source `f14b71c18368a4008c007783e0de07f24e3c563e`. Advances M4 teach-once recovery and M5 useful/localizable error implementation, without claiming M4-AC06/M5-AC10 integration acceptance or whole M3-AC12 privacy acceptance.

## Defect and behavior

WorkflowEditorModel.report formerly displayed String(describing: error). Caller/framework errors could disclose file paths or private identifiers and known action errors appeared as implementation case names. Fixed localized messages now cover the six editor errors, seven draft errors, workflow-store errors and geometry errors. Unknown errors get fixed review guidance. Store commitUncertain retains an explicit save-uncertainty warning: preserve the draft and review saved revisions before retrying. This function grants no retry authority and changes no draft/review/save state.

Nearest independent constraint: useful error reporting must preserve uncertainty and immutable draft/save state while admitting no caller-supplied diagnostic text. The regression exercises a synthetic NSError with private-looking domain/path/description, a missing-region identifier, a stale edit snapshot and an uncertain-store publication identity. Expected private-safe user messages, unchanged profile/edit generation/save flag and no synthetic marker are asserted.

## Actual validation

Before fix: focused regression exit1, one test with six failing assertions, zero unexpected failures. Final WorkflowEditorTests and OfflineSetupDiagnosticsTests:21 tests debug and21 release, zero failures, both command exits0. Repository preflight,106 Python tests and diff check exited0. Logs `/tmp/zpl-editor-errors-before.log`, `debug.log`, `release.log`, `preflight.log`, `python.log` (latter names share `/tmp/zpl-editor-errors-` prefix). No zero-test result used as evidence.

Core/accelerator tests NOT RUN for this native editor-only change; portable code, encoder and independent oracle unchanged. Full native CI, local artifact signing, GUI/keyboard/VoiceOver, minimum-runtime26, Linux, installed scheduler/helper/admin and physical printer evidence NOT RUN for this slice. Fixed messages are localizable source strings; actual translated-locale behavior is not qualified. Manual diff/disclosure reading confirmed fixed message vocabulary and synthetic test data only.

No acceptance/ledger refresh, printer I/O, queue or privileged operation, merge or publication. Prior integrated whole-source receipts are historical after source changes; frozen Linux and PartB candidates unchanged. Next: reconcile the remaining implemented privacy/IPC/options paths and reviewable source integration with existing PR81; production adapter/helper and manual/physical gates remain open.

## Implementation digests

- `Packages/LabelMac/Sources/LabelMac/WorkflowEditor.swift`: `706a2bc4645bbb15b33a860c3dc78838674926aba865a6cfa83f79e02533cdcf`
- `Packages/LabelMac/Tests/LabelMacTests/WorkflowEditorTests.swift`: `d27bd1edf52618e2adef9936bb7a33f5ff7b1e5698e37a20f197e4a1be8ba069`
