# M4 draft output-stock mutation — 2026-09-17

Evaluated source: `4f6fbd9b0471cbfc8b730cb01f68e6fb8ee011b7`, local and unpublished.

## Requirement and independent constraint
M4 stock editing must change the destination while retaining original source-sheet geometry and extraction rules. `WorkflowProfileDraft.setOutputStock(id:size:)` constructs a validated replacement before assignment, preserving profile ID, candidate revision, monochrome conversion and all page rules. It does not advance revisions, mutate a saved profile, change device settings or grant physical stock qualification.

The regression exercises a different stock with three source pages, an explicit customs-form skip, reordered regions, collated copies and a correction revision. Canonical roundtrip, source rectangles, skips, copied ordering and original immutable stock remain unchanged; every planned label binds the new destination. Invalid stock identifier admission leaves the draft unchanged. This new API has no prior implementation; no before-fix behavior assertion run is claimed.

## Actual validation
- Release Core suite: 304 tests, zero failures, own exit 0; `/tmp/zpl-stock-draft-final-core-release.log`.
- Final accelerator: 106 Python tests, 304 debug Core tests, 132 strict oracle cases, 180 compression cases, 2 lab privacy cases, 12 CLI cases, 15 CUPS ABI cases, 14 filter ABI cases and 1 inert discard case; own exit 0; `/tmp/zpl-stock-draft-final-accelerator.log`.
- Before accelerator: passed with 303 existing Core tests; `/tmp/zpl-stock-draft-before.log`.
- Initial release run failed compilation from an unqualified test-only CopyPolicy name. Corrected to LabelOrderPlan.CopyPolicy before the final successful runs. This is not behavioral regression evidence.
- Diff whitespace check: exit 0.

Full native CI, GUI/VoiceOver, signing/packaging, Linux, scheduler/administrator and physical printing: NOT RUN for this slice. Previous full native baseline remains source-bound to d41f091; the later publication-redaction focused evidence is separately bound to a5ee0f7.

## Remaining implementation
This is a portable draft API, not completed native stock editing or M4-AC01 acceptance. Native editor retains a fixed rendering canvas and saved-workflow bootstrap accepts only the configured 4×6 stock. Next implement explicit stock rendering context retaining resolution/resource limits, coherent supported-stock admission, preview cancellation and review invalidation, while preserving original source-sheet rules and immutable revisions. Do not silently remove stock qualification boundaries or relax resource limits.

No ledger refresh, printer commands, privilege, queue mutation, merge or publication. Frozen Part B candidate and existing finite zero-physical consent are unchanged.

## File SHA256
- `Packages/LabelCore/Sources/LabelCore/WorkflowProfileDraft.swift`: `fad0bc7660ed3c4653f829526bd7f3d8ed6575483f5e894fca8c34e0c73e1bfc`
- `Packages/LabelCore/Tests/LabelCoreTests/WorkflowProfileDraftTests.swift`: `56cbd9fba2472cf6b336561d33121d9712bf898e8247d49b66d674034ae24813`
