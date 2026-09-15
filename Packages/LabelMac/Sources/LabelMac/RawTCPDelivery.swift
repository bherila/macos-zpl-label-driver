@preconcurrency import Foundation
@preconcurrency import Network
import LabelCore

/// An explicitly configured raw-TCP target. This is deliberately not a
/// discovery API: callers must supply one bounded host and port, and neither
/// value is suitable for command construction or general logging.
public struct RawTCPEndpoint: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidHost
        case invalidPort
    }

    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) throws {
        guard !host.isEmpty, host.count <= 253,
              host.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0) })
        else { throw ValidationError.invalidHost }
        guard port != 0 else { throw ValidationError.invalidPort }
        self.host = host
        self.port = port
    }
}

public struct RawTCPDeliveryConfiguration: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable { case invalidTimeout }

    public let timeoutMilliseconds: Int

    public static let `default` = RawTCPDeliveryConfiguration(uncheckedTimeoutMilliseconds: 10_000)

    public init(timeoutMilliseconds: Int = 10_000) throws {
        guard (1...120_000).contains(timeoutMilliseconds) else { throw ValidationError.invalidTimeout }
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    private init(uncheckedTimeoutMilliseconds: Int) {
        timeoutMilliseconds = uncheckedTimeoutMilliseconds
    }
}

public enum RawTCPDeliveryFailure: Error, Equatable, Sendable {
    case connectionFailed
    case timedOutBeforeSend
    case timedOutAfterSendAttempt
    case sendFailedAfterAttempt
}

/// Result always carries the honest delivery state. In particular, an error
/// after `NWConnection.send` was invoked is uncertain even if the framework
/// did not expose a byte count: raw TCP has no device receipt or record frame.
public struct RawTCPDeliveryResult: Equatable, Sendable {
    public let receipt: DeliveryReceipt
    public let failure: RawTCPDeliveryFailure?
}

/// Sends one prepared byte stream on one explicitly configured raw-TCP
/// connection. Network.framework owns stream segmentation; this type neither
/// scans addresses nor interprets responses as a printer confirmation.
public enum RawTCPDelivery {
    public static func send(
        _ payload: Data,
        to endpoint: RawTCPEndpoint,
        profileRevision: Int,
        configuration: RawTCPDeliveryConfiguration = .default
    ) async throws -> RawTCPDeliveryResult {
        _ = try DeliveryTracker(expectedBytes: payload.count, profileRevision: profileRevision)

        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            throw RawTCPEndpoint.ValidationError.invalidPort
        }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let attempt = await ConnectionAttempt(connection: connection, payload: payload, timeoutMilliseconds: configuration.timeoutMilliseconds).run()

        return try result(for: attempt, payloadByteCount: payload.count, profileRevision: profileRevision)
    }

    /// Kept separate from Network.framework callbacks so every observable
    /// failure boundary has a deterministic regression vector. This is not a
    /// device receipt: `completed` still means only local stream acceptance.
    static func result(
        for attempt: RawTCPAttemptResult,
        payloadByteCount: Int,
        profileRevision: Int
    ) throws -> RawTCPDeliveryResult {
        var tracker = try DeliveryTracker(expectedBytes: payloadByteCount, profileRevision: profileRevision)
        try tracker.prepared()
        try tracker.waiting()
        switch attempt {
        case .completed:
            try tracker.acceptedByTransport(byteCount: payloadByteCount)
            try tracker.transportFinished()
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: nil)
        case .connectionFailed:
            try tracker.failedOrCancelledBeforeTransmission(cancelled: false)
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: .connectionFailed)
        case .timedOutBeforeSend:
            try tracker.failedOrCancelledBeforeTransmission(cancelled: false)
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: .timedOutBeforeSend)
        case .timedOutAfterSendAttempt:
            try tracker.transportAttemptBecameAmbiguous()
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: .timedOutAfterSendAttempt)
        case .sendFailedAfterAttempt:
            try tracker.transportAttemptBecameAmbiguous()
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: .sendFailedAfterAttempt)
        }
    }
}

enum RawTCPAttemptResult: Sendable {
    case completed
    case connectionFailed
    case timedOutBeforeSend
    case timedOutAfterSendAttempt
    case sendFailedAfterAttempt
}

/// The lock only settles callback races within one Network.framework attempt;
/// it is not a printer ownership mechanism.
private final class ConnectionAttempt: @unchecked Sendable {
    private let connection: NWConnection
    private let payload: Data
    private let timeoutMilliseconds: Int
    private let lock = NSLock()
    private var result: RawTCPAttemptResult?
    private var continuation: CheckedContinuation<RawTCPAttemptResult, Never>?
    private var sendWasAttempted = false

    init(connection: NWConnection, payload: Data, timeoutMilliseconds: Int) {
        self.connection = connection
        self.payload = payload
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    func run() async -> RawTCPAttemptResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            connection.stateUpdateHandler = { [weak self] state in self?.received(state) }
            connection.start(queue: DispatchQueue(label: "org.bherila.label-driver.raw-tcp"))
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds)) { [weak self] in
                self?.timedOut()
            }
        }
    }

    private func received(_ state: NWConnection.State) {
        switch state {
        case .ready:
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            sendWasAttempted = true
            lock.unlock()
            connection.send(content: payload, completion: .contentProcessed { [weak self] error in
                self?.completedSend(error: error)
            })
        case .failed, .cancelled:
            finish(hasSendAttempted() ? .sendFailedAfterAttempt : .connectionFailed)
        default:
            break
        }
    }

    private func completedSend(error: NWError?) {
        finish(error == nil ? .completed : .sendFailedAfterAttempt)
    }

    private func timedOut() {
        finish(hasSendAttempted() ? .timedOutAfterSendAttempt : .timedOutBeforeSend)
    }

    private func hasSendAttempted() -> Bool {
        lock.withLock { sendWasAttempted }
    }

    private func finish(_ next: RawTCPAttemptResult) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = next
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        connection.cancel()
        continuation?.resume(returning: next)
    }
}
