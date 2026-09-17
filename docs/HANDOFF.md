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
  `3047f7880665e9550efb621fbfad2ceb328fff49`. Latest published software
  implementation `ccd7a9a`: immutable original-PDF acceptance and range/copy ownership.
  Earlier explicit A assessments remain historical; new source needs reassessment.
- Latest completed finite900s `bash scripts/ci-swift.sh`, session46436, completed
  `BASELINE_EXIT 0`:104 Python/281 Core/360 native tests in debug/release,
  132 strict and180 ASCII oracle round trips per mode, finite benchmark and inert
  ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc signatures,
  unavailable Developer-ID negative, and packaged-worker PBM/ZPL equality.
  Local artifact: `artifacts/setup-app.sqj9Kl`; no printer accessed.
  This current-source gate includes the busy-state regression, setup-error redaction
  and both finishing CLI worker-admitted cancellation routes.
- Restored focused tests passed after independent fault checks. Early lease release
  before status waits failed45assertions. Previous framing faults detected quantity2,
  ordinary cutter-mode substitution and omitted complete-profile binding; delivery
  accounting detected treating zero known accepted bytes as a retryable send attempt.
- Hosted run35236186182 completed success at exact604aef7 (archive store).
  Attempt-store run35238690886 passed at exact385a545. New coordinator/evidence
  run35240005700 passed at exactfc24c3d. CI-history/evidence run35241292200
  passed at exact8c24997. Queue run35244168027 passed at exact029ddd5. Geometry run35245718555 passed at exact37775b4. Acceptance run35246781489 completed success
  at exact3047f78; it does not cover local durable storage.
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
104Python/279Core/324Mac debug/release and oracle/inert/signature/packaged checks. Local implementation
a6d90b4a1d9ed8b7eb4e73e42513be2c39f56092; source publication pending. See
[codec evidence](validation/M3-FINISHING-QUEUE-CODEC-2026-09-17.md).
Private finishing queue storage is now locally implemented; five focused/restored cases
passed, including cold recovery of uncertain publication. Snapshot and both digest faults
independently failed exit1. Full gate session41257 passed exit0 with104Python/279Core/329Mac
debug/release and oracle/inert/signature/packaged checks. Local implementation
a6d90b4a1d9ed8b7eb4e73e42513be2c39f56092; source publication pending. See
[store evidence](validation/M3-FINISHING-QUEUE-STORE-2026-09-17.md).
Native-pitch/profile/domain geometry binding is locally implemented; eight focused/restored
cases passed and three independent guard omissions failed exit1. Full gate session56035
passed exit0 with104Python/279Core/332Mac debug/release and oracle/inert/signature/packaged checks; see
[geometry evidence](validation/M3-FINISHING-DEVICE-GEOMETRY-2026-09-17.md).
Original-PDF in-memory acceptance and retained-source preparation are now locally implemented.
Eight Core/ten native focused/restored cases passed; six selection/copy/control/source
omissions independently failed exit1. Full gate session88103 passed exit0 with104Python/281Core/334Mac
debug/release plus oracle/inert/signature/packaged checks. Local implementation
ccd7a9aab1175518fda1a8db783862ed865b1d81; source publication pending. See
[acceptance evidence](validation/M3-ORIGINAL-FINISHING-ACCEPTANCE-2026-09-17.md).
Durable manifest/original-source transaction and complete cold-reconstruction validation are
locally implemented; fourteen focused/restored native cases passed and archive digest/context
omissions independently failed exit1. Full gate session6450 passed exit0 with104Python/281Core/338Mac
debug/release plus oracle/inert/signature/packaged checks; source publication pending. See
[durable acceptance evidence](validation/M3-DURABLE-FINISHING-ACCEPTANCE-2026-09-17.md).
The durable-reference preparation factory is now local; fifteen focused native cases passed,
including actual four-label packed preparation and wrong digest before worker invocation.
Full gate session94514 passed exit0 with104Python/281Core/339Mac debug/release
plus oracle/inert/signature/packaged checks; source publication pending. See [preparation bridge evidence](validation/M3-PREPARED-ACCEPTED-FINISHING-2026-09-17.md).
Accepted identity-bound framing and job-level intent are now local. Seventeen focused
native cases passed including artifact renaming, cold recovery, exact context, uncertain
publication and synthetic success without clearing uncertainty. Two independent guard
omissions failed exit1; exact restored17 cases passed exit0. Full gate session76633 passed exit0:104Python/281Core/341Mac debug/release plus
oracle/inert/signature/packaged checks; see [intent evidence](validation/M3-ACCEPTED-FINISHING-INTENT-2026-09-17.md).
Accepted-job coordinated inert admission is now local: twenty focused native cases passed
exit0, including intent-before-discard, job/device lease competitors during waits, replay
refusal and uncertainty after zero-byte/publication failures. Replay-veto/early-lease
faults failed exit1 through expected assertions; exact restored20 cases passed exit0.
Full gate session32086 passed exit0:104Python/281Core/344Mac debug/release plus
oracle/inert/signature/packaged checks;
see [coordinator evidence](validation/M3-ACCEPTED-FINISHING-COORDINATOR-2026-09-17.md).
Durable accepted-job cancellation requests and a validated bounded monitor are now local;
twenty-three focused/restored native cases passed exit0; three independent authorization/
context/record faults failed exit1. Mandatory polling is now integrated at accepted execution
event boundaries, with twenty-five focused cases passed exit0. Polling omission failed exit1 through expected assertions; exact restored25 cases passed
exit0. Full gate session54742 passed exit0:104Python/281Core/349Mac debug/release plus
oracle/inert/signature/packaged checks. See
[cancellation evidence](validation/M3-ACCEPTED-FINISHING-CANCELLATION-2026-09-17.md).
Cold recovery implementation checkpoint: `7654b787b08ef881887af3f9e5d8b80b362bcbb1` (local, unpublished).
Cold recovery interpretation is now local: twenty-seven focused native cases passed exit0,
including cancellation/intent combinations, synthetic success, corrupt records and finite
operation guards. Intent/cancellation mapping omissions each failed exit1 through expected assertions;
exact restored27 cases passed exit0. Full gate session31620 passed exit0:104Python/281Core/351Mac debug/release plus
oracle/inert/signature/packaged checks. See [recovery evidence](validation/M3-ACCEPTED-FINISHING-RECOVERY-2026-09-17.md).
Offline finishing inspection CLI is now local; focused/restored28 cases passed exit0,
including actual CLI success and digest mismatch with empty stdout. Four independent faults
for uncertainty/hardware/root guard/namespace creation failed expected assertions. Full
gate session70662 passed exit0:104Python/281Core/352Mac debug/release plus
oracle/inert/signature/packaged checks; see
[inspection evidence](validation/M3-FINISHING-INSPECTION-CLI-2026-09-17.md).
Packed accepted preview export implementation `a91cd4d77edb8ff952292c62ebb70dfdc60b475a` is committed locally and unpublished: thirty focused native cases passed exit0,
including exact PBM/manifest equality, no ZPL assets, existing output preservation, byte
budget and staged cleanup. CLI export integration passed31 focused cases exit0, including actual executable success
and repeat-export refusal. Empty existing-directory inode preservation also passed. Pixel/
overwrite/budget faults each failed expected assertions; exact restored31 cases passed
exit0. Full finite900-second Mac gate session53728 passed exit0:104Python/281Core/355Mac debug/release plus oracle/inert/signature/packaged checks; see
[export evidence](validation/M3-PACKED-FINISHING-PREVIEW-EXPORT-2026-09-17.md).
Selected-record lookup is under local validation: shared bounded canonical parser, private existing catalog reads, filename identity and unchanged catalog inode/permissions; initial focused run failed directory-URL trailing-slash equality, corrected to filesystem-path equality; filename omission fault failed expected assertion, restored32 cases passed exit0; full gate32797 failed an existing release source-page-preview result; unchanged four-test release rerun77654 passed, scheduling cause unconfirmed. App integration under focused validation7113. See [selected record evidence](validation/M3-SELECTED-FINISHING-RECORD-2026-09-17.md).
Saved finishing inspection/export model and native controls are wired into the setup app; corrected focused34-case session63707 passed exit0 after an async semaphore test-build correction; request-ownership omission fault failed expected assertion; exact restored34 cases passed exit0; full finite900-second gate14214 passed exit0,104Python/281Core/358Mac debug/release plus oracle/inert/signature/packaged checks. See [app slice evidence](validation/M5-SAVED-FINISHING-INSPECTION-2026-09-17.md).
Four-path stale-completion regression is now integrated and setup initialization errors are redacted. Busy-ownership fault failed the expected assertion; restored three model cases passed debug/release and final app build32129 passed exit0. Final artifact artifacts/setup-app.KxC3wr. Unpublished implementation checkpoint `fb9b34345a234238844f8d0151e54c01d27a29bf`. Next: reproduce and fix the separate CLI cancellation finding. CLI cancellation regression reproduced eight expected assertions across both commands/SIGINT/SIGTERM in55293 (exit65/INPUT_ERROR). Both routes now recognize worker cancellation; corrected two CLI-focused cases per mode47995 passed debug/release exit0, including repeat-export refusal; unpublished implementation `9ae4776ffdc0e26c2b38e64f42d7ddde62e7b845`. Preserve export commitUncertain priority. See [CLI cancellation evidence](validation/M3-FINISHING-CLI-CANCELLATION-2026-09-17.md). Setup initialization now uses a generic local-storage failure message; final affected build passed exit0. No recovery grants replay.
Actual identified unit correspondence remains open.

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

The separate finishing path now has typed queue definitions and immutable stores,
original-PDF acceptance, qualified device geometry, preparation, accepted-context
framing, durable attempt intent and cancellation, inert coordination, restart
observation, inspection, and exact packed-preview export. Ordinary queue/ticket
schemas still reject finishing profiles by design; the separate finishing route
must not be flattened into the ordinary raw delivery path. See the current
[software assessment](validation/M0-M2-CURRENT-SOFTWARE-ASSESSMENT-2026-09-17.md)
and the finishing evidence linked above. These components establish software and
inert behavior, not installed scheduler or physical device authority.

Copy-order audit at the unchanged source checkpoint: 23 focused portable tests
passed (ordering, both extraction planner entry points, prepared encoder/payload).
Assertions cover collated and uncollated order, source selection before copies,
upstream-expanded duplicates, and exact output count/order. Ordinary prepared
formats do not emit quantity commands; finishing framing emits quantity one per
already ordered raster. M2-AC08 remains unaccepted because real M1 scheduler
ownership has not been observed. Next work is a deliberate audit of the remaining
software criteria and integration gaps, rather than rebuilding these components.


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

## Current software acceptance baseline

Current-source CLI signature run88261 passed exit0; private local copies are in
artifacts/local-adhoc.T0kngf. Full finite900-second baseline46436 evaluates clean source
2f1f0e6061885274824e0895fcc6dbe14dea5e48; full baseline passed exit0:104Python/281Core/360Mac debug/release plus independent/inert/
signature/packaged checks; artifact artifacts/setup-app.sqj9Kl. Source stays frozen; metadata-only semantic assessment is recorded in
[current software assessment](validation/M0-M2-CURRENT-SOFTWARE-ASSESSMENT-2026-09-17.md).
No checkbox/ledger pass is inferred from counts. Native GUI automation returned
cgWindowNotFound twice for the local app; no window was observed, so GUI remains NOT RUN.
Seven explicit source-bound assessments are now recorded: M0-AC03/07/08/11, M2-AC07,
M5-AC12 at A; M0-AC04 at I for actual local native build/CGContext smoke only.
Next: validate the clean ledger readback, then continue remaining software gap review. All manual/hardware/release gates remain unchanged.

Current offline performance refresh: [M2-CURRENT-OFFLINE-PERFORMANCE-2026-09-17](validation/M2-CURRENT-OFFLINE-PERFORMANCE-2026-09-17.md), finite six invocations exit0; repeat p95 138.331ms, first515.937ms. Command RSS only; aggregate worker peak not instrumented. No acceptance promotion.

Saved finishing preview export chooser now discloses label content and document hashes and asks for review before sharing, before export consent. Finite300s release setup-app build passed exit0. Actual dialog/VoiceOver NOT RUN. This source change makes earlier exact-source acceptance records historical on this branch; no ledger pass was refreshed by a copy build.

2026-09-17 saved-job chooser non-cancellation failures now invalidate pending work and clear the previous verified selection/export authority with a redacted error; user cancellation preserves selection. Three release model tests passed; omission of selected=nil produced the expected no-export assertion failure, exact restoration passed all three. Release app build passed. Native chooser/error/VoiceOver NOT RUN; no new acceptance or device I/O.

2026-09-17 offline benchmark now bounds each conversion at120s and metadata probes at30s; timeout kills the owned process group, including children holding pipes after parent exit. Four focused tests and full105 Python tests passed exit0; removing group cleanup caused the expected child-survival assertion failure, exact restoration passed. Actual finite six-invocation current signed CLI benchmark passed exit0 with unchanged output. No aggregate memory, scheduler, GUI, printer or new acceptance evidence.

Latest isolated integrated baseline: [M2-M5-ISOLATED-SOFTWARE-BASELINE-2026-09-17.md](validation/M2-M5-ISOLATED-SOFTWARE-BASELINE-2026-09-17.md), terminal exit0:105Python/281Core/360Mac debug/release with independent/inert/signature/packaged checks. Local app artifacts/setup-app.fAUnee; manual gates unchanged. No publication or exact-ID acceptance refresh.

[M5-LOCALIZABLE-APP-MESSAGES-2026-09-17.md](validation/M5-LOCALIZABLE-APP-MESSAGES-2026-09-17.md): 18 stored app messages/dialog strings now use Foundation String(localized:) lookup with unchanged English fallback: saved-job inspection, USB discovery, editor errors, setup storage error and preview export dialog. Release app build and27 focused release model tests passed exit0. No translations, another-language support, actual GUI layout/VoiceOver or acceptance pass claimed.

Current M3 inventory: [M3-CURRENT-CONTROL-MAPPING-2026-09-17.md](validation/M3-CURRENT-CONTROL-MAPPING-2026-09-17.md). The older missing-control audit is historical; motor/darkness/tracking/geometry/offset/thermal/finishing mappings now exist in qualified paths.281Core debug/release passed; production integration and per-ID acceptance remain open.

Worker-memory instrumentation: [M2-WORKER-MEMORY-INSTRUMENTATION-ATTEMPT-2026-09-17.md](validation/M2-WORKER-MEMORY-INSTRUMENTATION-ATTEMPT-2026-09-17.md). Wrapper rejected by required parent-PID supervision, exit65; no memory pass. Next independent route: in-worker bounded scalar telemetry, preserving worker/coordinator identity.

[M2-IN-WORKER-MEMORY-TELEMETRY-2026-09-17.md](validation/M2-IN-WORKER-MEMORY-TELEMETRY-2026-09-17.md): Optional bounded render-worker RSS telemetry now travels through private result validation, CLI JSON and offline benchmark reports without an intermediate process. Unavailable remains nil/null; invalid0/negative/above1TiB values reject before returned payload.41 focused native tests passed debug/release; validation omission fault produced3 expected failures;106Python tests passed. Actual six-run offline measurement succeeded; CLI/worker peaks separate, not simultaneous aggregate memory. Native GUI/scheduler/install/hardware gates unchanged.

Clean committed-source telemetry measurement passed exit0 with default benchmark path; raw evidence docs/validation/M2-IN-WORKER-MEMORY-BASELINE-2026-09-17.json binds CLI and worker hashes. Separate CLI/worker RSS only; no new acceptance claim.

Latest integrated telemetry baseline: [M2-M5-TELEMETRY-INTEGRATED-BASELINE-2026-09-17.md](validation/M2-M5-TELEMETRY-INTEGRATED-BASELINE-2026-09-17.md), terminal exit0:106Python/281Core/361Mac debug/release plus independent/inert/signature/packaged checks. Local app artifacts/setup-app.HZUdFj; no publication or per-ID acceptance refresh. Next: deliberate remaining evidence/integration assessment; do not repeat identical full gate without a new change/failure.

Current M3-AC01 automated assessment: [M3-CAPABILITY-TRUTHFULNESS-ASSESSMENT-2026-09-17.md](validation/M3-CAPABILITY-TRUTHFULNESS-ASSESSMENT-2026-09-17.md), deliberately bound to tested source and16 immutable references. Unknown/absent/unsupported/configuration remain distinct; no physical support claim or other criterion refresh.

Current M3-AC02 A assessment: [M3-SETTINGS-VALIDATION-ASSESSMENT-2026-09-17.md](validation/M3-SETTINGS-VALIDATION-ASSESSMENT-2026-09-17.md), selected-value validation and negative precedence/combination assertions bound to executed baseline and16 immutable references; no installed/hardware acceptance or unrelated refresh.

[M3-DOCUMENTED-WIDTH-SUBSET-2026-09-17.md](validation/M3-DOCUMENTED-WIDTH-SUBSET-2026-09-17.md): Standalone documented print-width encoding now enforces the same2..32000 bounded geometry subset for both requested width and supplied model maximum. Overbroad declarations reject rather than widen the subset. New regression reproduced7 expected failures before the fix;282Core tests passed debug/release afterward;106Python tests, release setup-app build and debug accelerator passed exit0. No hardware/control setting changed. Older exact-source ledger records are historical after this source change; no acceptance refresh.

Unpublished width-subset implementation checkpoint `8dcc24141aaa8dbb6ca6aa27aecba0ba9193267b`; code/regression digests match the tested candidate. Current full baseline remains the preceding source, not this checkpoint.

## Endpoint byte-budget follow-on

[Endpoint validation](validation/M3-ENDPOINT-UTF8-BUDGET-2026-09-17.md) records the reproduced grapheme-count bypass and bounded UTF-8 fix. All 16 TCP tests passed debug/release; 106 Python tests and the release setup-app build passed. This is unpublished local evidence. The preceding full baseline and source-bound acceptance records predate the width and endpoint changes. Manual gates are unchanged.

## Legacy status grammar follow-on

[Function-setting validation](validation/M3-STATUS-FUNCTION-BUDGET-2026-09-17.md) records the eight-bit boundary regression and fix. All 283 Core tests passed debug/release; the debug accelerator and release setup-app build passed. This advances status validation without a complete M3-AC12 assessment. No printer query or physical evidence was added. Next: assess the remaining control/status requirements against current source while preserving the frozen M1 Part B candidate.

## Late TCP callback regression

[Terminal-state ordering](validation/M3-TCP-LATE-CALLBACKS-2026-09-17.md) adds finite adversarial coverage for late callbacks after three admitted-send failures. A queued observer proves all late events were processed before the stored-result/count assertions. This advances automated M3-AC05 coverage without claiming complete network or installed scheduler acceptance. The frozen manual candidate and device-I/O budget remain unchanged.

## Typed extraction region admission

[Shared page-region budget](validation/M4-TYPED-REGION-LIMIT-2026-09-17.md) fixes a typed profile that could be exported but not imported. Model, JSON importer and editor now share the existing 256-region limit; rejection is explicit. All 284 Core and 31 native editor tests passed debug/release; the debug accelerator passed. No manual editor, scheduler or physical gate was promoted. Next: inspect remaining profile/planning requirements and production integration dependencies rather than carry historical acceptance forward.

## Open exact-integer identity defect

[JSON integer investigation](validation/JSON-INTEGER-IDENTITY-INVESTIGATION-2026-09-17.md) reproduced lossy large revision/order reload and Int.max rejection. A tentative string conversion still admitted a large fractional token after Foundation rounded it. Source and tests were restored; no partial fix landed. Next slice is shared exact integer parsing across the enumerated codec sites, preserving geometry and existing wire/error contracts. This is an independent software gap, so the goal is not blocked on hardware.

## Exact integer conversion dependency

[Token conversion validation](validation/EXACT-JSON-INTEGER-TOKENS-2026-09-17.md) records the internal scalar parser and signed-edge/fraction/exponent tests. All 287 Core tests passed debug/release; debug accelerator passed. Product codecs are unchanged and the identity defect is still open. Next is bounded JSON traversal retaining numeric lexemes and integration across all enumerated codec sites, with original round-trip regressions. No Mac GUI/scheduler or physical gates were advanced.

## Token-preserving JSON traversal dependency

[Traversal evidence](validation/TOKEN-PRESERVING-JSON-2026-09-17.md) records the internal bounded object/array parser, numeric lexeme retention and adversarial grammar/resource tests. All 291 Core tests passed debug/release. Product codecs are unchanged: the integer identity defect remains open. Next is integration across the enumerated codec sites with original regressions and explicit compatibility/error-contract checks. Manual gates are unchanged.

Unpublished token-traversal implementation checkpoint: `37977fdb1912ece63784ac4af79b6f31b28062b2`. Codec integration remains the next required slice.

## Exact JSON identity codec integration

[Codec integration evidence](validation/EXACT-JSON-INTEGER-CODECS-2026-09-17.md) repairs the identified manual codec sites together, including private defaults readers and native qualification manifests. All 299 Core and 21 native workflow-store tests passed debug/release; restoring floating integer conversion caused 18 failures across seven codec regressions. Source is restored. Full native CI-equivalent validation is pending; older whole-system baselines are historical. No manual or physical gate changed.

## Current complete software baseline

[Exact JSON integrated baseline](validation/M2-M5-EXACT-JSON-INTEGRATED-BASELINE-2026-09-17.md) evaluated clean unpublished `b12e65a63cfebcce3625a249975e837dbb0bc2ee` with the finite 900-second native CI sequence, exit 0. Passed 106 Python, 299 Core and 364 native tests debug/release, both oracle/ABI modes, ARM/minimum-26 metadata, nested local ad-hoc signatures, fail-closed Developer-ID negative and packaged-worker synthetic PBM/ZPL equality. Local artifact `artifacts/setup-app.ANaCKz` does not replace the frozen manual candidate. Manual/physical/retail-host gates remain open; no ledger acceptance was refreshed. Next: audit remaining independent software requirements against this checkpoint and prepare reviewable source integration without merging or binary publication.

## M3 network automated assessment

[M3-AC05 assessment](validation/M3-NETWORK-CORRECTNESS-ASSESSMENT-2026-09-17.md) now records the exact A-level simulator criterion as passed at unpublished `b12e65a63cfebcce3625a249975e837dbb0bc2ee`, using the full current software baseline and inspected short-write/loopback/terminal-state assertions. Production queue retry/ownership, USB, physical completion and status-channel gates remain open separately. This is not a global M3 completion claim.

## Full-scope gap audit and next implementation

[All 21 mandatory requirements](validation/FULL-SCOPE-GAP-AUDIT-2026-09-17.md) retain explicit completion gaps. The next independent slice is the missing cited control protocol table for tracking, dimensions, offsets and qualified finishing; current source has emitted commands but only five structured metadata rows. Production installer/helper/USB/queue integration remains pending the actual ADR 0003 admission boundary, rather than falsely labeled implemented. Hosted PR81 checks still apply only to published 3047f78. No goal completion/block claim.

## Complete control protocol metadata

[Protocol table evidence](validation/M3-CONTROL-PROTOCOL-TABLE-2026-09-17.md) fills the concrete table gap for all twelve documented kinds and four qualified finishing modes. Explicit range/model-limit fields retain independent bounds and unverified persistence. Offline ^MMC and native ^MMD/~JK are distinguished. Core 301 debug/release and accelerator passed before the final metadata-only cut-row refinement; final two coverage tests passed both modes afterward. Prior full native/ledger evidence is historical after source changes. Next is a current M3-AC03 semantic assessment, without promoting physical state-isolation or production adapter claims.

## Current control coverage assessment

[Source-bound M3-AC03 assessment](validation/M3-CONTROL-COVERAGE-ASSESSMENT-2026-09-17.md) now records an A-level pass at clean local unpublished 2d59771aba5cd27d950fde395bbccaef24fc5d9a. Both Core modes passed 301 tests; both actual native finishing suites passed nine tests. An initial filter matched no tests and was excluded. Mapping includes every documented kind and both offline/native finishing routes; ordinary and finishing print speed remain 2/3/4 even though the standalone qualified tuple supports 2..12. Sixteen immutable implementation/evidence digests bind this assessment. Older ledger records remain historical. Manual/USB/physical/release gates and frozen Part B candidate are unchanged. Next: assess remaining automated privacy/permission requirements and reconcile reviewable unpublished source with PR81; do not merge or publish.

## Bare TCP host admission

[Endpoint delimiter regression](validation/M3-ENDPOINT-URI-COMPONENTS-2026-09-17.md) records local unpublished 8743f7ac65c0217ad795454d303020bb0d051f6f. Six URL-component acceptances were reproduced; the constructor now rejects path/user-info/query/fragment/backslash delimiters while preserving bare DNS/IP/scoped IPv6 and existing encoded-size limits. Eighteen TCP tests passed debug/release; 106 Python tests and preflight passed. No DNS/physical printer operation occurred in the regression; transport tests use loopback only. M3-AC12 remains unchecked pending the full privacy audit and production privileged boundary. Previous whole-source ledger evidence is historical after this code change; no acceptance was refreshed. Next: audit remaining diagnostic and operation-admission paths. Manual gates and frozen candidate are unchanged.

## Worker fractional integer admission

[Private worker admission evidence](validation/M3-WORKER-INTEGER-ADMISSION-2026-09-17.md) records local unpublished 81f41cba1c28402aa3d51b26a5a08221d73ad4e8. Six render-result and four conversion-ticket fractional acceptances were reproduced. Shared token admission now guards all seventeen integer paths across conversion tickets, render results, failure records and layout requests/results, preserving fractional geometry and optional null. Final 26 native tests passed debug/release, including actual renderer/layout children; 106 Python tests and preflight passed. M3-AC12 and privileged integration remain open; other Codable consumers are explicitly outside this assessment. Next: current-source full native baseline, then artifact binding/private-record audit and reviewable source integration. Frozen candidate/manual gates unchanged; no ledger refresh, printer I/O, merge or publication.

## Current worker-admission integrated baseline

[Full native validation receipt](validation/M2-M5-WORKER-ADMISSION-INTEGRATED-BASELINE-2026-09-17.md) evaluated clean local unpublished 4ddffeb40e1866629972f131df1048c26cac75e3; finite 900-second native CI sequence exited 0. Passed 106 Python/301 Core/370 native tests debug/release, independent oracles, inert ABI/discard cases, ARM/minimum-26 metadata, nested ad-hoc signatures and packaged-worker synthetic equality. Local app setup-app.GeEvs8 does not replace the frozen manual candidate. Host/SDK were 27.0, so retail runtime 26 is unqualified. Canonical equality guards already protect archive/scratch record spellings. A 521-file exact tracked-source archive and bounded Linux handoff are ready locally; no worker/result claimed. Next: audit ordinary parent output binding against the extraction bitmap/ZPL oracle and implement a regression-backed shared boundary if needed, then reconcile source into PR81. No ledger refresh, manual/physical pass, merge or publication.

## Shared parent bitmap binding

[Packed preview/ZPL binding evidence](validation/M3-WORKER-BITMAP-BINDING-2026-09-17.md) records local unpublished b424d61cfacc63e6dd74ff3be0c0c7d3b3f910cf. Ordinary parent accepted three byte-count-preserving substitutions before the fix. Shared WorkerBitmapBinding now checks bounded canonical PBM layout/padding and regenerated diagnostic ZPL equality; extraction retains expected-canvas checks and existing errors. Forty-five render/Quartz/CLI cases plus nine qualified-finishing cases passed debug/release; 106 Python tests and preflight passed. This adds bounded parent validation work, without refreshed performance qualification. Prior full baseline and Linux snapshot remain historical/frozen; no ledger refresh. Next: audit ordinary result/request dimensions and remaining privacy requirements, then reconcile source into PR81. All manual, USB, physical and release gates and frozen Part B candidate remain unchanged.

## Worker result/request canvas binding

[Immutable request-canvas evidence](validation/M3-WORKER-REQUEST-CANVAS-2026-09-17.md) records local unpublished 0315fbc236f1f553e13bb6a3e4e5f910133ab46c. Three internally canonical wrong-canvas results were reproduced. Successful output now compares both dimensions against DotCanvas reconstructed from the immutable staged ticket, preserving original-unit rounding and independent X/Y resolution without rescaling bytes. Fifty-five native cases passed debug/release; final two parent regressions passed both modes after tightening artifact fixture requests, keeping pixel/padding checks independent of request rejection. Preflight and106 Python tests passed. Prior full source baseline/Linux snapshot remain historical/frozen; no ledger refresh or manual/hardware completion. Next: finish privacy/gate reconciliation and prepare coherent source integration into PR81. No printer, queue, privilege, merge or publication actions; frozen candidate unchanged.

## Direct dependency provenance inventory

[Existing direct dependency audit](validation/M6-DIRECT-DEPENDENCY-PROVENANCE-2026-09-17.md) and THIRD-PARTY-NOTICES now record exact fixture/action pins, primary license evidence, roles and non-bundling. Exact Pillow12.3.0 metadata declares MIT-CMU; ReportLab BSD-3-Clause is explicitly an inspected mapping rather than a publisher expression. Verified ReportLab sdist and pinned action license hashes are recorded. No dependency/version/runtime change or acceptance refresh. Live issue80 still has no PartB result; production adapter selection remains deferred. Next: full-scope independent gap reconciliation and source integration, retaining all manual/hardware/release gates.

Provenance slice checks: all four fixture versions matched exact published metadata and both unique workflow commits matched the notices; repository preflight and diff check own exits 0; disclosure scan/manual review passed. Runtime tests NOT RUN for documentation-only changes.

## PDF page-box finite extents

[M2-PAGE-BOX-FINITE-EXTENTS-2026-09-17.md](validation/M2-PAGE-BOX-FINITE-EXTENTS-2026-09-17.md) records a regression-backed portable admission fix: eight overflowing extent acceptances reproduced, shared source-rectangle validator reused, finite negative origins preserved. Core302 and focused native38 passed debug/release; before/after accelerator and preflight passed. Local source remains unpublished. No acceptance refresh or manual/physical claims. Next: reconcile PR dependency/merge readiness and unpublished source before remote changes. Frozen Part B candidate unchanged.

## Private worker contracts reconciled

Local unpublished d86206a2bb5721c36569f5f7100c5b58c3facb66 documents the implemented integer-token, bitmap/ZPL, immutable canvas and layout-result admission boundaries in CONTRACTS.md. Source inspection checked all five message types and both render parents; preflight and diff check exited0. Runtime tests NOT RUN for documentation-only changes; existing regression receipts remain historical. Explicitly retains limits: no general Codable integer-identity claim, no arbitrary-child rendering/page-completeness proof, no performance refresh or M3-AC12 acceptance. No source/fixture/oracle/queue/device/privilege changes or remote publication. Next: consolidate the current privacy/permissions audit across implemented transport/options/diagnostic/IPC paths, then prepare reviewable unpublished-source integration. Production helper/adapter and installed scheduler gates remain open; frozen Part B candidate unchanged.

## Identifier-bearing error redaction

[Regression evidence](validation/M3-IDENTIFIER-ERROR-REDACTION-2026-09-17.md) evaluates local unpublished 2c128dbf7d47c14a52e3fbb47764ce0c5acf3252. Six error cases across queue/draft/extraction/reference workflow validation now redact identifier strings in routine formatting and nested dumps, preserving typed payloads/equality and useful fixed codes. Initial10 plus expanded9 assertion failures reproduced before fixes. Final303Core debug/release,20native editor/diagnostic debug,106Python and accelerator oracles/inert cases passed; preflight/diff passed. Earlier20native release applies only to initial scope, not final expanded source. No whole privacy acceptance/ledger refresh or manual/physical claim. Next: audit remaining implemented option/IPC/diagnostic paths and prepare reviewable source integration; production helper/scheduler/USB and frozen PartB candidate remain gated. No device/queue/privilege/remote mutation or publication.

## Private-safe editor action messages

[Regression evidence](validation/M4-EDITOR-ACTION-ERROR-MESSAGES-2026-09-17.md) evaluates local unpublished f14b71c18368a4008c007783e0de07f24e3c563e. Editor action failures now use fixed localized guidance rather than arbitrary error descriptions; uncertain saves retain preserve-and-review guidance. One regression reproduced six assertion failures before the fix and verifies synthetic NSError/region identity redaction, stale edit guidance, uncertainty and unchanged draft/generation/save flag.21focused native cases passed debug/release;106Python/preflight/diff passed. No Core/oracle changes, full CI, GUI/VoiceOver, translated-locale or physical evidence claimed. No acceptance refresh or remote publication. Next: finish implemented privacy/IPC/options reconciliation and reviewable source integration. Production scheduler/helper/manual/USB gates and frozen PartB candidate unchanged.

## Offline lab failure privacy

[Regression evidence](validation/M2-LAB-FAILURE-PRIVACY-2026-09-17.md) evaluates local unpublished 4f8d38eb9c4c8087909dc36cb9d805e18bc48a86. Real lab filesystem failure exposed a synthetic caller path before the fix. Four known lab failures now have fixed typed guidance; unknown errors use fixed preparation failure. Two real blocked/existing destination cases assert path-free stderr, exit2/empty stdout and unchanged caller file/no extra output. Both accelerator modes passed106Python/303Core,132strict/180compression,2privacy/12CLI/15ABI/14filter/1discard; preflight/diff passed. No encoder/oracle/fixture change or whole privacy acceptance. Native/fullCI/GUI/admin/printer evidence not refreshed. Next: current integrated native baseline and privacy/source-integration audit. Production adapter/helper/manual/USB gates and frozen PartB/Linux snapshots remain unchanged; no remote publication or privileged/device operation.

## Current privacy integrated software baseline

[Full native receipt](validation/M2-M5-PRIVACY-INTEGRATED-BASELINE-2026-09-17.md) evaluated clean local unpublished d41f091681e8986691107419e1667c6b01cc4559; finite900-second CI wrapper exited0.106Python/303Core/374Mac passed debug/release, both oracles/inert pipelines plus2newlab privacy cases, ARM/min26 metadata, nested ad-hoc signatures, fail-closed Developer-ID negative and packaged worker equality. Actual host27.0 is not runtime26 qualification. Local app setup-app.DVSdSn does not replace frozen manual candidate. New533-file exact tracked-source Linux archive/handoff is ready locally; no worker/result claimed. Older archive remains frozen. No whole privacy acceptance/ledger refresh, manual/physical result or publication. Source delta beyond published PR81 spans126files; primary checkpoint is an ancestor and untouched. Next: privacy/source-integration review and exact remaining requirements audit, retaining production adapter/helper/scheduler/USB gates.

## Shared publication identity redaction

[Regression evidence](validation/M5-PUBLICATION-DIAGNOSTIC-REDACTION-2026-09-17.md) evaluates local unpublished a5ee0f7eef8bb1f29de85e41a5f3f9fc5189deb4. All six identity-bearing commit-uncertain error wrappers now redact their four shared value types in routine descriptions/reflection/dumps, preserving typed IDs/hashes/equality and existing codecs/uncertainty. Regression reproduced60 assertions before fix.96actual store/editor cases plus9actual finishing-plan cases passed debug/release (105distinct per mode);106Python/preflight/diff passed. Two nonexistent filter alternatives counted as no evidence. Prior full374-native baseline and app/Linux snapshot remain bound to older source; no full/signature/packaging refresh for this native reflection-only patch. No whole privacy/ledger acceptance or manual/physical claim. Next: finish implemented privacy/source-integration review and requirements reconciliation. Production adapter/helper/scheduler/USB gates and frozen PartB candidate unchanged; no remote publication or privileged/device operation.

## Atomic candidate output-stock edit

[Stock draft evidence](validation/M4-DRAFT-OUTPUT-STOCK-2026-09-17.md) evaluates local unpublished4f6fbd9b0471cbfc8b730cb01f68e6fb8ee011b7. Validated atomic stock replacement preserves source-sheet rules/crops/skips, candidate revision, copy order and immutable original profile.304Core debug/release,106Python and accelerator passed; initial test-only qualification compile error corrected. This does not complete native stock UI or M4 media acceptance. Next: explicit rendering context retaining resolution/resource/stock limits, coherent bootstrap policy and preview/review invalidation before exposing stock changes. Full native/signatures/Linux not refreshed; frozen manual candidate and all scheduler/helper/USB/physical gates unchanged. No merge or publication.

## Limit-preserving stock canvas

[Canvas receipt](validation/M2-CANVAS-STOCK-RESIZING-2026-09-17.md) records unpublished8749143. DotCanvas retains admission budgets for validated physical-size replacement with original independent pitch; geometry equality remains compatible with finishing binding. Preliminary305Core both/accelerator passed; final9geometry cases both passed after explicit equality refinement. Native stock editor integration remains next; no native/GUI/physical/signature acceptance refreshed. Frozen candidate unchanged.
