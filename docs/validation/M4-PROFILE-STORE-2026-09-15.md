# Evidence — M4 immutable local profile store

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `df06929`
- Related requirement and acceptance IDs: F11, M4-AC06, M4-AC08, M4-AC09,
  M4-AC12
- Evidence level: A (partial; UI and installed-path rows retain I gates)
- Status: PASS for the native storage contract
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: LabelMac user-local workflow profile store
- Printer/transport/stock: no printer, transport, queue, or physical stock was
  accessed
- Fixture/profile revision: synthetic structurally checked Letter workflow
  revisions 1 and 2
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelMac \
  --filter WorkflowProfileStoreTests
bash scripts/ci-swift.sh
```

## Expected and observed results

All six focused profile-store tests passed. The complete CI-equivalent sequence
passed 126 LabelCore tests and 59 LabelMac tests in both debug and release
configurations, 56 Python tests, 132 independent graphics round trips, 15
backend ABI cases, ten filter ABI cases, one inert pipeline, and local ad-hoc
signature checks.

The store keeps exact immutable profile JSON and local unattended-use
qualification records in separate private directories. Profile IDs never
become path components; opaque SHA-256-derived filenames prevent traversal.
Directories and reads use owner, mode, regular-file, single-link, and no-follow
checks. Writes use a private exclusive temporary file, complete writes, file
`fsync`, exclusive atomic rename, and directory `fsync`. Saving the same bytes
is idempotent; a different definition with the same ID/revision is a conflict.
Concurrent conflicting writers leave exactly one complete winner.

Qualification requires the exact stored definition and writes only its ID,
revision, and canonical profile digest. Import/save alone leaves a profile
unqualified. Missing definitions, changed geometry, changed revisions,
malformed records, and digest tampering fail closed.

## Artifacts

- `Packages/LabelMac/Sources/LabelMac/WorkflowProfileStore.swift`
- `Packages/LabelMac/Tests/LabelMacTests/WorkflowProfileStoreTests.swift`

## Limitations / next action

This strengthens M4-AC08 and supplies partial automated evidence for
M4-AC06/09/12, but closes no additional row. The store has not yet been wired
to a SwiftUI/AppKit editor, application sandbox/container selection, queue
binding, installed service identity, migration UI, or restart recovery flow.
The next safe slice should add reusable teach-once editor state and commands
over this store, with canonical-coordinate editing and exact preview inputs;
keyboard and rendered UI validation will still require integration evidence.
