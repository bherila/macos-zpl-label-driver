# Re-seal M2-AC04 and M2-AC13 after the manifest scope slice — 2026-09-19

Level A. **No new claim.** Eleventh and twelfth instances of the documented sequencing rule.
Records bind source `87cbd247161f30b51a05c59047a4bd4fbd4690b4`, the tip of `main`.

## Why they were stale

#125 changed `.github/workflows/ci.yml`, `scripts/check_repo.py` and added
`scripts/refresh_manifest.py` — none of them exempt. The manifest backfill itself is exempt, so the
164 added entries invalidated nothing; only the workflow and script changes did.

## A rebind, not a re-verification

All **31** cited paths across the two records were re-hashed at `87cbd24`: **31 of 31 match**.
(The count rose from 29 because #124 added its own validation document to each record.) #125 touched
no cited path — it changed `scripts/check_repo.py`, while `M2-AC13` cites
`scripts/check_reference_target.py`, `scripts/zpl_oracle.py`, `scripts/tests/test_zpl_oracle.py`,
`scripts/tests/test_reference_target.py` and `scripts/run-accelerator-checks.py`. `sourceSHA` is the
only field that moved.

## First re-seal under whole-tree enforcement

This is the first evidence slice written since `--enforce-covered --enforce-coverage` went live, so
it is also the first real test of the workflow #125 imposes. Recorded because the answer is the whole
argument for having shipped the helper with the gate rather than after it:

The slice adds one validation document and edits four manifest-covered files. Under the old regime
that meant hand-hashing five paths and hoping none was missed. Here it was
`git add -A && python3 scripts/refresh_manifest.py --backfill`, which reported exactly what it
changed, and both gates then exited 0 on the first attempt. The tax is real but it is one command,
and the command tells you what it did.

One sharp edge confirmed in practice, already documented in `CONTRIBUTING.md`: `--backfill` reads the
git index, not the working tree, so a new file must be staged before the refresh can see it. An
unstaged validation document is silently not covered, and the coverage gate then fails the build
rather than the refresh — which is the right order, but only obvious once.

## Validation

Linux x86_64, Swift 6.1.3, CPython 3.11. All exit 0:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | 168 tests, OK (skipped=2) |
| `swift test --package-path Packages/LabelCore` | 329 tests, 0 failures |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/evidence_currency.py` | exit 0, both rows `qualified` |
| `python3 scripts/evidence_currency.py --gate-stale` | exit 0 — no stale record remains |
| `manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| `sha256sum -c MANIFEST.sha256` | 522 of 522 OK |
| `python3 scripts/run-accelerator-checks.py` | PASS |
| `git diff --check` | clean |

**NOT RUN:** LabelMac suites and `ci-swift.sh` are macOS-only. No Swift file is touched by this slice.

## Scope

Touches only paths `source_is_unchanged` exempts, so the binding survives its own squash merge.

PR #123 (USB identity qualification) remains open and held for maintainer review; merging it will
stale these records again and owe a thirteenth re-seal. The eleven checked rows carrying no ledger
record at all, including the level-I `M2-AC12`, are still reported and still uncorrected. GUI,
installed scheduler, administrator, USB, printer, physical output and every release gate remain
NOT RUN.
