# Evidence ancestry in qualifying CI — 2026-09-17

Partial M6-AC01 tooling integration. Source-bound evidence needs an available evaluated
ancestor and unchanged build/requirement inputs. A missing ancestor is not equivalent.
The repository preflight already fetched full history; native CI and both compatibility
candidate jobs previously used default shallow checkouts. Those three sites now explicitly
fetch history while retaining pinned checkout, read-only tokens, persist-credentials=false,
standard hosted runners and finite existing job timeouts. Intel remains optional/unqualified.

Nearest independent constraint: a qualifying checkout must actually contain the evidence
source ancestor. The new regression creates real synthetic evaluated/evidence commits,
reads all four production checkout settings, clones using each setting and checks candidate
continuity plus report readiness. A separate one-commit clone lacks the ancestor and stays
unready despite valid reference hashes. Existing real-history tests reject changed code and
unrelated/reversed ancestry. Removing fetch-depth only from the Intel compatibility job
failed the named real-checkout regression, exit1. Byte-restored15focused tests and full
104Python tests passed, with each command's own exit0 captured.
Logs /tmp/zpl-traceability-history-fault.log, /tmp/zpl-traceability-history-restored.log
and /tmp/zpl-traceability-history-python.log. python3 scripts/check_repo.py and diffcheck
passed. Finite900s native full gate session76225 completed FULL_GATE_EXIT0:
104Python/272Core/324Mac debug/release,132strict/180ASCII oracle round trips per mode,
finite benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc
signatures, unavailable Developer-ID negative and packaged-worker PBM/ZPL equality.
Log /tmp/zpl-traceability-history-full.log; local artifact artifacts/setup-app.w0DWyo.
No printer accessed. Source checkpoint pending.

Changing workflow/test inputs intentionally invalidates older source assessments. Reassess
unchanged control behavior against the new evaluated source after the full gate; do not
exclude CI files from source-continuity checks or manufacture qualification from missing
history. Evidence-only descendants retain the existing strict reference/source rules.

No installed/system-dialog/physical configuration is qualified. M6 per-ID backfill,
independent semantic review and prescribed integration/H/R evidence remain open. Frozen B
unchanged. No administrator, printer, merge or binary publication action.
