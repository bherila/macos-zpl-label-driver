# Evidence — M4 native teach-once editor components

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `7c5e58b`
- Related requirement and acceptance IDs: F11, F12, M4-AC01, M4-AC06,
  M4-AC09, M4-AC12
- Evidence level: A/C (partial; the acceptance rows retain their I gates)
- Status: PASS for component/model automation only
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: reusable LabelMac SwiftUI editor and main-actor model
- Printer/transport/stock: no printer, transport, queue, or physical stock was
  accessed
- Fixture/profile revision: generated two-tone vector PDF and synthetic
  structurally checked profile revisions 1 through 3
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelMac --filter WorkflowEditorTests
bash scripts/ci-swift.sh
```

## Expected and observed results

All four focused editor tests passed. The complete CI-equivalent sequence passed
130 LabelCore tests and 63 LabelMac tests in both debug and release
configurations, 56 Python tests, 132 independent graphics round trips, 15
backend ABI cases, ten filter ABI cases, one inert pipeline, and local ad-hoc
signature checks.

The reusable SwiftUI view and main-actor model expose:

- source-page region selection and one global output order;
- explicit millimeter fields and a distinct physical-output-stock summary;
- right-angle rotation controls;
- keyboard shortcuts for preview, save, and earlier/later ordering;
- separate save and unattended-approval actions, with approval disabled until
  the current revision is saved;
- accessible error and preview labels that do not rely only on color; and
- correction reload as a new immutable revision.

Preview planning uses analyzed original-page geometry and renders the original
PDF through `QuartzPlannedExtraction`. The displayed `CGImage` expands the same
packed `MonochromeBitmap` passed to the encoder. A correction from the black
left half to the white right half of the vector fixture changes the exact packed
bytes, and editing invalid millimeter geometry leaves both draft and preview
unchanged. Save, separate confirmation, reload, and revision advancement are
tested against the real private profile store.

## Artifacts

- `Packages/LabelMac/Sources/LabelMac/WorkflowEditor.swift`
- `Packages/LabelMac/Tests/LabelMacTests/WorkflowEditorTests.swift`

## Limitations / next action

This adds substantial implementation and automated evidence but closes no I
row. View construction is not a hands-on keyboard/accessibility test, and these
components are not yet hosted by a signed setup application with document
selection and lifecycle. M4-AC01 also remains open until queue options preserve
the input/output media split. The next slice should add the setup-app target and
an editor host/document-open flow, then record a finite local UI procedure for
manual interaction evidence.
