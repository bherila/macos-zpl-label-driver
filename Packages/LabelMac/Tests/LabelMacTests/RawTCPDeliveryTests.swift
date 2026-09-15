@preconcurrency import Network
import XCTest
import LabelCore
@testable import LabelMac

final class RawTCPDeliveryTests: XCTestCase {
    func testEndpointAndTimeoutRejectUnsafeValues() {
        XCTAssertThrowsError(try RawTCPEndpoint(host: "", port: 9100))
        XCTAssertThrowsError(try RawTCPEndpoint(host: "printer\nother", port: 9100))
        XCTAssertThrowsError(try RawTCPEndpoint(host: "127.0.0.1", port: 0))
        XCTAssertThrowsError(try RawTCPDeliveryConfiguration(timeoutMilliseconds: 0))
        XCTAssertThrowsError(try RawTCPDeliveryConfiguration(timeoutMilliseconds: 120_001))
    }

    func testLoopbackDeliveryReportsOnlyLocalTransmission() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
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

    func testFaultOutcomesAreConservativeAndNeverDeviceConfirmed() throws {
        let expected: [(RawTCPAttemptResult, DeliveryState, RawTCPDeliveryFailure?)] = [
            (.completed, .transmitted(bytesAccepted: 4), nil),
            (.connectionFailed, .failedBeforeTransmission, .connectionFailed),
            (.timedOutBeforeSend, .failedBeforeTransmission, .timedOutBeforeSend),
            (.timedOutAfterSendAttempt, .uncertain(bytesAccepted: 0), .timedOutAfterSendAttempt),
            (.sendFailedAfterAttempt, .uncertain(bytesAccepted: 0), .sendFailedAfterAttempt),
        ]
        for (attempt, state, failure) in expected {
            let result = try RawTCPDelivery.result(for: attempt, payloadByteCount: 4, profileRevision: 7)
            XCTAssertEqual(result.receipt.state, state)
            XCTAssertEqual(result.failure, failure)
            XCTAssertNotEqual(result.receipt.state, .deviceConfirmed)
        }
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

private final class ReceivedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    var value: Data? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
