# Evidence — M4 unattended workflow qualification boundary

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `b3b2a32`
- Related requirement and acceptance IDs: F11, M4-AC09, M4-AC12
- Evidence level: A (partial; the acceptance rows require I)
- Status: PASS for the portable contract only
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: portable LabelCore matching/qualification contract
- Printer/transport/stock: no printer, transport, queue, or physical stock was
  accessed
- Fixture/profile revision: synthetic structurally checked Letter workflow
  revisions 1 and 2
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelCore \
  --filter WorkflowQualificationTests
python3 scripts/run-accelerator-checks.py
```

## Expected and observed results

All five focused qualification tests and all 126 LabelCore tests passed. The
offline accelerator also passed 56 Python tests, 132 independent graphics round
trips, 15 backend ABI cases, ten filter ABI cases, and one inert pipeline.

An imported or otherwise unconfirmed matching profile returns
`confirmationRequired`, never an unattended approval. Creating an
`UnattendedWorkflowQualification` is an explicit user-confirmation operation
and requires structural checks on every page, including pages with explicit
non-label dispositions. The qualification contains the exact immutable profile
value rather than only an ID/revision pair. Changing a revision or any geometry
therefore requires a new confirmation. Geometry and structural validation occur
before qualification is considered, so a qualification cannot override a
mismatch.

The exact JSON schema encodes only `WorkflowProfile`; it has no field capable of
importing or asserting the qualification wrapper.

## Artifacts

- `Packages/LabelCore/Sources/LabelCore/WorkflowQualification.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/WorkflowQualificationTests.swift`

## Limitations / next action

This is partial automated evidence for M4-AC09 and M4-AC12; neither row is
closed because each requires installed macOS integration evidence. There is not
yet a durable profile store, a UI confirmation action, an installed offline
detector path, queue/profile binding, mismatch-review workflow, or restart
recovery test. The next slice should define bounded atomic profile persistence
that stores definitions and local qualification state separately, then expose
it through the teach-once editor rather than treating imported JSON as trusted.
