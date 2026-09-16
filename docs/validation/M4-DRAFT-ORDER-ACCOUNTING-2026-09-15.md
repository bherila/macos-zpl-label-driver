# Evidence — M4 canonical draft, ordering, and page accounting

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `05eb16d`
- Related requirement and acceptance IDs: F11, F12, M4-AC03, M4-AC05,
  M4-AC06
- Evidence level: A
- Status: PASS for M4-AC03 and M4-AC05; partial for M4-AC06
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: portable LabelCore workflow draft and extraction planner
- Printer/transport/stock: no printer, transport, queue, or physical stock was
  accessed
- Fixture/profile revision: synthetic two-page, three-region Letter workflow,
  revisions 4 and 5
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelCore \
  --filter WorkflowProfileDraftTests
swift test --package-path Packages/LabelCore \
  --filter ExtractionPlanTests
python3 scripts/run-accelerator-checks.py
```

## Expected and observed results

All four focused draft tests and the existing six extraction-planner tests
passed; the full accelerator passed all 130 LabelCore tests, 56 Python tests,
132 independent graphics round trips, 15 backend ABI cases, ten filter ABI
cases, and one inert pipeline.

A draft created from revision 4 becomes revision 5. Canonical normalized
coordinates and right-angle rotation survive validation. Moving region B from
the third global position to the first rewrites one contiguous cross-page order;
after exact JSON save/reopen, two collated copies plan as B,A,C,B,A,C. Existing
oracles separately prove uncollated A,A,B,B,C,C behavior.

Every source page must have one explicit rule. Extra input pages fail with
`unaccountedSourcePage`; absent required pages fail with `missingSourcePage`;
and explicitly skipped customs/instruction pages remain in the plan with page
number and reason rather than disappearing. Invalid edits leave the draft
unchanged, and revision overflow fails.

## Artifacts

- `Packages/LabelCore/Sources/LabelCore/WorkflowProfileDraft.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/WorkflowProfileDraftTests.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/ExtractionPlanTests.swift`

## Limitations / next action

This closes M4-AC03 and M4-AC05 at automated level and adds only partial
M4-AC06 evidence. It does not provide a rendered editor, keyboard interaction,
source-document picker, exact-preview presentation, or save/reload interaction
on the installed application path. The next slice should wrap this state in
reusable native editor components and connect preview generation to
`QuartzPlannedExtraction` without accepting preview pixels as print input.
