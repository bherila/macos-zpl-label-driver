# Evidence — M4 portable extraction planner

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `306bb32`
- Related requirement and acceptance IDs: F11, F12, M4-AC01, M4-AC02,
  M4-AC03, M4-AC04, M4-AC05, M4-AC13
- Evidence level: A
- Status: PASS (partial milestone evidence)
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: portable LabelCore planner only
- Printer/transport/stock: typed nominal 4x6 output stock; no printer or
  transport was accessed
- Fixture/profile revision: synthetic in-memory Letter/A4/rotated page boxes
  and immutable schema-1 workflow profiles
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

```sh
swift test --package-path Packages/LabelCore
python3 scripts/run-accelerator-checks.py
```

## Expected and observed results

All 104 LabelCore tests passed. The complete accelerator also passed 56 Python
tests, fixture integrity for 19 PDFs / 29 pages and three HTML files, 132
independent graphics round trips, 15 backend ABI cases, ten filter ABI cases,
and one inert pipeline case.

The six new planner regressions prove that input sheet size and output stock are
separate records; normalized regions use the existing origin/rotation transform;
only uniform fit is available; explicit global output order feeds the existing
collated/uncollated planner; every source page needs an exact rule; explicit
non-label skips remain visible in the plan; Letter/A4 changes, missing pages,
unsafe identifiers, duplicate region IDs/orders, invalid copy policies, and
output-count overflow fail before a render or delivery exists.

## Artifacts

- `Packages/LabelCore/Sources/LabelCore/ExtractionPlan.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/ExtractionPlanTests.swift`

## Limitations / next action

This is the M4.1 portable foundation, not completion of any M4 acceptance row.
It does not yet provide stable JSON import/export, structural anchors, concrete
native/Letter/A4 reference profiles, original-PDF region rendering, exact
preview integration, template detection, a teach-once UI, queue binding,
browser evidence, or physical output. M4.2 should add deterministic reference
workflow definitions and layout-mismatch validators using committed fixtures.

## Reference-workflow follow-up

Commit `4977e67` adds the named `native-4x6`, `letter-to-4x6`, and
`a4-to-4x6` definitions. All bind `gc420d-4x6-precut` stock while retaining
101.6 mm, 215.9 mm, and 210 mm input widths respectively. Native 4x6 has one
qualified full-page region. Letter and A4 intentionally return the stable
`requiresTeachOnce` error and cannot produce a guessed crop. Four focused
regressions and the resulting 108-test LabelCore suite pass. This strengthens
partial M4-AC01/M4-AC04/M4-AC13 evidence but remains short of those complete
acceptance rows because saved profiles, structural validators, import, and the
native render/preview path have not yet landed.
