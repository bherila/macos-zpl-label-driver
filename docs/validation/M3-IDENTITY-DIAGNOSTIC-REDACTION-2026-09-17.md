# M3 — routine identity diagnostic redaction

## Requirement and independent constraint

Additional partial M3-AC12 automated evidence on the existing PR #81 branch.
Normal diagnostics must not expose private endpoints or device identity fields
(CONTRACTS.md). The nearest independent constraint is preserving explicit typed
transport/profile access and equality while redacting routine diagnostics.
Redaction is not access control and must not change configured delivery bytes.

The audited sites are `StableConnectionIdentity`, `RawTCPEndpoint` and
`USBPrinterObservation`. The first and third already redacted descriptions but
Swift structural dumps revealed their stored fields. The endpoint had default
field-bearing descriptions as well. Shared portable `RedactedDiagnosticValue`
provides type-only redacted descriptions/debug descriptions and an empty custom
mirror. All three sites conform; the private profile codec and explicit typed
transport/registry fields remain intact. Other arbitrary caller-owned strings,
explicit field exports and IPC policies are outside this narrow diagnostic fix.

## Actual regression evidence

- Three correctly selected old-code tests each fail, exit 1: connection identity
  three assertions, TCP endpoint five, registry observation six. Nested array
  dumps exposed the synthetic private value, host/port or registry fields.
- An initial USB test selection matched no cases; it was not counted as evidence.
  The test was moved from the test seam to the XCTest class and rerun correctly.
- Fourteen `PrinterProfileTests` pass exit 0, including existing description/range
  expectations plus explicit original private identity preservation.
- Fifteen `RawTCPDeliveryTests` pass exit 0, including explicit endpoint field /
  equality preservation, safe descriptions/dumps, real finite loopback delivery,
  complete-job equality and truthful fault boundaries.
- Six `USBRegistryDiscoveryTests` pass exit 0, including safe structural dump and
  unchanged explicitly accessed synthetic registry metadata.
- Required `bash scripts/ci-swift.sh`: PASS, exit 0 within the 900-second
  timeout. 86 Python / 190 Core / 269 Mac tests pass in debug/release, including
  private profile JSON round trips. Original 132 / compressed 180 oracle
  vectors, 15 inert ABI / 14 filter ABI / one discard pipeline per configuration,
  native builds, nested ad-hoc signatures, ARM/minimum-26 metadata and packaged
  worker PBM/ZPL equality all pass.
- Actual local runtime: macOS 27.0 (26A428), arm64, Xcode 27.0, Swift 6.4.
- Scheduler/USB physical delivery, installation, IPC-wide privacy and production
  acceptance: NOT RUN. No queue, printer or privileged action is added.

## Review and next action

PR #81 second/final cloud review is clean at base `77c29ff` / head `a370e05`;
this follow-on is not part of that reviewed source. Local inspection enumerates
all three identity diagnostic sites and shared policy, without inferring cloud
review of new code. Complete required gates, publish the coherent follow-on,
and retain exact-head hosted and manual gates. No third review request, merge
or release publication. The separate frozen B candidate remains unchanged.
