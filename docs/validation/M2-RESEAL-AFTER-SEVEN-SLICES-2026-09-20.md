# Re-seal M2-AC04 and M2-AC13 after seven merged slices — 2026-09-20

Level A. **No new claim.** Fifteenth and sixteenth instances of the documented sequencing rule, and the
first to follow the receipt-replacement rule that #140 wrote into `AGENTS.md`. Records bind source `1471eda37aa4f03415a8f89097bd362464efcc84`, the tip of `main`.

## Why they were stale

Seven pull requests merged between the previously bound `9aa0a21` and this one. Each touched at least one
path `source_is_unchanged` treats as source, so each staled both records on its own.

| Merge | Non-exempt paths |
|---|---|
| #140 `5057a1f` | `AGENTS.md` |
| #142 `a3f64c0` | `docs/hardware/GC420D.md` |
| #141 `96995e3` | `OfflineConversion.swift`, `OfflineConversionTicketErrorSurfaceTests.swift`, `OfflineExtractionWorkerTests.swift` |
| #144 `ab8115c` | `docs/adr/0005-queue-installation-transaction.md` |
| #143 `8f0c883` | `.github/workflows/evidence-staleness.yml` |
| #123 `b8d0883` | 9 files across `LabelCore`, `LabelMac` and `LabelSetupApp` |
| #145 `1471eda` | 9 files across `LabelCore` and `LabelMac` |

Four of the seven are documentation, a repository instruction file, an ADR or a workflow, and they staled
the records exactly as the Swift changes did. That is the rule working, not misfiring: `AGENTS.md`,
`docs/adr/`, `docs/hardware/` and `.github/` are source, and only evidence metadata,
`docs/validation/*.md`, a milestone `ACCEPTANCE.md` and a truthful manifest are exempt.

This is the batching `AGENTS.md` asks for. Seven separate re-seals would have been seven slices doing one
slice's work, and each would have staled on the next merge before anyone read it.

## A rebind, not a re-verification

Both records cited **27** implementation and evidence paths before this slice. Two of them are the
superseded receipt, replaced below; the other **25 were re-hashed at the bound commit and 25 of 25 match**.
No cited path was touched by any of the seven merges, so apart from that one replacement `sourceSHA` is the
only field that moves on either record.

The count fell from 33 to 27 at the previous re-seal, when four superseded receipts were dropped from each
record under the rule this document now follows. It is unchanged by anything here.

## Receipt replacement, in practice for the first time

`M2-AC04` and `M2-AC13` each cited `docs/validation/M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19.md`.
That citation is **replaced** by this document rather than joined by it. `M2-AC13` holds 13 evidence
entries; appending would have made 14 and the one after that 15, and the 16-entry cap would have expired
the record in two more re-seals for reasons having nothing to do with whether the criterion holds.

The chain stays auditable by name. Each receipt names its predecessors, so this one continues:

- `docs/validation/M2-RESEAL-AFTER-REPORT-DEADLINE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-EDITOR-AND-CI-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-TICKET-AND-LITERAL-SLICES-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-MANIFEST-SCOPE-2026-09-19.md`
- `docs/validation/M2-RESEAL-AFTER-USB-BINDING-AND-BUILD-GUIDE-2026-09-19.md`
- this document

**No evidence of either criterion is removed or weakened.** A re-seal receipt records that a rebind
happened and why it was safe; it says nothing about whether the criterion holds. The evidence is the
tests, the oracle and the original validation documents — 12 real entries for `M2-AC13` and 3 for
`M2-AC04` — and every one is untouched and still digest-valid. The superseded receipt stays in the
repository, covered by `MANIFEST.sha256`.

## What issue #134 asked for, and what happened

#134 anticipated one re-seal covering #127 and #123 together. #123 was held for the reattachment check in
#128 and merged later, so the 2026-09-19 receipt covered only the three that had merged and #134 stayed
open for this one. #123 is now covered here, along with six slices #134 did not anticipate. #134 can
close.

## Validation

macOS 27.0 (26A428), arm64, Swift 6.4, CPython 3. Exit status taken from each command itself, never from a
pipeline:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | 180 tests, OK |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/evidence_currency.py` | exit 0 |
| `python3 scripts/evidence_currency.py --gate-stale` | exit 0 — no stale record remains |
| `python3 scripts/manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| `git diff --check` | clean |

Currency was verified **after committing**, in a clean throwaway clone of the committed branch rather than
in the working checkout. `evidence_currency.py` decides dirtiness with `git status --porcelain`, which
counts untracked files, and this checkout holds untracked personal files, so in it every row reads
`stale-source` under `WORKSPACE-DIRTY` however correct the commit is. That is fail-closed and defensible —
SwiftPM would compile an untracked `.swift` file — but it means those rows are reproducible only from a
clean checkout, as CI's is.

**NOT RUN:** the Swift suites, in this slice. No Swift file is touched by it. The executed Swift evidence
for the bound commit is the hosted `macos-26` run recorded in
`docs/validation/M3-HOSTED-MACOS-CONTROL-COVERAGE-2026-09-20.md`.

## Scope

Touches only paths `source_is_unchanged` exempts, so the binding survives its own squash merge.

Unchanged: the checked rows carrying no ledger record at all, including the level-I `M2-AC12` (#130). GUI,
installed scheduler, administrator, USB transport, physical output and every release gate remain NOT RUN.
The read-only USB identity work in #123 and #145 advanced no acceptance ID and is not cited by either
record here.
