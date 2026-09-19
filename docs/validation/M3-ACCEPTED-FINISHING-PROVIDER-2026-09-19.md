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
overwrite API, so `recordOutcome` validates the disposition against that complete
context before anything is written: the step index must address a framed step of the
kind that state can stop at, and a partial transmission must report a byte count the
framed file can produce. An uncertain disposition cannot be recorded unless the
durable send-attempt record already exists. The closed textual token set is decoded
by exact canonical re-encoding, not by a synthesized `Codable` layout.

`BoundedFinishingDelivery` acquires the artifact (job) lease and the physical-device
lease, both nonblocking, before any provider call, refuses to run when any durable
record already exists, publishes the send-attempt record before the first offered
file and before all byte accounting, revalidates ownership after every complete file
and every status wait, records the terminal state while both leases are still held,
and releases both on scope exit including thrown errors. Cancellation and the finite
deadline are enforced by the executor so a cancelled or expired run can still record
its terminal state, and both are rechecked after a status wait completes, before the
returned reading is consumed. The finite deadline reads a monotonic source that is
injectable inside the module; production callers always read the real clock.

The returned `Outcome` publishes the disposition plus an `Accounting` value holding
the byte and step facts. It deliberately does not republish the in-memory tracker:
that tracker maps a pre-attempt timeout and a pre-attempt ownership loss onto its
`failedBeforeAttempt` state, whose `mayRetryAutomatically` would contradict the
disposition recorded for the same run. `authorizesBoundedRetry`, identical to what
the durable record reports on a later cold observation, is the only retry signal.

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

## Review findings addressed

Four P2 findings were raised against this branch by an automated reviewer and each
was checked against the source before any change was made.

1. Real. `BoundedFinishingDelivery` rechecked only ownership after `awaitStatus`
   returned. Every framed file step is immediately followed by a status step, so the
   last step is always a status wait: a `satisfied` reading that arrived after the
   run was cancelled or after the deadline expired advanced the tracker to
   `confirmed`, left the loop and durably published `allStepsSatisfied`. Cancellation
   and expiry are now decided before the reading is consumed, yielding
   `cancelledAfterAttempt` or `timedOutAfterAttempt` at the interrupted step. The
   same recheck also corrects the step named when a wait is interrupted mid-run: the
   step whose wait was crossed, rather than the following step the old code had
   already advanced to.
2. Real, and wider than reported. `halt(false)` for a pre-attempt timeout left the
   tracker in `failedBeforeAttempt`, so the published `tracker.mayRetryAutomatically`
   was true while `authorizesBoundedRetry` was correctly false; a pre-attempt
   ownership loss had the same contradiction. The fix removes the second signal
   rather than renaming one instance of it: the tracker is no longer part of the
   public returned state and the new `Accounting` value carries no retry
   authorization. Adding distinct tracker states instead would have grown a public
   enum shared with another executor while still leaving two signals that can drift.
3. Real. `recordOutcome` serialized any public enum value, so `ownershipLost(-1)` or
   a `partialTransmission` whose accepted count equals its expected count was
   published durably and then rejected by this store's own parser on every later
   observation, with no reset API to recover. Admission is now fail-closed with a
   typed `invalidDisposition` error, checked before the intent requirement so the
   error is precise.
4. Real. The timeout regressions gave the whole delivery one real second and assumed
   a one-second scripted status wait would be what crossed it, while archive
   validation, lease work, intent publication and the first transmission spent the
   same budget. The deadline now reads an injected monotonic source that the test
   advances at a chosen step, so no wall-clock boundary is involved. The provider's
   own simulated-wait cap is still asserted directly.

Added and extended regressions in
`Packages/LabelMac/Tests/LabelMacTests/BoundedFinishingDeliveryTests.swift`:
`testLateCancellationOrExpiryAcrossAStatusWaitNeverCompletesTheRun` drives a
cancellation and, separately, a deadline expiry across the final status wait and
asserts the run is uncertain, names the final step, is not `allStepsSatisfied`,
establishes no physical completion, authorizes no retry, and records that state
durably, while the provider event log shows the wait really was performed.
`testUnreachableDispositionsAreRefusedBeforePublication` asserts that ten
unreachable dispositions are refused with `invalidDisposition` and leave the record
absent, and that all fifteen reachable ones are admitted and read back exactly
through a freshly constructed store. The existing terminal-state case now asserts
that the outcome's retry authorization equals the durable record's, and that the
pre-attempt timeout keeps the contradictory tracker flag internal.

No acceptance criterion was relaxed, no assertion was removed or weakened, and no
existing test was disabled.

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
- `swiftc -frontend -parse` on each new and changed Swift file — exit 0, no
  diagnostics. This is syntactic parsing only. It is not type checking, concurrency
  checking, availability checking or a build.
- `swiftc -swift-version 6 -typecheck` on a scratch file reproducing the review-fix
  constructs against local stubs — exit 0. It covers the two `run` overloads and the
  defaulted call between them, the local `exhausted()` closing over the non-escaping
  monotonic parameter, the multi-pattern `case let` bindings in the new validation
  switch, the optional `ManualClock` test parameter and a non-`Sendable` clock
  captured by an `@escaping` closure formed in a `@MainActor` context. The stubs are
  not the real types, so this is a language-level check of the new constructs only
  and is not a build of `LabelMac`.

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

The injected monotonic source is a module-internal parameter on `run`. It removes a
wall-clock race from the regressions; it is not evidence about the real deadline's
behaviour under load, which only the hosted run and later real transmission work can
provide.

The executor's own dispositions were already within the bounds the store now
enforces, so the admission check changes no delivery outcome. It constrains what any
other caller of the public store can publish.

Implementation source `c04276a8b4706f4bd7dd425b1954de946062e19c`, with the review
fixes in `30a295a1201bc570e74a471e3866be971d8d5ef2`; committed locally on
`codex/m3-accepted-finishing-provider`. Not pushed. Hosted coverage pending. No
printer, administrator, merge, release or binary publication action was taken.
