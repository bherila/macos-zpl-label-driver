# Bounded inert finishing delivery provider — 2026-09-19

No acceptance ID is claimed and no evidence level is asserted for this change. The
new code is related to the M3 delivery-state work recorded in
[attempt intent](M3-FINISHING-ATTEMPT-INTENT-2026-09-17.md) and
[inert persisted coordination](M3-INERT-PERSISTED-FINISHING-2026-09-17.md), and it
extends those semantics rather than replacing them. No accepted sender, correlated
device status, hardware receipt or replay authority is introduced. Nothing here is
I, H or R evidence, and none of the new source was compiled or executed anywhere.

## What was implemented

`FinishingDeliveryProvider` is a bounded file/status boundary. The caller passes a
scoped `FinishingDeviceOwnership` witness; a provider may observe it and may never
release, re-acquire or outlive it. A Swift actor is not a cross-process device lock,
so ownership is two kernel `flock` descriptors owned by the executor. Readiness,
complete-file publication (`published` / `ambiguous`) and status readings
(`unknown` / `notSatisfied` / `satisfied`) are separate facts; unknown is never
false, zero, supported or completed, and complete files are never flattened into
raw transport frames or concatenated.

`FinishingDeliveryDisposition` gives each terminal state a distinct observable case:
`allStepsSatisfied`, `failedBeforeAttempt`, `cancelledBeforeAttempt`,
`timedOutBeforeAttempt`, `cancelledAfterAttempt`, `timedOutAfterAttempt`,
`partialTransmission` (with the exact step and accepted/expected counts),
`ambiguousPublication`, `statusUnknown`, `statusNotSatisfied`, `ownershipLost` and
`providerFailedAfterAttempt`. `establishesPhysicalCompletion` is false for every
case, including full synthetic satisfaction. `authorizesBoundedRetry` is true only
for a proven pre-attempt refusal.

`FinishingDeliveryOutcomeStore` publishes at most eight append-only bounded 1024-byte
binary records in `finishing-deliveries`, reusing the existing private immutable
directory's exclusive publication lock, namespace validation, permissions and
durability checks. Both record kinds independently revalidate the archived complete
framed context through `FinishingArtifactStore`. There is no clear, reset or
overwrite API. An uncertain disposition cannot be recorded unless the durable
send-attempt record already exists. The closed textual token set is decoded by exact
canonical re-encoding, not by a synthesized `Codable` layout.

`BoundedFinishingDelivery` acquires the artifact (job) lease and the physical-device
lease, both nonblocking, before any provider call, refuses to run when any durable
record already exists, publishes the send-attempt record before the first offered
file and before all byte accounting, revalidates ownership after every complete file
and every status wait, records the terminal state while both leases are still held,
and releases both on scope exit including thrown errors. Cancellation and the finite
deadline are enforced by the executor so a cancelled or expired run can still record
its terminal state.

`InertFinishingDeliveryProvider` is discard-only: it opens no socket, performs no
transport, never invokes `lpr` and keeps no output sink. Its status readings are
scripted simulator input, never a device receipt.

## Nearest independent constraints exercised by the added regressions

Ownership must cover the whole wait, not only the write; an uncertain or partial
state must survive a restart-like cold reopen byte-exactly and with no byte callback;
the absence of a record must authorize nothing; synthetic completion must not become
physical completion; and ambiguity must not authorize replay. The added focused cases
in `Packages/LabelMac/Tests/LabelMacTests/BoundedFinishingDeliveryTests.swift` cover
each terminal state above, competing lease acquisition failing at every step index
including status steps, losing ownership mid-wait, cold reopen of the exact
`partialTransmission` step and counts through a freshly constructed store, refusal of
a second run after both a partial transmission and full synthetic satisfaction with
the replacement provider never reached, rejection of a record written without prior
intent, and rejection of alternate spellings, a negative step, an unknown token and a
foreign reference in the record codec.

## Environment

Linux x86_64 (kernel 6.18.44), Swift 6.1.3, Python 3.11, `libcups2-dev` installed.
No macOS host, no `xcrun`, no Core Graphics, no CryptoKit, no printer, no network
transport and no privileged action. No local macOS candidate was built or frozen.

## Commands actually run, with exact results

- `python3 scripts/check_repo.py` — exit 0. "Repository preflight passed (links,
  metadata, milestone files, action pins)."
- `python3 -m unittest discover -s scripts/tests` — exit 0. Ran 108 tests in 1.180s,
  OK (skipped=2).
- `swift test --package-path Packages/LabelCore` — exit 0. Executed 313 tests, 0
  failures, in 5.158s; swift-testing run with 0 tests also passed.
- `python3 scripts/run-accelerator-checks.py` — exit 0. "PASS: offline accelerator
  suite." 132 cross-language ZPL/PBM/analytic round trips, 180 independent ASCII
  compression round trips, 12 finite encoding benchmark CLI cases, 15 inert CUPS ABI
  cases, 14 inert CUPS filter ABI cases, 1 inert filter-to-discard pipeline case.
- `git diff --check` — exit 0, no output.
- `swiftc -parse` on each new and changed Swift file — exit 0, no diagnostics. This
  is syntactic parsing only. It is not type checking, concurrency checking,
  availability checking or a build.

## Not run, and why

- `swift test --package-path Packages/LabelMac` — NOT RUN. `LabelMac` declares
  `platforms: [.macOS("26.0")]` and imports `CryptoKit`, `Darwin` and
  `CoreGraphics`, none of which exist on this Linux host. No shim, no weakened
  platform declaration and no workaround was attempted.
- `bash scripts/ci-swift.sh` — NOT RUN. It requires macOS and `xcrun`.
- Consequently every line of new `LabelMac` source and every new focused test is
  UNCOMPILED and UNEXECUTED. The four commands above exercise the repository
  preflight, the Python tooling, the portable `LabelCore` package and the offline
  accelerator suite; none of them touches the new code. Hosted `macos-26` CI is the
  only compile and test evidence for this change, and until it runs the change has
  no execution evidence at all.
- No installed scheduler, CUPS queue, GUI, signing, installation or physical printer
  test was run or is claimed.

## Limitations

The delivery lifecycle is keyed by `FinishingArtifactReference`, the immutable
archive of a framed output. It is deliberately not yet bound to
`AcceptedFinishingReference`; accepted-job identity, the accepted attempt and
cancellation stores and accepted lifecycle recovery remain separate work in the
accepted-finishing path, and this change does not modify them.

The executor refuses every run once any durable record exists, including a recorded
pre-attempt refusal. `authorizesBoundedRetry` therefore reports a distinction that no
automatic path acts on; a bounded retry still requires separate reviewed work and
real transmission evidence.

The artifact-lease domain string is duplicated from the existing persisted
coordinator so both paths serialize the same immutable reference. If one copy
changes without the other, the two paths would stop excluding each other.

A provider error after an attempted file is converted into a recorded uncertain
terminal state rather than rethrown, so a provider defect and a transport fault are
not distinguished at this boundary.

Ownership coverage is established structurally: both leases are acquired before the
first provider call and released only on scope exit, and the regressions assert that
competing acquisition fails at every step index including status steps. That is not
the same as observing a competing acquisition at an arbitrary instant inside a wait,
and it is not evidence about cross-process ownership on an installed scheduler.

Discarded byte counts are simulator accounting, not physical label counts. Nothing in
this change proves that a device received, printed, cut or released anything.

Implementation source `c04276a8b4706f4bd7dd425b1954de946062e19c`; committed locally
on `codex/m3-accepted-finishing-provider`. Not pushed. Hosted coverage pending. No
printer, administrator, merge, release or binary publication action was taken.
