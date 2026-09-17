# Read-only acceptance traceability tooling — 2026-09-17

Partial M6-AC01 implementation. The report joins all 90 acceptance IDs and 21 requirements
from existing metadata/checklists with explicit per-ID source-bound evidence assessments.
The new ledger intentionally starts empty; generic milestone prose never becomes pass.
Exact evidence level, file/reference integrity, complete checkbox, candidate equivalence
and clean workspace are independently required. Current failure/block at any level vetoes
readiness. Source ancestry may preserve evidence-only descendants, never changed build
inputs/requirements or unrelated histories. Hashes check reference integrity, not the
truth of a physical or GUI declaration. The only positive result is readyForMaintainerReview;
there is no releaseQualified flag or publication action.

Descriptor-relative no-follow bounded reads cover metadata, tables and references; FIFO,
symlinks, hardlinks, duplicate JSON keys/assessments and traversal fail closed. Budgets and
finite Git/deadline checks are documented in ../TRACEABILITY.md. Preflight validates this
new target/ledger, and the native CI sequence invokes the real source-bound CLI.

Nearest independent constraints: evidence levels cannot substitute for prescribed proof,
current failure cannot be hidden by another pass, and later evidence must not hide changed
build inputs. 14 focused cases passed, including a real synthetic two-commit Git candidate/
evidence history followed by changed code; source, evidence, checkbox, corruption/path/
resource/staleness/dirty and no-release assertions. Removing level matching, current-failure
veto or changed-source rejection independently failed exit 1. Restored 14 cases passed
exit 0; full Python 103 cases passed exit 0. Actual report maps 90 IDs / 21 requirements and
correctly readyForMaintainerReview=false with no invented per-ID pass.
Restored report SHA256
6e793cc3450e06633d40477789d6fcedd4ae384bf15df5136812be6d7a1c8db1.
Logs /tmp/zpl-traceability-level-fault.log, /tmp/zpl-traceability-failure-fault.log,
/tmp/zpl-traceability-source-fault.log, /tmp/zpl-traceability-restored.log,
/tmp/zpl-traceability-python-suite.log. Finite 900-second full gate session24242 completed FULL_GATE_EXIT 0:
103 Python / 272 Core / 324 native tests in debug/release, 132 strict and 180 ASCII
oracle round trips per mode, finite benchmark and inert ABI/pipeline checks, ARM/minimum26
metadata, nested local ad-hoc signatures, unavailable Developer-ID negative, and packaged
worker synthetic PBM/ZPL equality. Log /tmp/zpl-traceability-full.log; local artifact
artifacts/setup-app.jamhiV. No printer accessed. Source checkpoint pending.

M6-AC01 remains open: deliberate implementation/evidence backfill for every mandatory
criterion, independent semantic review, scope/support matrices and actual prescribed
manual/hardware/release evidence are incomplete. M6 runtime/hardware/release gates stay
unqualified. Frozen B unchanged. No administrator/printer/merge/binary publication action.
