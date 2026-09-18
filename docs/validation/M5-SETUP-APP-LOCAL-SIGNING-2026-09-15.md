# Evidence — M5 setup-app host and local signing-mode separation

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `75c2aee5fdcd373d7050ad25c6de71c169350e68`
- Related requirement and acceptance IDs: F11, F12, N11, M4-AC06,
  M4-AC09, M4-AC12, M5-AC02, M5-AC10, M5-AC11, M5-AC12
- Evidence level: A/C; M5-AC12 PASS, other listed rows partial only
- Status: PASS for the bounded app build, bootstrap tests, exact local signature,
  and fail-closed signing-mode selection
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3, SDK 26.5
- Application path: local SwiftUI setup app and security-scoped PDF-open flow
- Printer/transport/stock: no printer, transport, queue, scheduler mutation, or
  physical stock was accessed
- Fixtures: committed native-vector, letter-one, a4-one, ambiguous-region,
  mixed-pages, and non-label-pages PDFs plus a generated borderless native page
- Profile/job-ticket revision: new unsaved local workflow revision 1; no job
  ticket or delivery payload
- Hardware/installation authorization: not required; zero labels, zero device
  commands, zero privileged operations, and zero system changes

## Procedure

```sh
python3 scripts/check_repo.py
python3 -m unittest discover -s scripts/tests
swift test --package-path Packages/LabelCore
bash scripts/ci-swift.sh
```

The CI-equivalent script also invoked both signing modes:

```sh
bash scripts/build-local-app.sh --signing-mode developer-id
bash scripts/build-local-app.sh
```

The first command was required to fail before building or signing because no
Developer-ID mode is configured. The second built the ARM release executable,
assembled the app bundle, signed the executable and containing bundle with an
ad-hoc identity, verified each after final signing, and inspected the minimum
OS and architecture.

## Expected and observed results

Repository preflight and 56 Python tests passed. LabelCore passed 130 tests.
LabelMac passed 70 tests in both debug and release. The reused accelerator
oracles passed 132 independent round trips, 15 backend ABI cases, ten filter
ABI cases, and one inert filter-to-discard pipeline case.

Seven focused bootstrap tests establish that:

- native 4x6, Letter, and A4 inputs remain distinct while targeting the same
  nominal 4x6 output stock;
- native pages use their full original page and do not require an artificial
  border;
- Letter and A4 candidates become unsaved, unqualified editable drafts using
  the bounded structural analyzer and original PDF;
- the editor preview expands the exact packed bitmap passed to the encoder;
- an ambiguous two-label sheet is rejected instead of choosing one label;
- mixed geometry and an unexpected non-label page are rejected rather than
  silently discarded; and
- the configured page cap is enforced before a draft is created.

The produced executable was thin `arm64`, carried `LC_BUILD_VERSION` minimum
macOS 26.0, and its containing bundle reported `Signature=adhoc`, no Authority,
and no TeamIdentifier. `LabelDriverSigningMode` was `local-ad-hoc`, and the UI
visibly identifies itself as a local ad-hoc development build. Selecting
`developer-id` failed with exit 2 and did not fall back. This satisfies
M5-AC12 at automated level.

## Artifacts

- Source executable SHA-256 from this run:
  `0cc4f2db737664382e4e3b254882edfe727a131bfe5c74c8576c70263e8e8992`
- Bundle Info.plist SHA-256 from this run:
  `f4bb9554fab39834d6ba2854127318b44b1d8d00d80e8dcdd02be5b0b75e4522`
- `Packages/LabelMac/Sources/LabelSetupApp/main.swift`
- `Packages/LabelMac/Sources/LabelMac/WorkflowEditorBootstrap.swift`
- `Packages/LabelMac/Tests/LabelMacTests/WorkflowEditorBootstrapTests.swift`
- `scripts/build-local-app.sh`

The generated app bundle remains an ignored local artifact and is not a
published release.

## Limitations / next action

This is not install, Gatekeeper, quarantine, scheduler, helper, restart,
accessibility-walkthrough, or physical-printer evidence. M5-AC01 through AC11
and M5-AC13 remain open except for the narrow partial implementation described
above. M5-AC02 also requires inspection of every eventually shipped component,
not only this app. The next safe slice is a nonprivileged setup/status model and
diagnostics UI; privileged lifecycle work remains gated on the accepted M1
architecture and a separately authorized finite administrator experiment.
