# Evidence — M4 workflow-profile import safety

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `73a881d`
- Related requirement and acceptance IDs: F11, M4-AC08
- Evidence level: A
- Status: PASS
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: portable LabelCore workflow-profile JSON codec
- Printer/transport/stock: no printer or transport was accessed
- Fixture/profile revision: synthetic schema-1 two-page workflow with an
  extraction region, structural anchor, and explicit non-label skip
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelCore --filter WorkflowProfileJSONTests
python3 scripts/run-accelerator-checks.py
```

## Expected and observed results

All four focused codec tests and all 116 LabelCore tests passed. Repository
preflight, fixture integrity, 56 Python tests, 132 independent graphics round
trips, 15 backend ABI cases, ten filter ABI cases, and one inert pipeline case
also passed.

The version-1 JSON contract uses an exact allowlist at every object level and a
non-raisable 256 KiB cap. It rejects malformed JSON, oversized input, attempts
to raise the cap, unknown schema versions, missing/wrong fields, booleans or
out-of-range values in integer fields, unsupported enum values, unsafe typed
geometry, and oversized output. Unknown top-level and nested fields are
rejected; regressions specifically try raw-command, filesystem-path, and
embedded-document fields. Imported profiles contain only typed identifiers,
dimensions, normalized regions, enumerated rotation/scale/page policies, and
typed structural anchors. Encoding is deterministic and round-trips the exact
immutable profile value.

## Artifacts

- `Packages/LabelCore/Sources/LabelCore/WorkflowProfileJSON.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/WorkflowProfileJSONTests.swift`

## Limitations / next action

This proves the portable data contract and closes M4-AC08. It does not prove a
file-picker UI, profile storage permissions, migration from a future schema,
teach-once interaction, native analysis, queue binding, or physical output.
The next portable/native slice should render planned regions from the original
PDF into the existing canonical bitmap/preview path.
