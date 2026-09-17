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
  `eafb5644df2073ce859f98c540ccbb5128325f6a`. Latest implementation commit
  `3a5b79a`: finite inert finishing coordinator and lease-lifetime tests.
- Latest finite900s `bash scripts/ci-swift.sh`, session1032, completed
  `FULL_GATE_EXIT 0`:89 Python/272 Core/324 native tests in debug/release,
  132 strict and180 ASCII oracle round trips per mode, finite benchmark and inert
  ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc signatures,
  unavailable Developer-ID negative, and packaged-worker PBM/ZPL equality.
  Local artifact: `artifacts/setup-app.hSSAIH`; no printer accessed.
- Restored focused tests passed after independent fault checks. Early lease release
  before status waits failed45assertions. Previous framing faults detected quantity2,
  ordinary cutter-mode substitution and omitted complete-profile binding; delivery
  accounting detected treating zero known accepted bytes as a retryable send attempt.
- Hosted run35233437806 for the published head is in progress; repository
  validation and change-scope classification passed. No terminal hosted pass yet.
  Previous run35232614294 at `d64ee84` is still in progress. Poll these existing
  handles; do not restart on an observation timeout. Last verified successful hosted
  checkpoint:run35229621380 at `07ef316`, which does not qualify newer changes.
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

## Local artifact slice awaiting source publication

FinishingFramedArtifact now serializes exact immutable context plus separate ordered
files/status requirements. Reopen compares canonical bytes against independently supplied
context; it never parses attacker-controlled counts or manufactures replay authority.
Nine restored native focused cases passed; omitting original-source hash failed four
assertions with identical rasters/files. Full finite900s session1032 passed ownexit0 with the checks above;
log /tmp/zpl-finishing-artifact-full.log. Source/disclosure review passed with restored
hash unchanged. Implementation 9a14f80b7efa857f01a98e96a87e79e651501a50 is committed locally;
hold push until the published checkpoint CI finishes.
See [artifact serialization](validation/M3-FINISHING-FRAMED-ARTIFACT-2026-09-17.md).
The consolidated handoff/history commit is local and not yet pushed; wait for the
published checkpoint's hosted result before pushing new work.

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

Next independent software work: private durable framed-artifact publication and conservative
restart recovery; persistent exact-profile output qualifications; accepted finishing
queue/ticket/device and qualified-pitch binding; actual bounded file/status provider
integration retaining ownership throughout waits. These must reuse established
immutable stores and coordination invariants, not manufacture accepted-device authority
from the private utility catalog or flatten finishing files into raw TCP bytes.

Manual M1 must establish actual scheduler fidelity/options, sandbox/helper identity,
backend lifetime and retry behavior before production adapter assumptions. Installed
queue management, privileged authorization/lifecycle, restart repair and system-dialog
visibility remain open. GUI/accessibility and compatibility/release matrices also remain
open. M6 is not implemented/accepted simply because local builds pass.

Physical qualification requires separately authorized named hardware and finite label/
command budget. GC420d USB4×6pre-cut tear-off/no cutter is the primary target; retain
separate S2 accessory/model evidence. USB unplug/replug, output quality/count/order,
physical status/faults, actual cross-queue serialization and finishing remain unobserved.
Never promote compiled, inert, reported GUI or hosted checks into printed evidence.
Do not automatically calibrate/reset/save/upgrade firmware/erase or replay ambiguity.
