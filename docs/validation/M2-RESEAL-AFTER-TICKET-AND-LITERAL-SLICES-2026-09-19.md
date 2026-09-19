# Re-seal M2-AC04 and M2-AC13 after the ticket and literal-table slices — 2026-09-19

Level A. **No new claim.** Ninth and tenth instances of the documented sequencing rule. Nothing is
promoted, no checkbox changes state, and no criterion gains evidence it did not already have.

Records bind source `ab41094e66344917665975dd04520aa2de7bcd63`, the tip of `main`. This slice touches
only the paths `source_is_unchanged` exempts, so the binding survives its own squash merge.

## Why they were stale

| Merge | Non-exempt paths |
|---|---|
| #121 `dbf66ff` | `Packages/LabelCore/Tests/…/ExtractionPlanTests.swift`, `Packages/LabelMac/Tests/…/OfflineExtractionWorkerTests.swift` |
| #122 `ab41094` | `ZPLControlEncoder.swift`, `ZPLControlProtocolCoverage.swift`, `FinishingControlQualification.swift`, `ZPLDocumentedControlEncoder.swift`, `FinishingFramedOutput.swift`, and two test files |

Worth noting that **#121 was test-only and still staled both records**. `source_is_unchanged` is
repository-wide: a test file is a source path, so adding coverage invalidates currency exactly as
changing an implementation does. That is the rule working as designed, not an over-reaction — the
ledger declines to vouch for a tree it has not seen, whatever changed in it.

## A rebind, not a re-verification

All **29** cited implementation and evidence paths across the two records were re-hashed at
`ab41094`: **29 of 29 match**. (The count rose from 27 because #120 added its own validation document
to each record.) Neither merge touched a cited path — #122 changed `ZPLControlEncoder.swift` while
M2-AC13 cites `ZPLGraphicEncoder.swift`, a different file, and #121 touched only test files neither
record cites. `sourceSHA` is the only field that moved.

The distinction is recorded rather than assumed because a re-seal that quietly re-hashed a *changed*
implementation file would be promoting a new claim under an old one.

## `--gate-stale` — recommendation: keep it off for the required check

`evidence_currency.py --gate-stale` exits 0 on this tree, so the prerequisite recorded in
`docs/TRACEABILITY.md` is met for the second time. The recommendation is nonetheless **not to enable
it on `push`**, and the reason is a principle rather than a preference:

A required per-PR check should answer *"is this change safe to merge?"*. Staleness is not a property
of the change — it is a property of the repository's bookkeeping at that instant, created by the
sequencing rule itself. The author of a source slice cannot avoid staling records; the rule says they
must not re-seal in the same commit. Gating on it would fail PRs for a condition their authors are
forbidden from fixing, and would make a red `main` the normal state during ordinary work: ten merges
today each produced that window, some of them hours long. A gate that is red as a matter of routine
teaches reviewers to ignore it, which costs more than it protects.

What the gate is genuinely good for is catching a record that goes stale and *stays* stale — a
forgotten re-seal. That is a periodic question, not a per-commit one, and a scheduled non-required
run answers it without blocking anyone. Recommend keeping `--gate-stale` off the required path and
revisiting only if a re-seal is ever actually forgotten. It has not been: instances one through ten
were each predicted in the source PR and then closed.

## Validation

Linux x86_64, Swift 6.1.3, CPython 3.11. All exit 0:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | 161 tests, OK (skipped=2) |
| `swift test --package-path Packages/LabelCore` | 329 tests, 0 failures |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/evidence_currency.py` | exit 0, both rows `qualified` |
| `python3 scripts/evidence_currency.py --gate-stale` | exit 0 — no stale record remains |
| `python3 scripts/manifest_audit.py` | 0 stale, 0 absent, 0 untracked |
| `sha256sum -c MANIFEST.sha256` | 356 of 356 OK |
| `python3 scripts/run-accelerator-checks.py` | PASS |
| `git diff --check` | clean |

Hosted `macos-26` at the bound commit's inputs: LabelCore 328 and LabelMac 415 on #122, LabelCore 327
and LabelMac 417 on #121, debug and release, 0 failures.

**NOT RUN:** `swift test --package-path Packages/LabelMac` and `bash scripts/ci-swift.sh` are
macOS-only. No Swift file is touched by this slice.

## Scope and what is still owed

PR #123 (USB identity qualification) is **open and deliberately held for maintainer review**. It is
green with a clean Codex security review, but it moves queue installation from structurally
impossible to possible, which is a maintainer decision rather than a code-correctness one. Merging it
will stale these two records again and owe an eleventh re-seal. That is expected and costs nothing
here.

Unchanged: the eleven checked rows carrying no ledger record at all, including the level-I `M2-AC12`,
are still reported and still uncorrected. GUI, installed scheduler, administrator, USB, printer,
physical output and every release gate remain NOT RUN.
