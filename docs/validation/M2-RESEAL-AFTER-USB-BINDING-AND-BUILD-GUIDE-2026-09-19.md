# Re-seal M2-AC04 and M2-AC13 after the USB observation, binding-regression and build-guide slices — 2026-09-19

Level A. **No new claim.** Thirteenth and fourteenth instances of the documented sequencing rule. Covers the
merged half of issue #134: #127, #137 and #138. Records bind source `9aa0a210ed40d0dd53d7c2a1e2af6b38f10e388f`, the tip of `main`.

## Why they were stale

| Merge | Non-exempt paths |
|---|---|
| #127 `286b212` | `README.md`, `AGENTS.md`, `CLAUDE.md`, `scripts/usb_identity_probe.py` and its tests, `docs/hardware/GC420D.md`, `docs/REFERENCES.md`, one LabelMac test file (a comment) |
| #137 `9fe4d48` | `Packages/LabelMac/Tests/LabelMacTests/WorkflowEditorTests.swift` |
| #138 `9aa0a21` | `docs/BUILDING.md`, `README.md`, `AGENTS.md`, `CONTRIBUTING.md` |

Most of #127 and all of #138 is documentation, and it staled the records all the same: `README.md`, `AGENTS.md` and
`docs/hardware/` are source paths as far as `source_is_unchanged` is concerned. Only evidence metadata,
`docs/validation/*.md`, a milestone `ACCEPTANCE.md` and a truthful manifest are exempt.

## A rebind, not a re-verification

All **33** implementation and evidence paths cited before this slice were re-hashed at the bound
commit: **33 of 33 match**, so `sourceSHA` is the only field that moved. The count rose from 31 because
#126 added its own validation document to each record.

One cited path does appear in `git diff` between the previously bound commit and this one —
`docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md` — and it is worth saying why that is not
a changed citation: that document was *added* by #126 after the previous bound commit, so it is in the
range as an addition. Its recorded digest still matches, which is the test that matters; it has not been
modified since it was cited. None of #127, #137 or #138 touched any cited implementation or test file: both
records cite `Packages/LabelCore` and a disjoint set of `scripts/` files.

#138 was landed *before* this re-seal on purpose. A build guide under `docs/` is a source path, so
merging it afterwards would have staled this record within minutes; a first draft of this re-seal, bound to
`9fe4d48`, was set aside uncommitted for exactly that reason and redone here against the later tip.

## The evidence lists had reached the ledger's cap, and the procedure changed

`scripts/traceability_report.py` bounds each record's `implementation` and `evidence` list at 16 entries.
Every re-seal so far, this author's and the one before them, **appended** its own receipt to both records.
`M2-AC13` holds 12 entries of real evidence; this would have been its fifth receipt and its 17th entry, and
preflight refused it with `Invalid reference lists`. The pattern was always going to end here.

From this re-seal on, a record cites **only the latest receipt**, and that receipt names the chain:

- `docs/validation/M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md`
- this document

The cap was not raised. It is a deliberate bound on untrusted input, raising it would only postpone the
same failure, and doing so is a `scripts/` change that would itself stale the ledger.

This removes four citations from each record, so it is stated plainly rather than done quietly: **no
evidence of either criterion is removed or weakened.** A re-seal receipt does not show that a criterion
holds; it records that a rebind happened and why it was safe. The evidence is the tests, the oracle and the
original validation documents — 12 entries for `M2-AC13` and 3 for `M2-AC04` — and every one is untouched
and still digest-valid. The four earlier receipts stay in the repository, covered by `MANIFEST.sha256`, and
remain auditable by name from here.

## Why this was not held for PR #123

Issue #134 anticipated one re-seal covering #127 and #123 together. #123 is held for a reattachment check
that needs a person at the printer (#128), and the printer is not currently accessible. A stale `main`
should not wait indefinitely on a held pull request, so this re-seal covers the three that have merged. Merging #123
later will stale the records once more and owe one further re-seal; #134 stays open for that.

## Validation

macOS 27.0, CPython 3. Exit status taken from each command itself, never from a pipeline:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | 180 tests, OK |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/evidence_currency.py` | exit 0, both rows `qualified` |
| `python3 scripts/evidence_currency.py --gate-stale` | exit 0 — no stale record remains |
| `manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| `git diff --check` | clean |

Currency was verified **after committing**, and **in a clean throwaway clone** of the committed branch, not
in the working checkout. The checker decides dirtiness with `git status --porcelain`, which counts
*untracked* files, and the maintainer's checkout holds untracked personal files, so in that checkout both
rows read `stale-source` under `WORKSPACE-DIRTY` however correct the commit is. That is a defensible
fail-closed choice rather than a defect — SwiftPM would compile an untracked `.swift` file — but it means
the two currency rows above are reproducible only from a clean checkout, as CI's is.

**NOT RUN:** the Swift suites locally. No Swift file is touched by this slice; hosted `macos-26` ran both
suites green on #127 and #137 at the commits merged; #138 is documentation only and the scope classifier
legitimately skipped the macOS job, which `ci-required` asserts rather than trusts.

## Scope

Touches only paths `source_is_unchanged` exempts, so the binding survives its own squash merge.

Unchanged: the eleven checked rows carrying no ledger record at all, including the level-I `M2-AC12`
(#130). GUI, installed scheduler, administrator, USB transport, physical output and every release gate
remain NOT RUN. The read-only USB identity observation in #127 advanced no acceptance ID and is not cited
by either record here.
