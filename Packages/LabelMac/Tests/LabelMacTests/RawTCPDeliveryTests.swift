@preconcurrency import Network
import Darwin
import XCTest
@testable import LabelCore
@testable import LabelMac

final class RawTCPDeliveryTests: XCTestCase {
    func testEndpointDiagnosticsRedactCoordinatesWithoutChangingTransportValues() throws {
        let endpoint = try RawTCPEndpoint(host: "synthetic.example.test", port: 19101)
        XCTAssertEqual(String(describing: endpoint), "RawTCPEndpoint(redacted)")
        XCTAssertEqual(String(reflecting: endpoint), "RawTCPEndpoint(redacted)")
        var output = ""
        dump([endpoint], to: &output)
        XCTAssertFalse(output.contains("synthetic.example.test"))
        XCTAssertFalse(output.contains("19101"))
        XCTAssertTrue(Mirror(reflecting: endpoint).children.isEmpty)
        XCTAssertEqual(endpoint.host, "synthetic.example.test")
        XCTAssertEqual(endpoint.port, 19101)
        XCTAssertEqual(endpoint, try RawTCPEndpoint(host: endpoint.host, port: endpoint.port))
        XCTAssertNotEqual(endpoint, try RawTCPEndpoint(host: endpoint.host, port: 19102))
    }

    func testEndpointHostBudgetCountsUTF8BytesBeforeNetworkAdmission() throws {
        let maximum = "e" + String(repeating: "\u{0301}", count: 126)
        let oversized = maximum + "\u{0301}"
        XCTAssertEqual(maximum.utf8.count, 253)
        XCTAssertEqual(oversized.count, 1)
        XCTAssertNoThrow(try RawTCPEndpoint(host: maximum, port: 19101))
        XCTAssertThrowsError(try RawTCPEndpoint(host: oversized, port: 19101)) {
            XCTAssertEqual($0 as? RawTCPEndpoint.ValidationError, .invalidHost)
        }
        XCTAssertNoThrow(try RawTCPEndpoint(host: String(repeating: "a", count: 253), port: 19101))
        XCTAssertThrowsError(try RawTCPEndpoint(host: String(repeating: "a", count: 254), port: 19101))
        XCTAssertNoThrow(try RawTCPEndpoint(host: "::1", port: 19101))
    }

    func testEndpointRejectsURLComponentsWhilePreservingBareHostForms() throws {
        for host in ["tcp://synthetic.example.test", "synthetic-user@synthetic.example.test",
                     "synthetic.example.test/path", "synthetic.example.test?option=value",
                     "synthetic.example.test#fragment", "synthetic.example.test\\path"] {
            XCTAssertThrowsError(try RawTCPEndpoint(host: host, port: 19101)) {
                XCTAssertEqual($0 as? RawTCPEndpoint.ValidationError, .invalidHost)
            }
        }
        for host in ["synthetic.example.test", "127.0.0.1", "::1", "fe80::1%en0"] {
            let endpoint = try RawTCPEndpoint(host: host, port: 19101)
            XCTAssertEqual(endpoint.host, host)
            XCTAssertEqual(endpoint.port, 19101)
            XCTAssertFalse(String(reflecting: endpoint).contains(host))
        }
    }

    private func completeJob() throws -> PreparedJobPayload {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 29)
        let encoder = try ZPLPreparedLabelEncoder()
        let outputs = [ResolvedOutputLabel(sourcePage: 2, regionID: "first"),
                       ResolvedOutputLabel(sourcePage: 1, regionID: "second")]
        let labels = try zip(outputs, [UInt8(0x80), UInt8(0x40)]).map { output, pixel in
            PreparedOutputLabel(output: output, prepared: try encoder.prepare(
                bitmap: MonochromeBitmap(width: 8, height: 1, bytes: [pixel]), profile: profile))
        }
        return try PreparedJobPayload(labels: labels, expectedOutputLabels: outputs,
            monochromeConversion: .textAndBarcodeThreshold(cutoff: 128))
    }

    func testCompleteJobLoopbackPreservesEveryLabelAndBoundSnapshot() async throws {
        let job = try completeJob()
        let peer = try LoopbackFaultPeer()
        let complete = expectation(description: "complete two-label job")
        let finished = expectation(description: "bounded peer finished")
        peer.start(resetAfterPrefix: false, prefixReceived: complete, finished: finished,
            readGoal: job.bytes.count, readSizes: [1, 7, 2, 31])
        defer { peer.release() }
        let result = try await RawTCPDelivery.send(job,
            to: RawTCPEndpoint(host: "127.0.0.1", port: peer.port),
            configuration: RawTCPDeliveryConfiguration(timeoutMilliseconds: 2_000))
        peer.release()
        await fulfillment(of: [complete, finished], timeout: 3)
        XCTAssertNil(peer.failure.value)
        XCTAssertEqual(peer.received.value, job.bytes)
        XCTAssertEqual(String(decoding: peer.received.value, as: UTF8.self)
            .components(separatedBy: "^XA").count - 1, 2)
        XCTAssertEqual(result.receipt.profileSnapshot, job.profileSnapshot)
        XCTAssertEqual(result.receipt.state, .transmitted(bytesAccepted: job.bytes.count))
        XCTAssertNil(result.failure)
        XCTAssertFalse(result.receipt.mayRetryAutomatically)
    }

    func testCompleteJobSnapshotSurvivesEveryTransportFailureBoundary() throws {
        let job = try completeJob()
        let cases: [(RawTCPAttemptResult, DeliveryState, RawTCPDeliveryFailure?)] = [
            (.completed, .transmitted(bytesAccepted: job.bytes.count), nil),
            (.connectionFailed, .failedBeforeTransmission, .connectionFailed),
            (.timedOutBeforeSend, .failedBeforeTransmission, .timedOutBeforeSend),
            (.cancelledBeforeSend, .cancelledBeforeTransmission, .cancelledBeforeSend),
            (.timedOutAfterSendAttempt, .uncertain(bytesAccepted: 0), .timedOutAfterSendAttempt),
            (.cancelledAfterSendAttempt, .uncertain(bytesAccepted: 0), .cancelledAfterSendAttempt),
            (.sendFailedAfterAttempt, .uncertain(bytesAccepted: 0), .sendFailedAfterAttempt)
        ]
        for (attempt, state, failure) in cases {
            let result = try RawTCPDelivery.result(for: attempt, preparedJob: job)
            XCTAssertEqual(result.receipt.profileSnapshot, job.profileSnapshot)
            XCTAssertEqual(result.receipt.profileRevision, 29)
            XCTAssertEqual(result.receipt.expectedBytes, job.bytes.count)
            XCTAssertEqual(result.receipt.state, state)
            XCTAssertEqual(result.failure, failure)
            XCTAssertNotEqual(result.receipt.state, .deviceConfirmed)
        }
    }

    func testEndpointAndTimeoutRejectUnsafeValues() {
        XCTAssertThrowsError(try RawTCPEndpoint(host: "", port: 9100))
        XCTAssertThrowsError(try RawTCPEndpoint(host: "printer\nother", port: 9100))
        XCTAssertThrowsError(try RawTCPEndpoint(host: "127.0.0.1", port: 0))
        XCTAssertThrowsError(try RawTCPDeliveryConfiguration(timeoutMilliseconds: 0))
        XCTAssertThrowsError(try RawTCPDeliveryConfiguration(timeoutMilliseconds: 120_001))
    }

    func testLoopbackDeliveryReportsOnlyLocalTransmission() async throws {
        let listener = try loopbackListener()
        let received = expectation(description: "loopback payload")
        let box = ReceivedDataBox()
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                box.value = data
                received.fulfill()
                connection.cancel()
            }
        }
        listener.start(queue: .global())
        let port = try await listenerPort(listener)
        defer { listener.cancel() }

        let result = try await RawTCPDelivery.send(
            Data([0x5E, 0x58, 0x41, 0x0A]),
            to: try RawTCPEndpoint(host: "127.0.0.1", port: port),
            profileRevision: 7,
            configuration: try RawTCPDeliveryConfiguration(timeoutMilliseconds: 2_000)
        )

        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(box.value, Data([0x5E, 0x58, 0x41, 0x0A]))
        XCTAssertEqual(result.receipt.state, .transmitted(bytesAccepted: 4))
        XCTAssertEqual(result.receipt.profileRevision, 7)
        XCTAssertNil(result.failure)
    }

    func testPreparedLabelDeliveryPreservesTheBoundProfileSnapshot() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 17)
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0x40])
        let prepared = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: profile)
        let result = try RawTCPDelivery.result(for: .completed, preparedLabel: prepared)

        XCTAssertEqual(result.receipt.state, .transmitted(bytesAccepted: prepared.bytes.count))
        XCTAssertEqual(result.receipt.profileSnapshot, prepared.profileSnapshot)
        XCTAssertEqual(result.receipt.profileRevision, 17)
        XCTAssertNil(result.failure)
    }

    func testTaskCancellationEntersAttemptStateMachine() async throws {
        let listener = try loopbackListener()
        listener.newConnectionHandler = { connection in connection.start(queue: .global()) }
        listener.start(queue: .global())
        let port = try await listenerPort(listener)
        defer { listener.cancel() }

        let task = Task {
            try await RawTCPDelivery.send(
                Data([0x5E, 0x58, 0x41]),
                to: try RawTCPEndpoint(host: "127.0.0.1", port: port),
                profileRevision: 4,
                configuration: try RawTCPDeliveryConfiguration(timeoutMilliseconds: 10_000)
            )
        }
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(
            result.failure == .cancelledBeforeSend || result.failure == .cancelledAfterSendAttempt
        )
        XCTAssertTrue(
            result.receipt.state == .cancelledBeforeTransmission ||
                result.receipt.state == .uncertain(bytesAccepted: 0)
        )
    }

    func testFaultOutcomesAreConservativeAndNeverDeviceConfirmed() throws {
        let expected: [(RawTCPAttemptResult, DeliveryState, RawTCPDeliveryFailure?)] = [
            (.completed, .transmitted(bytesAccepted: 4), nil),
            (.connectionFailed, .failedBeforeTransmission, .connectionFailed),
            (.timedOutBeforeSend, .failedBeforeTransmission, .timedOutBeforeSend),
            (.timedOutAfterSendAttempt, .uncertain(bytesAccepted: 0), .timedOutAfterSendAttempt),
            (.cancelledBeforeSend, .cancelledBeforeTransmission, .cancelledBeforeSend),
            (.cancelledAfterSendAttempt, .uncertain(bytesAccepted: 0), .cancelledAfterSendAttempt),
            (.sendFailedAfterAttempt, .uncertain(bytesAccepted: 0), .sendFailedAfterAttempt),
        ]
        for (attempt, state, failure) in expected {
            let result = try RawTCPDelivery.result(for: attempt, payloadByteCount: 4, profileRevision: 7)
            XCTAssertEqual(result.receipt.state, state)
            XCTAssertEqual(result.failure, failure)
            XCTAssertNotEqual(result.receipt.state, .deviceConfirmed)
        }
    }

    func testRealLoopbackBackpressureTimesOutAfterObservedPrefixWithoutRetryPermission() async throws {
        let peer = try LoopbackFaultPeer()
        let prefix = expectation(description: "loopback peer received prefix")
        let finished = expectation(description: "bounded peer finished")
        peer.start(resetAfterPrefix: false, prefixReceived: prefix, finished: finished)
        defer { peer.release() }
        let result = try await RawTCPDelivery.send(
            Data(repeating: 0xA5, count: 16 * 1024 * 1024),
            to: RawTCPEndpoint(host: "127.0.0.1", port: peer.port),
            profileRevision: 7,
            configuration: RawTCPDeliveryConfiguration(timeoutMilliseconds: 1_000))
        peer.release()
        await fulfillment(of: [prefix, finished], timeout: 3)
        XCTAssertNil(peer.failure.value)
        XCTAssertEqual(peer.received.value, Data(repeating: 0xA5, count: 64))
        XCTAssertEqual(result.failure, .timedOutAfterSendAttempt)
        // Zero reported framework bytes does NOT mean nothing reached the peer.
        XCTAssertEqual(result.receipt.state, .uncertain(bytesAccepted: 0))
        XCTAssertNotEqual(result.receipt.state, .deviceConfirmed)
    }

    func testCompletePreparedFormatSurvivesVariableSizedLoopbackReads() async throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 17)
        let bitmap = try MonochromeBitmap(width: 9, height: 4,
            bytes: [0x80, 0x80, 0x00, 0x00, 0xAA, 0x80, 0x00, 0x00])
        let prepared = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: profile)
        let peer = try LoopbackFaultPeer()
        let complete = expectation(description: "complete synthetic prepared stream")
        let finished = expectation(description: "bounded variable-read peer finished")
        peer.start(resetAfterPrefix: false, prefixReceived: complete, finished: finished,
            readGoal: prepared.bytes.count, readSizes: [1, 7, 31, 2, 17])
        defer { peer.release() }
        let result = try await RawTCPDelivery.send(prepared,
            to: RawTCPEndpoint(host: "127.0.0.1", port: peer.port),
            configuration: RawTCPDeliveryConfiguration(timeoutMilliseconds: 2_000))
        peer.release()
        await fulfillment(of: [complete, finished], timeout: 3)
        XCTAssertNil(peer.failure.value)
        XCTAssertEqual(peer.received.value, prepared.bytes)
        XCTAssertTrue(peer.received.value.starts(with: Data("^XA\n".utf8)))
        XCTAssertTrue(peer.received.value.suffix(4) == Data("^XZ\n".utf8))
        XCTAssertEqual(result.receipt.profileSnapshot, prepared.profileSnapshot)
        XCTAssertEqual(result.receipt.state, .transmitted(bytesAccepted: prepared.bytes.count))
        XCTAssertNil(result.failure)
        XCTAssertNotEqual(result.receipt.state, .deviceConfirmed)
    }

    func testRealLoopbackResetAfterPrefixIsUncertainWithoutRetryPermission() async throws {
        let peer = try LoopbackFaultPeer()
        let prefix = expectation(description: "loopback peer received prefix")
        let finished = expectation(description: "bounded reset peer finished")
        peer.start(resetAfterPrefix: true, prefixReceived: prefix, finished: finished)
        defer { peer.release() }
        let result = try await RawTCPDelivery.send(
            Data(repeating: 0xA5, count: 16 * 1024 * 1024),
            to: RawTCPEndpoint(host: "127.0.0.1", port: peer.port),
            profileRevision: 7,
            configuration: RawTCPDeliveryConfiguration(timeoutMilliseconds: 2_000))
        await fulfillment(of: [prefix, finished], timeout: 3)
        XCTAssertNil(peer.failure.value)
        XCTAssertEqual(peer.received.value, Data(repeating: 0xA5, count: 64))
        XCTAssertEqual(result.failure, .sendFailedAfterAttempt)
        XCTAssertEqual(result.receipt.state, .uncertain(bytesAccepted: 0))
        XCTAssertNotEqual(result.receipt.state, .deviceConfirmed)
    }

    func testOwnedNonListeningLoopbackPortFailsBeforeTransmission() async throws {
        // Keep the bound descriptor alive: another test cannot adopt the port
        // between choosing an allegedly unused port and making the connection.
        let reservation = try LoopbackFaultPeer(listening: false)
        let result = try await RawTCPDelivery.send(Data([0xA5]),
            to: RawTCPEndpoint(host: "127.0.0.1", port: reservation.port),
            profileRevision: 7,
            configuration: RawTCPDeliveryConfiguration(timeoutMilliseconds: 1_000))
        // Network.framework can report refusal as failed or keep waiting until
        // the adapter deadline. Both must remain before-send, never uncertain
        // or successful. This does not assume an immediate error callback.
        XCTAssertTrue(result.failure == .connectionFailed || result.failure == .timedOutBeforeSend)
        XCTAssertEqual(result.receipt.state, .failedBeforeTransmission)
        XCTAssertNotEqual(result.receipt.state, .deviceConfirmed)
        withExtendedLifetime(reservation) {}
    }

    private func loopbackListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        return try NWListener(using: parameters, on: .any)
    }

    func testTimeoutQueuedDuringSendAdmissionCannotAuthorizeRetry() async {
        let sendEntered = DispatchSemaphore(value: 0)
        let releaseSend = DispatchSemaphore(value: 0)
        let settled = expectation(description: "attempt settled")
        let result = LockedBox<RawTCPAttemptResult?>(nil)
        let machine = RawTCPAttemptStateMachine(
            startTransport: {},
            send: { _ in
                sendEntered.signal()
                releaseSend.wait()
            },
            cancelTransport: {}
        )
        machine.setCompletion { value in result.value = value; settled.fulfill() }
        machine.start()
        machine.ready()
        XCTAssertEqual(sendEntered.wait(timeout: .now() + 1), .success)

        machine.timedOut()
        releaseSend.signal()
        await fulfillment(of: [settled], timeout: 1)
        XCTAssertEqual(result.value, .timedOutAfterSendAttempt)
    }

    func testCancellationQueuedDuringSendAdmissionIsUncertain() async {
        let sendEntered = DispatchSemaphore(value: 0)
        let releaseSend = DispatchSemaphore(value: 0)
        let settled = expectation(description: "attempt settled")
        let result = LockedBox<RawTCPAttemptResult?>(nil)
        let machine = RawTCPAttemptStateMachine(
            startTransport: {},
            send: { _ in
                sendEntered.signal()
                releaseSend.wait()
            },
            cancelTransport: {}
        )
        machine.setCompletion { value in result.value = value; settled.fulfill() }
        machine.start()
        machine.ready()
        XCTAssertEqual(sendEntered.wait(timeout: .now() + 1), .success)

        machine.cancelled()
        releaseSend.signal()
        await fulfillment(of: [settled], timeout: 1)
        XCTAssertEqual(result.value, .cancelledAfterSendAttempt)
    }

    func testLateCallbacksCannotReviveSettledSendOrCompleteTwice() async throws {
        for outcome in [RawTCPAttemptResult.timedOutAfterSendAttempt,
                        .cancelledAfterSendAttempt, .sendFailedAfterAttempt] {
            let admitted = expectation(description: "send admitted")
            let settled = expectation(description: "first terminal result")
            let drained = expectation(description: "late callback queue drained")
            let observedAfterDrain = LockedBox<RawTCPAttemptResult?>(nil)
            let callback = LockedBox<(@Sendable (Bool) -> Void)?>(nil)
            let completions = LockedBox(0)
            let sends = LockedBox(0)
            let cancellations = LockedBox(0)
            let result = LockedBox<RawTCPAttemptResult?>(nil)
            let machine = RawTCPAttemptStateMachine(
                startTransport: {},
                send: { completion in
                    sends.value += 1
                    callback.value = completion
                    admitted.fulfill()
                },
                cancelTransport: { cancellations.value += 1 })
            machine.setCompletion { value in
                completions.value += 1
                if completions.value == 1 {
                    result.value = value
                    settled.fulfill()
                }
            }
            machine.start()
            machine.ready()
            await fulfillment(of: [admitted], timeout: 1)
            switch outcome {
            case .timedOutAfterSendAttempt: machine.timedOut()
            case .cancelledAfterSendAttempt: machine.cancelled()
            default: machine.connectionEnded()
            }
            await fulfillment(of: [settled], timeout: 1)
            let lateCompletion = try XCTUnwrap(callback.value)
            lateCompletion(true)
            lateCompletion(false)
            machine.connectionEnded()
            machine.ready()
            machine.timedOut()
            machine.cancelled()
            machine.start()
            // Registration is serialized after all late events. It observes
            // the stored result and proves those events have been processed.
            machine.setCompletion { value in
                observedAfterDrain.value = value
                drained.fulfill()
            }
            await fulfillment(of: [drained], timeout: 1)
            XCTAssertEqual(observedAfterDrain.value, outcome)
            XCTAssertEqual(result.value, outcome)
            XCTAssertEqual(completions.value, 1)
            XCTAssertEqual(cancellations.value, 1)
            XCTAssertEqual(sends.value, 1)
        }
    }

    func testCancellationBeforeReadyDoesNotInvokeSend() async {
        let settled = expectation(description: "attempt settled")
        let sendCalls = LockedBox(0)
        let result = LockedBox<RawTCPAttemptResult?>(nil)
        let machine = RawTCPAttemptStateMachine(
            startTransport: {},
            send: { _ in sendCalls.value += 1 },
            cancelTransport: {}
        )
        machine.setCompletion { value in result.value = value; settled.fulfill() }
        machine.start()
        machine.cancelled()
        machine.ready()

        await fulfillment(of: [settled], timeout: 1)
        XCTAssertEqual(result.value, .cancelledBeforeSend)
        XCTAssertEqual(sendCalls.value, 0)
    }

    private func listenerPort(_ listener: NWListener) async throws -> UInt16 {
        for _ in 0..<100 {
            if let port = listener.port?.rawValue, port != 0 { return port }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ListenerError.notReady
    }
}

private enum ListenerError: Error { case notReady }

/// Test-only Darwin peer: bind exclusively to loopback, constrain receive
/// buffering, consume a bounded prefix or complete format, then stall or reset. No printer, DNS,
/// status protocol, unbounded read, or indefinitely living worker is involved.
private final class LoopbackFaultPeer: @unchecked Sendable {
    enum Failure: Error { case setup, accept, read, reset, releaseDeadline }
    let port: UInt16
    let received = LockedBox(Data())
    let failure = LockedBox<Failure?>(nil)
    private let descriptor: Int32
    private let releaseGate = DispatchSemaphore(value: 0)

    init(listening: Bool = true) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.setup }
        var acquired = false
        defer { if !acquired { close(fd) } }
        let flags = fcntl(fd, F_GETFL)
        var capacity: Int32 = 4_096
        guard flags >= 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
              setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &capacity,
                         socklen_t(MemoryLayout.size(ofValue: capacity))) == 0 else {
            throw Failure.setup
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, !listening || listen(fd, 1) == 0 else { throw Failure.setup }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let queried = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard queried == 0, address.sin_addr.s_addr == inet_addr("127.0.0.1"),
              address.sin_port != 0 else { throw Failure.setup }
        port = UInt16(bigEndian: address.sin_port)
        descriptor = fd
        acquired = true
    }

    deinit { close(descriptor) }

    func release() { releaseGate.signal() }

    func start(resetAfterPrefix: Bool, prefixReceived: XCTestExpectation,
               finished: XCTestExpectation, readGoal: Int = 64, readSizes: [Int] = [64]) {
        precondition((1...1_048_576).contains(readGoal))
        precondition(!readSizes.isEmpty && readSizes.allSatisfy { (1...4_096).contains($0) })
        DispatchQueue.global().async { [self] in
            var notified = false
            defer {
                if !notified { prefixReceived.fulfill() }
                finished.fulfill()
            }
            do {
                let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
                try waitReadable(descriptor, deadline: deadline)
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else { throw Failure.accept }
                defer { close(client) }
                let flags = fcntl(client, F_GETFL)
                guard flags >= 0, fcntl(client, F_SETFD, FD_CLOEXEC) == 0,
                      fcntl(client, F_SETFL, flags | O_NONBLOCK) == 0 else {
                    throw Failure.setup
                }
                var bytes = Data()
                var readIndex = 0
                while bytes.count < readGoal {
                    try waitReadable(client, deadline: deadline)
                    let size = min(readSizes[readIndex % readSizes.count], readGoal - bytes.count)
                    var buffer = [UInt8](repeating: 0, count: size)
                    let count = buffer.withUnsafeMutableBytes { recv(client, $0.baseAddress, $0.count, 0) }
                    if count < 0, errno == EAGAIN || errno == EINTR { continue }
                    guard count > 0 else { throw Failure.read }
                    bytes.append(contentsOf: buffer.prefix(count))
                    readIndex += 1
                }
                received.value = bytes
                notified = true
                prefixReceived.fulfill()
                if resetAfterPrefix {
                    var option = linger(l_onoff: 1, l_linger: 0)
                    guard setsockopt(client, SOL_SOCKET, SO_LINGER, &option,
                                    socklen_t(MemoryLayout.size(ofValue: option))) == 0 else {
                        throw Failure.reset
                    }
                } else if releaseGate.wait(timeout: .now() + 5) != .success {
                    throw Failure.releaseDeadline
                }
            } catch { failure.value = (error as? Failure) ?? .setup }
        }
    }

    private func waitReadable(_ fd: Int32, deadline: UInt64) throws {
        while DispatchTime.now().uptimeNanoseconds < deadline {
            var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let result = poll(&item, 1, 50)
            if result > 0 { return }
            if result < 0, errno != EINTR { throw Failure.read }
        }
        throw Failure.read
    }
}

private final class ReceivedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    var value: Data? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
