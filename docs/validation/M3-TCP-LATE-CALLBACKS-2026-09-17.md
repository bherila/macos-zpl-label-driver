# TCP terminal-state callback ordering

Advances automated M3-AC05 timeout/cancellation coverage without closing the full acceptance criterion or installed scheduler gates.

The independent constraint is terminal-state immutability: after timeout, cancellation or connection failure settles an admitted send, later Network.framework callbacks must not authorize another send, settle the caller twice, replace the stored result or repeat transport cancellation. The existing implementation already enforces this; this slice adds missing adversarial regression coverage rather than another transport implementation.

The test enumerates timedOutAfterSendAttempt, cancelledAfterSendAttempt and sendFailedAfterAttempt. It admits a send while retaining the completion callback, settles the selected failure, then delivers both late success/failure callbacks, connection end, readiness, timeout, cancellation and start events. A completion registration queued after all events observes the stored result and proves the serial queue drained. Assertions require the original result, one caller completion, one send and one transport cancellation. Expectations have one-second finite deadlines; there is no arbitrary sleep or network/device endpoint in this test.

A deliberate fault removing phase = .settled caused five expected failed assertions in the final regression (changed stored results and repeated cancellation). The source was restored before final validation. The final debug and release RawTCPDeliveryTests suites each passed 17 tests with exit 0. Existing real loopback backpressure, prefix reset, refused connection and complete typed prepared-job framing cases remain included. Sender short-write accounting belongs to portable delivery APIs; variable-sized receiver reads are not sender short-write observations. Full M3-AC05 assessment remains open rather than promoting this focused test to complete production network correctness.

No product API, wire schema, status query or device command changed. No printer I/O, queue operation, administrator action, GUI test, merge or release occurred. These are unpublished local test results, not hosted CI. Previous source-bound acceptance records remain historical after test changes. Manual M1 Part B and hardware gates are unchanged.

Evaluated regression SHA-256: d0f83df8b78e2bf660dae831d28fb103f5f6e67c6fd27db2db8dee0df9bbc2c4
