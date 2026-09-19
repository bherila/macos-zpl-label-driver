# Re-seal M2-AC04 and M2-AC13 after the editor and CI slices — 2026-09-19

Level A. **No new claim.** Both criteria were already passing and digest-valid; this rebinds them to
the current source tree after five non-exempt merges staled them. Nothing is promoted, no checkbox
changes state, and no criterion gains evidence it did not already have.

Records bind source `201ab1cd93b6e32f02f14e516268c86b6931c534`, the tip of `main`. This slice touches
only the paths `source_is_unchanged` exempts — `docs/ACCEPTANCE-EVIDENCE.json`, `docs/PROGRESS.json`,
`docs/HANDOFF.md`, `docs/validation/*.md`, a milestone `ACCEPTANCE.md` and `MANIFEST.sha256` — so the
binding survives its own squash merge.

## Why they were stale

The seventh and eighth instances of the documented sequencing rule: evidence follows source, in its
own slice against the merged result. Five merges since the last re-seal changed non-exempt paths.

| Merge | Non-exempt paths touched |
|---|---|
| #111 `c3bbc5c` | `.github/workflows/ci.yml` |
| #112 `3324241`, #113 `f5f5a8f`, #115 `c940d1e` | `Packages/` |
| #114 `e180f13` | `scripts/`, `.github/workflows/ci.yml` |
| #117 `df0dc17` | `.github/workflows/ci.yml`, `scripts/` |
| #118 `201ab1c` | `Packages/`, `scripts/` |

Measured on `main` at `201ab1c` before this slice, both rows read
`checked, digest-valid, NOT current, at the prescribed level` — verdict `stale-source`. Neither was
ever digest-invalid or below its level; only currency lapsed.

## This is a rebind, not a re-verification

All 27 cited implementation and evidence paths across the two records were re-hashed against the
working tree at `201ab1c`: **27 of 27 match**. None of the five merges touched any cited path. #117
changed `scripts/check_repo.py` and `scripts/tests/test_preflight.py`; M2-AC13 cites
`scripts/check_reference_target.py`, `scripts/tests/test_reference_target.py`, `scripts/zpl_oracle.py`,
`scripts/tests/test_zpl_oracle.py` and `scripts/run-accelerator-checks.py` — disjoint. #118 changed
`Packages/LabelMac/`; both records cite `Packages/LabelCore/` only.

So the underlying evidence is undisturbed and `sourceSHA` is the only field that needed to move. That
is stated plainly because a re-seal that quietly re-hashed a changed implementation file would be
promoting a new claim under an old one.

The cited LabelCore suites were nevertheless re-run rather than assumed: 326 tests, 0 failures, debug
and release, locally and on hosted `macos-26`.

## Validation

Linux x86_64, Swift 6.1.3, CPython 3.11, at this commit. All exit 0:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | 161 tests, OK (skipped=2) |
| `swift test --package-path Packages/LabelCore` | 326 tests, 0 failures |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/evidence_currency.py` | exit 0, both rows `qualified` |
| `python3 scripts/evidence_currency.py --gate-stale` | exit 0 — no stale record remains |
| `python3 scripts/manifest_audit.py` | 0 stale, 0 absent, 0 untracked |
| `sha256sum -c MANIFEST.sha256` | 356 of 356 OK |
| `python3 scripts/run-accelerator-checks.py` | PASS |
| `git diff --check` | clean |

`--gate-stale` exiting 0 is the condition the handoff recorded as the prerequisite for enabling that
gate in CI. It is met on this tree. Enabling it remains a separate maintainer decision recorded in
`docs/TRACEABILITY.md`, and this slice does not change the workflow.

**NOT RUN:** `swift test --package-path Packages/LabelMac` and `bash scripts/ci-swift.sh` are
macOS-only. No Swift file is touched by this slice, so no Swift behaviour can be affected by it.

## Scope

M2-AC11 (level H, physical image quality) and M2-AC12 (level I, performance baseline) are untouched
and remain as they were; this slice re-binds two level-A rows and nothing else. macOS integration,
GUI, installation, the scheduler, signing, USB, physical output and every release gate remain
NOT RUN. The eleven checked rows carrying no ledger record at all, including the level-I `M2-AC12`,
are still reported and still uncorrected — that remains a maintainer call.
