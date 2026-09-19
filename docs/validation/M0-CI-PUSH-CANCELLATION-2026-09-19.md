# CI no longer cancels its own `main` pushes — 2026-09-19

Level C (repository/configuration). No acceptance ID advances and no evidence level is claimed
for any macOS, GUI, scheduler, hardware or release row.

## The defect, observed rather than theorised

`concurrency.cancel-in-progress` was unconditional, and the group key is
`github.event.pull_request.number || github.ref`. For a push there is no pull-request number, so
the group is the ref and a push to `main` was cancellable on exactly the same terms as a
superseded pull-request run.

That fired on 2026-09-19. Five pull requests (#112, #113, #115, #114, #116) were merged inside ten
minutes against a macOS job that takes roughly eleven. Each push cancelled its predecessor:

| Run | Head | Merge | Outcome |
|---|---|---|---|
| 35425952173 | `3324241` | #112 | cancelled |
| 35425959560 | `f5f5a8f` | #113 | cancelled |
| 35425967696 | `c940d1e` | #115 | **cancelled** |
| 35425980897 | `e180f13` | #114 | cancelled |
| 35426344624 | `19197e3` | #116 | completed, macOS **skipped** |

Run 35425967696 is the one that mattered: `c940d1e` was the first tree containing all three Swift
slices, and it was the only scheduled run that would have compiled them together. The surviving run
at `19197e3` then classified its own diff (`e180f13..19197e3`) as documentation-only and skipped the
macOS job — correctly, by `scripts/ci_scope.py`, since that diff touches no Swift.

So `ci-required` reported success while the merged tree had never been compiled. Every assertion the
gate makes was individually true. Nothing lied; the combination was simply never built, and no check
is responsible for noticing that.

The gap was closed manually by dispatching run 35426395417 against `19197e3`, which forced the macOS
job (`workflow_dispatch` supplies no base SHA, and `ci_scope.classify` fails open to testing on
unparseable input). Result: LabelCore 326 tests and LabelMac 408 tests, debug and release, 0
failures. 408 reconciles against the individually measured 403 for #112 and 400 for #115 over a
shared base, so both slices' tests were present rather than lost in the merge.

## Change

`cancel-in-progress` is now `${{ github.event_name == 'pull_request' }}`. Superseded pull-request
runs are still cancelled, as the CI rules require. A push to `main` queues behind its predecessor
instead of replacing it, because a push carries the merged tree and is the last opportunity to
compile it. `workflow_dispatch` shares the ref group and is likewise no longer cancellable, so a
manual verification run cannot be killed by an unrelated merge landing mid-build.

`check_repo.push_cancellation_errors` rejects any workflow that triggers on `push` while declaring
an unconditional `cancel-in-progress`, so a revert fails preflight rather than silently restoring
the hole. `compatibility.yml` is `workflow_dispatch`-only and is deliberately unaffected: cancelling
a superseded manual run there discards nothing a merge depended on.

## Coverage proven by mutation

`cancel-in-progress: true` was restored in `.github/workflows/ci.yml` and the file byte-restored
afterwards. Against the reintroduced defect: `check_repo.py` exits 1 with
`Workflow cancels superseded pushes`, and `test_ci_does_not_cancel_its_own_main_pushes` fails. After
restoration all 161 tests pass and preflight exits 0.

`test_ci_does_not_cancel_its_own_main_pushes` also asserts the `push:` trigger is present, so
deleting the trigger cannot make the test pass vacuously.

## Validation

Linux x86_64, CPython 3.11, at this commit. All exit 0:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | **161 tests, OK (skipped=2)** — up from 157 |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/evidence_currency.py` | exit 0 |
| `python3 scripts/manifest_audit.py` | 0 stale, 0 absent, 0 untracked |
| `sha256sum -c MANIFEST.sha256` | 356 of 356 OK |
| `python3 scripts/run-accelerator-checks.py` | PASS |
| `git diff --check` | clean |

`.github/workflows/ci.yml` parses under PyYAML with all three jobs intact and
`cancel-in-progress` reading `${{ github.event_name == 'pull_request' }}`.

**NOT RUN:** `swift test --package-path Packages/LabelMac` and `bash scripts/ci-swift.sh` are
macOS-only; no Swift file is touched by this slice. The changed workflow expression itself is
evaluated only by GitHub Actions, so the hosted run on this pull request is its first execution.

## Scope

This slice changes `.github/` and `scripts/`, neither of which `source_is_unchanged` exempts, so it
stales `M2-AC04` and `M2-AC13` again. The re-seal slice is owed against the merged result and must
land after the last non-exempt change in this batch, not before it.
