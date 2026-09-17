# Current implementation handoff — 2026-09-17

## Scope and authorization

The active goal is the full system in [EPIC.md](../EPIC.md), completing independent
implementation without inventing manual scheduler, GUI, administrator or physical
printer evidence. No merge or binary publication is authorized. Source changes stay
on the existing branch and PR. No printer I/O is the default. Preserve the frozen
Part B candidate; newer software artifacts are separate checkpoints.

Read the project [agent instructions](../AGENTS.md), [contracts](CONTRACTS.md),
[execution protocol](EXECUTION.md), and four active milestone files before work.
Historical checkpoints are preserved in [HANDOFF-HISTORY-2026-09-17.md](HANDOFF-HISTORY-2026-09-17.md).
Detailed per-slice evidence remains in [PROGRESS.json](PROGRESS.json) and validation files.

## Verified source and checks

- Branch: `codex/m2-ascii-graphic-compression`; open PR81, base
  `codex/m3-control-speed-boundary`. This is stacked unmerged work, not main.
- Published source/remote/PR equality verified at
  `8c2499783c64b218c289fc50d5bb019b42e8ff8c`. Latest published software
  implementation `42a4cae`: inert durable finishing intent/coordinator integration;
  compatibility inventory and two explicit A assessments are also published.
- Latest finite900s `bash scripts/ci-swift.sh`, session76703, completed
  `FULL_GATE_EXIT 0`:104 Python/277 Core/324 native tests in debug/release,
  132 strict and180 ASCII oracle round trips per mode, finite benchmark and inert
  ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc signatures,
  unavailable Developer-ID negative, and packaged-worker PBM/ZPL equality.
  Local artifact: `artifacts/setup-app.gfdEKb`; no printer accessed.
- Restored focused tests passed after independent fault checks. Early lease release
  before status waits failed45assertions. Previous framing faults detected quantity2,
  ordinary cutter-mode substitution and omitted complete-profile binding; delivery
  accounting detected treating zero known accepted bytes as a retryable send attempt.
- Hosted run35236186182 completed success at exact604aef7 (archive store).
  Attempt-store run35238690886 passed at exact385a545. New coordinator/evidence
  run35240005700 passed at exactfc24c3d. CI-history/evidence run35241292200
  passed at exact8c24997. Neither covers the newer offline queue source.
- The two earlier cloud review passes apply to older base/head pairs. No third pass
  was requested, and these passes are not a verdict on subsequent changes.
- Local host evidence is macOS27 ARM; minimum-runtime26 and hosted checks are
  separate. No local compile or signature result proves retail installation policy.

## Implemented software boundaries

Original PDFs feed isolated Quartz rendering. Geometry, PDF boxes/rotation/UserUnit,
extraction/copy order and monochrome conversion are explicit. Packed previews and
canonical graphic encoding share actual bitmap inputs; the independent oracle stays
separate. Resource caps, finite worker budgets and cancellation are enforced.

Ordinary qualified controls cover motor speeds, darkness, tracking, geometry, signed
offsets and thermal method with immutable profile/queue/ticket snapshots and configured
defaults. Native utility drafts save/reopen exact bounded private-store revisions.
This private catalog does not manage installed product queues. Reference GC420d facts
remain constrained:USB, native8dots/mm, direct thermal, tear-off,2/3/4ips model choices;
unit sensing, current settings and identity remain unobserved.

Finishing schema8 storage binds independently qualified mode/accessory/stock and cut
intentions. Private-store plans, ordered raster hashes and original-source preparation
retain complete immutable context and shared validated normal-control bytes. Additional
output facts bind the exact full profile. Bounded framed candidates preserve quantity1
per expanded label, separate delayed-cut files and explicit completion/removal waits.
The delivery tracker preserves uncertainty after every attempted file. The inert
coordinator holds the kernel lease through all files and waits, then releases on scope
exit. Its bytes are discarded and all status is synthetic. Caller-provided simulator
coordination is not accepted device admission. Ordinary schema8 queue/ticket/encoder
admission remains gated.

Read the current finishing evidence in
[framing](validation/M3-FINISHING-OUTPUT-FRAMING-2026-09-17.md),
[delivery accounting](validation/M3-FINISHING-DELIVERY-ACCOUNTING-2026-09-17.md), and
[inert lease execution](validation/M3-INERT-FINISHING-LEASE-2026-09-17.md).

## Published exact-context artifact serialization

FinishingFramedArtifact now serializes exact immutable context plus separate ordered
files/status requirements. Reopen compares canonical bytes against independently supplied
context; it never parses attacker-controlled counts or manufactures replay authority.
Nine restored native focused cases passed; omitting original-source hash failed four
assertions with identical rasters/files. Full finite900s session1032 passed ownexit0 with the checks above;
log /tmp/zpl-finishing-artifact-full.log. Source/disclosure review passed with restored
hash unchanged. Implementation 9a14f80b7efa857f01a98e96a87e79e651501a50 is published;
hosted run35235059609 passed at its exact60257d1 checkpoint.
See [artifact serialization](validation/M3-FINISHING-FRAMED-ARTIFACT-2026-09-17.md).
The consolidated handoff/history and serialization checkpoints are now pushed.
The private finishing archive store below is also published and hosted-tested.

## Published immutable archive store

FinishingArtifactStore now publishes private bounded binary archives using the existing
immutable directory helper. Typed record-format capacity keeps four-record admission
and idempotent full-store readback consistent.38combined focused/restored native cases
passed; JSON-only capacity regression failed four assertions. Full finite900s session57062 passed ownexit0 with the current checks above;
log /tmp/zpl-finishing-store-full.log. Implementation 425e584c673d6316951be5a7e8c24b7791fd88ba is published;
hosted run35236186182 passed at exact604aef7;
see [store evidence](validation/M3-FINISHING-ARTIFACT-STORE-2026-09-17.md).
This does not supply durable delivery lifecycle or post-crash replay authorization.

## Locally validated M6 traceability tooling

The read-only report covers all 90 acceptance IDs / 21 requirements. It preserves exact
prescribed evidence levels, candidate/file bindings and current-failure veto. Explicit
per-ID ledger is empty; milestone prose/checkmarks cannot qualify rows. 14 focused/restored
and 103 Python cases passed with independent level/failure/source faults detected.
Finite full gate session24242 passed own exit0 with 103/272/324 tests and the
checks above; log /tmp/zpl-traceability-full.log. Implementation 947557476c5f4dd52dcd87d8600cd1089de5ada7 committed locally; exact hosted coverage pending; [tool guide](TRACEABILITY.md) and
[evidence](validation/M6-TRACEABILITY-REPORT-2026-09-17.md). No release qualified.

## Local conservative finishing attempt intent

FinishingAttemptStore adds bounded immutable intent tied to the independently revalidated
archive reference/context. Cold reopen preserves uncertainty without any byte callback;
absence is observation only, never retry authorization. All four modes exercise cold reopen,
idempotence, corrupt/context/cancel rejection and uncertain sync. Nine focused cases passed;
missing-intent fault failed exit1 and restored nine cases passed exit0; finite full gate session87410 passed FULL_GATE_EXIT 0 with 103/272/324 tests and
the checks above; log /tmp/zpl-finishing-intent-full.log. Implementation 3c96e68acdeeef4152aa5381f77be6e9dbd3d9c5 committed locally;
source push/remote/PR equality verified at385a545; hosted run35238690886 pending.
See [intent evidence](validation/M3-FINISHING-ATTEMPT-INTENT-2026-09-17.md).
Accepted lifecycle/device binding and sender integration remain open.

## Local inert persisted finishing integration

InertPersistedFinishingDelivery now composes exact archive/context intent with the
existing device lease before first discard, plus an artifact lease across simulator
aliases. Previous intent rejects restart. All four modes exercise no-attempt cancel/stop,
zero-byte attempt, synthetic waits, uncertain sync and lease release. Expanded nine tests
passed; publication/replay faults detected exit1, restored nine cases passed exit0.
Full finite gate session64896 passed FULL_GATE_EXIT 0 with 103/272/324 tests and
the checks above; log /tmp/zpl-persisted-finishing-full.log. Implementation 42a4caec2fb28ce8e752860cf494ddf9c37c6b69 committed locally; source push and hosted
coverage pending. See
[integration evidence](validation/M3-INERT-PERSISTED-FINISHING-2026-09-17.md).
No actual accepted sender/device status or replay authority is introduced.

## Local compatibility inventory refresh

[COMPATIBILITY.md](COMPATIBILITY.md) now records actual hosted26.6.2/25G83 arm64 and
local27.0/26A428 arm64 automation, separate from narrow reported GUI and absent installed/
physical qualification. Runtime, application, transport/accessory and distribution rows
retain exact pending gates; no qualified physical row or broad family/runtime claim.
Preflight/diffcheck passed. See [inventory evidence](validation/M6-COMPATIBILITY-INVENTORY-2026-09-17.md).
Documentation checkpoint 523fa6b committed locally; push pending.
Per-ID assessments and semantic review remain open.

## Explicit per-ID automated assessments

The ledger now records reviewed A-level assessments for M3-AC01 capability truthfulness
and M3-AC04 no implicit persistent mutation. Exact implementation/test/evidence bytes and
evaluated source bind these two declarations. Focused26Core tests passed exit0 and executable
inputs match the previous passing full gate. No integration/H/R criterion is promoted.
See [assessments](validation/M3-PER-ID-AUTOMATED-ASSESSMENTS-2026-09-17.md).
Global qualification remains incomplete and semantic review remains required.

## Local source-history inputs for CI qualification

Native CI and both compatibility candidates now fetch full history, matching the existing
preflight checkout. A real-Git regression enumerates all four settings, rejects a missing
ancestor, and recognizes evidence-only ancestry. Removing Intel candidate history failed
exit1; restored15focused/full104Python cases passed own exit0. Finite native full gate session76225 passed FULL_GATE_EXIT0 with104/272/324 tests and
the checks above; log /tmp/zpl-traceability-history-full.log;
see [history evidence](validation/M6-TRACEABILITY-CI-HISTORY-2026-09-17.md).
Implementation b4eb3bc8ef7bae8a63bd14f021c4502be0b097df committed locally, push/hosted validation pending.
After the passing full gate, M3-AC01/04 implementation/test hashes were checked unchanged
and fresh A records bind this source and new gate evidence. Earlier records remain
historical. Never exempt CI inputs from source binding; integration/H/R stay pending.

## Local offline finishing queue policy

FinishingQueueDefinition binds exact workflow/profile snapshots, stock and explicit whole
mode/schedule selection. Five focused/restored tests passed; snapshot/selection/stock
omissions independently failed exit1. No installed queue, actual reference-digest check or
accepted ticket is produced. Full gate session76703 passed exit0 with104Python/277Core/324Mac
in debug/release and oracle/inert/signature/packaged checks. Local implementation
8493efcbea4420ada22d70002a5d08e2010b5c37; publication pending. See
[queue evidence](validation/M3-FINISHING-QUEUE-DEFINITION-2026-09-17.md).
The canonical codec is now implemented locally; seven focused/restored cases passed and
canonical-byte omission failed two assertions. Full gate session28149 passed exit0 with
104Python/279Core/324Mac debug/release and oracle/inert/signature/packaged checks; see
[codec evidence](validation/M3-FINISHING-QUEUE-CODEC-2026-09-17.md).
Next independent slice: canonical bounded private queue persistence with actual reference
readback, then accepted finishing source/order/pitch/device and durable lifecycle binding.

## Manual Part A and Part B

The maintainer reported issue80 Part A passed with the corrected local editor artifact
on the same macOS27 Mac. This is narrow reported GUI evidence; keyboard/VoiceOver,
minimum-runtime26 and the full GUI matrix remain open. See
[editor layout](validation/M5-EDITOR-LAYOUT-2026-09-17.md).

Part B has no result yet. The separately frozen local candidate is from source52ba93f;
the private pointer `/tmp/zpl-current-m1-candidate-path.txt` identifies its directory.
Do not replace those bytes with newer builds. The maintainer has been given the frozen
script's interactive `--apply` command. Await its output and stop on failure without
retry. The script prompts through OS authentication; agents never collect passwords
or invoke privileged installation.

The approved finite experiment is one discard queue transaction, one held synthetic
single-page PDF/one copy, one release, at most60seconds of observation and guarded
cleanup. Zero physical labels/device commands. No Zebra printer is required.
After successful apply, follow [single-job admission](validation/M1-SINGLE-JOB-ADMISSION.md):
strict final PPD and planned filter-chain checks; exact stopped/rejecting/unshared
`file:///dev/null` queue/default readback; held-job attributes; one resume; correlated
schema2 filter metadata and finite discard completion; then owned-job/queue cleanup.
Missing metadata is inconclusive, not a pass or reason to enable global verbose logging.
Use the fixed verified local scheduler endpoint and controlled client environment.
Recovery and readback details:
[transaction recovery](validation/M1-TRANSACTION-RECOVERY.md),
[IPP readback](validation/M1-READONLY-IPP-READBACK-2026-09-16.md).
Part B alone does not accept the production adapter or complete M1.

## Remaining implementation and evidence

Next independent software work: validate the local intent/coordinator integration,
then accepted-context framed-artifact binding and durable lifecycle/restart recovery; persistent exact-profile output qualifications; accepted finishing
queue/ticket/device and qualified-pitch binding; actual bounded file/status provider
integration retaining ownership throughout waits. These must reuse established
immutable stores and coordination invariants, not manufacture accepted-device authority
from the private utility catalog or flatten finishing files into raw TCP bytes.

Accepted-context gap inspection: VirtualQueueDefinition admits schemas1–6 and profile1–7,
with tear-off defaults; ResolvedJobTicket admits schemas2–7 and independently checks queue/
printer references in its initializer. Finishing profile8 cannot enter either path. The
next admission slice must extend typed queue/defaults and ticket serialization/validation,
then store/load and preparation binding together, with regressions for every reference,
mode/schedule/output-order/source/device/cancellation combination. Preserve ordinary role
rejection until the separate finishing path is complete; M1 privilege/backend identity
still requires its prescribed real scheduler evidence before production assumptions.


Manual M1 must establish actual scheduler fidelity/options, sandbox/helper identity,
backend lifetime and retry behavior before production adapter assumptions. Installed
queue management, privileged authorization/lifecycle, restart repair and system-dialog
visibility remain open. GUI/accessibility and compatibility/release matrices also remain
open. M6 traceability/evidence-integrity tooling is implemented; deliberate per-ID
evidence backfill and semantic review remain open. Empty/blocked evidence cannot
promote local compilation to installation or hardware qualification. M6 is not implemented/accepted simply because local builds pass.

Physical qualification requires separately authorized named hardware and finite label/
command budget. GC420d USB4×6pre-cut tear-off/no cutter is the primary target; retain
separate S2 accessory/model evidence. USB unplug/replug, output quality/count/order,
physical status/faults, actual cross-queue serialization and finishing remain unobserved.
Never promote compiled, inert, reported GUI or hosted checks into printed evidence.
Do not automatically calibrate/reset/save/upgrade firmware/erase or replay ambiguity.
