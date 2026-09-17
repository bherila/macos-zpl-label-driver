# M3-AC05 network correctness automated assessment

A-level pass at clean evaluated implementation `b12e65a63cfebcce3625a249975e837dbb0bc2ee`. This assesses the exact simulator criterion, not installed scheduler/device acceptance.

| Required case | Inspected implementation and executed oracle |
|---|---|
| Short writes | BoundedDelivery offers at most 64 KiB and advances by accepted counts; tests enumerate 2/2/1 and a >1 MiB payload accepted in 49153-byte prefixes, compare complete bytes/order and bound the largest offer. Impossible negative/over-offer counts are uncertain, never retryable. |
| Backpressure | Native owned loopback peer reads exactly 64 bytes of a 16 MiB synthetic stream then stalls. The 1000 ms deadline yields timedOutAfterSendAttempt/uncertainty despite zero reported framework bytes; the observed prefix proves transmission happened. |
| Framing | Real typed prepared single and two-label jobs reassemble exactly under variable-sized loopback reads. Format delimiters/count, complete ordered bytes and immutable snapshots are asserted. Receiver read sizes are not misrepresented as sender short-write counts. |
| Zero-byte failure | An explicit-count sink guarantees zero accepted bytes and fails before transmission; zero after an accepted prefix is uncertain. A bound non-listening loopback port yields refusal or before-send timeout without manufacturing success. Raw TCP send-attempt ambiguity never becomes known-zero safe retry. |
| Mid-stream disconnect | Loopback zero-linger reset after an observed prefix produces sendFailedAfterAttempt and uncertainty, never device confirmation or automatic retry permission. |
| Timeouts | Before/after-send classifications are enumerated. Timeout/cancellation during serialized send admission remain uncertain. Late success/failure/readiness/connection-end events cannot change a settled result or repeat send/cancellation/caller completion; a queued observer proves all late events were processed. |

Read BoundedDelivery's byte-count/throw contract, RawTCPDelivery's Network.framework adapter and serialized state machine, DeliveryTracker transitions, complete prepared-job framing, and every named assertion in BoundedDeliveryTests/RawTCPDeliveryTests. Network.framework owns native segmentation; portable explicit-count sink tests supply the independent short-write oracle. These complementary tests cover each listed criterion without pretending the native adapter exposes write counts it does not report.

All cited cases executed in the clean full native CI sequence: 299 Core and 364 Mac tests debug/release, exit 0; see [integrated baseline](M2-M5-EXACT-JSON-INTEGRATED-BASELINE-2026-09-17.md). Native TCP suite has 17 methods, including actual finite loopback faults. The late-settlement fault was independently detected before restoration. No new code changed for this assessment, and no full-suite repeat was needed.

Local transmission is not printed output or a device receipt. This pass does not qualify USB, installed queue/backend lifetime, physical coordination, scheduler retry mapping, status-channel support, printer/network permissions, any remote printer or broader model/accessory behavior. M3-AC06/07/08/09/10/11 and M1/M5/M6 integration/hardware/release gates remain open at their prescribed evidence levels. No network scan, printer command, queue change, privilege, manual GUI, merge or release occurred. All servers bind only owned loopback endpoints with finite budgets.

This is an explicit semantic assessment with exact source/file references. Prior unchecked prose demanding unspecified production policies did not alter M3-AC05's A-level criterion; production claims remain gated separately. Older source records remain historical and are not mechanically refreshed.
