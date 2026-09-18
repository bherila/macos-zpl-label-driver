# M3 — complete prepared-job delivery binding

## Scope and constraints

Additional partial M3-AC05/09/12 automated evidence on the existing PR #81
branch. Complete preparation already checks every ordered output identity,
common immutable profile and resolved controls. Delivery previously exposed
only a typed single-label handoff or revision-only arbitrary bytes.

The nearest independent constraint is exact ordered byte binding across the
preparation/delivery boundary. Equal-length substitution is not an identity
check. The new `DeliveryTracker(preparedJob:)` binds the complete original byte
stream and snapshot through the same private initializer as the single-label
path. Existing pre-write validation rejects substituted bytes without a sink
callback, preserving the waiting state so the correct payload can be delivered.

`RawTCPDelivery.send(PreparedJobPayload, ...)` hands the complete already-resolved
stream to the existing finite Network.framework attempt. It never reapplies
copies, page ranges or collation. A shared result path retains the complete-job
snapshot through every completion/failure boundary. Local acceptance remains
transmitted rather than printed; post-attempt ambiguity remains uncertain and
never automatically replayable. This low-level adapter does not acquire the
physical-device lease and is not a production queue/coordinator entry point.

## Evidence actually obtained

- Pre-implementation focused Core build: exit 1 because the complete-job tracker
  initializer did not exist. This identifies a missing API, not a behavioral
  regression pass or physical result.
- Nine focused `BoundedDeliveryTests` pass exit 0. Two distinct labels in a
  deliberately non-page-sorted order reject equal-length reordered bytes before
  any write and then deliver exactly the original bytes with the bound snapshot.
- Fourteen focused `RawTCPDeliveryTests` pass exit 0. A finite Darwin peer bound
  only to 127.0.0.1 consumes the complete two-label stream in variable-size reads;
  byte equality and exactly two envelopes pass. All seven deterministic attempt
  outcomes retain the job snapshot and truthful delivery/retry state.
- Initial native test compilation found the output-identity initializer is
  intentionally internal. Test-only `@testable import LabelCore` constructs the
  synthetic identities without broadening the production API.
- Required `bash scripts/ci-swift.sh`: PASS, exit 0 within the 900-second
  timeout. 86 Python / 189 Core / 267 Mac tests pass in debug/release, as do
  original 132 and compressed 180 independent vectors, 15 inert ABI / 14 filter
  ABI / one discard pipeline per configuration, native builds, nested ad-hoc
  signatures, ARM/minimum-26 metadata and packaged-worker PBM/ZPL equality.
- PR #81 second/final review is clean at base `77c29ff` / head `a370e05`:
  reviewer thumbs-up, no inline findings, submissions or review threads. This
  follow-on was not present at that reviewed head. No third request is planned.
- Source inspection checks shared snapshot/byte initialization, reuse of the
  existing finite attempt/result paths, and no added copies or lease claims.
  This is local inspection rather than independent cloud review.
- Scheduler/USB/physical delivery, lease integration and qualification: NOT RUN.

Actual local runtime: macOS 27.0 (26A428), arm64, Xcode 27.0, Swift 6.4.
The separately frozen B candidate remains unchanged; these package builds do
not replace its files or imply administrator approval.

## Next action

Complete required gates and publish on the existing branch. Reconcile the
already-requested second PR review against its exact reviewed source pair; do
not infer review of this follow-on from an earlier thumbs-up. No merge or release.
