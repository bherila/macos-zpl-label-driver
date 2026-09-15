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
    case cancelledBeforeSend
    case cancelledAfterSendAttempt
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
    /// Preferred typed handoff: payload bytes and the profile snapshot cannot
    /// be paired with different revisions by this adapter.
    public static func send(
        _ preparedLabel: PreparedLabel,
        to endpoint: RawTCPEndpoint,
        configuration: RawTCPDeliveryConfiguration = .default
    ) async throws -> RawTCPDeliveryResult {
        let tracker = try DeliveryTracker(preparedLabel: preparedLabel)
        return try await send(
            payload: preparedLabel.bytes,
            to: endpoint,
            tracker: tracker,
            configuration: configuration
        )
    }

    /// Legacy revision-only handoff. New product paths should pass a
    /// `PreparedLabel` so the receipt has an immutable configuration snapshot.
    public static func send(
        _ payload: Data,
        to endpoint: RawTCPEndpoint,
        profileRevision: Int,
        configuration: RawTCPDeliveryConfiguration = .default
    ) async throws -> RawTCPDeliveryResult {
        let tracker = try DeliveryTracker(expectedBytes: payload.count, profileRevision: profileRevision)
        return try await send(payload: payload, to: endpoint, tracker: tracker, configuration: configuration)
    }

    private static func send(
        payload: Data,
        to endpoint: RawTCPEndpoint,
        tracker: DeliveryTracker,
        configuration: RawTCPDeliveryConfiguration
    ) async throws -> RawTCPDeliveryResult {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            throw RawTCPEndpoint.ValidationError.invalidPort
        }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let attempt = await ConnectionAttempt(connection: connection, payload: payload, timeoutMilliseconds: configuration.timeoutMilliseconds).run()

        return try result(for: attempt, tracker: tracker)
    }

    /// Kept separate from Network.framework callbacks so every observable
    /// failure boundary has a deterministic regression vector. This is not a
    /// device receipt: `completed` still means only local stream acceptance.
    static func result(
        for attempt: RawTCPAttemptResult,
        payloadByteCount: Int,
        profileRevision: Int
    ) throws -> RawTCPDeliveryResult {
        try result(
            for: attempt,
            tracker: DeliveryTracker(expectedBytes: payloadByteCount, profileRevision: profileRevision)
        )
    }

    /// Testable typed result seam. This preserves a prepared-label snapshot
    /// through every TCP completion/failure state without inventing a device
    /// receipt.
    static func result(
        for attempt: RawTCPAttemptResult,
        preparedLabel: PreparedLabel
    ) throws -> RawTCPDeliveryResult {
        try result(for: attempt, tracker: DeliveryTracker(preparedLabel: preparedLabel))
    }

    private static func result(
        for attempt: RawTCPAttemptResult,
        tracker initialTracker: DeliveryTracker
    ) throws -> RawTCPDeliveryResult {
        var tracker = initialTracker
        try tracker.prepared()
        try tracker.waiting()
        switch attempt {
        case .completed:
            try tracker.acceptedByTransport(byteCount: tracker.receipt.expectedBytes)
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
        case .cancelledBeforeSend:
            try tracker.failedOrCancelledBeforeTransmission(cancelled: true)
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: .cancelledBeforeSend)
        case .cancelledAfterSendAttempt:
            try tracker.transportAttemptBecameAmbiguous()
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: .cancelledAfterSendAttempt)
        case .sendFailedAfterAttempt:
            try tracker.transportAttemptBecameAmbiguous()
            return RawTCPDeliveryResult(receipt: tracker.receipt, failure: .sendFailedAfterAttempt)
        }
    }
}

enum RawTCPAttemptResult: Equatable, Sendable {
    case completed
    case connectionFailed
    case timedOutBeforeSend
    case timedOutAfterSendAttempt
    case cancelledBeforeSend
    case cancelledAfterSendAttempt
    case sendFailedAfterAttempt
}

/// Serializes every external attempt boundary. The send operation is invoked on
/// this machine's queue immediately after admission, so timeout or cancellation
/// cannot settle a stale pre-send classification between admission and send.
/// This is not a printer ownership mechanism.
final class RawTCPAttemptStateMachine: @unchecked Sendable {
    typealias Completion = @Sendable (RawTCPAttemptResult) -> Void
    typealias SendOperation = @Sendable (@escaping @Sendable (Bool) -> Void) -> Void

    private enum Phase { case idle, waiting, sending, settled }

    private let queue: DispatchQueue
    private let startTransport: @Sendable () -> Void
    private let send: SendOperation
    private let cancelTransport: @Sendable () -> Void
    private var phase: Phase = .idle
    private var result: RawTCPAttemptResult?
    private var completion: Completion?

    init(
        queueLabel: String = "org.bherila.label-driver.raw-tcp.attempt",
        startTransport: @escaping @Sendable () -> Void,
        send: @escaping SendOperation,
        cancelTransport: @escaping @Sendable () -> Void
    ) {
        queue = DispatchQueue(label: queueLabel)
        self.startTransport = startTransport
        self.send = send
        self.cancelTransport = cancelTransport
    }

    func setCompletion(_ completion: @escaping Completion) {
        queue.async {
            if let result = self.result { completion(result) }
            else { self.completion = completion }
        }
    }

    func start() {
        queue.async {
            guard self.phase == .idle else { return }
            self.phase = .waiting
            self.startTransport()
        }
    }

    func ready() {
        queue.async {
            guard self.phase == .waiting else { return }
            self.phase = .sending
            self.send { [weak self] succeeded in self?.sendCompleted(succeeded: succeeded) }
        }
    }

    func connectionEnded() { queue.async { self.settleForConnectionEnd() } }
    func timedOut() { queue.async { self.settleForTimeout() } }
    func cancelled() { queue.async { self.settleForCancellation() } }

    private func sendCompleted(succeeded: Bool) {
        queue.async {
            guard self.phase == .sending else { return }
            self.settle(succeeded ? .completed : .sendFailedAfterAttempt)
        }
    }

    private func settleForConnectionEnd() {
        switch phase {
        case .idle, .waiting: settle(.connectionFailed)
        case .sending: settle(.sendFailedAfterAttempt)
        case .settled: break
        }
    }

    private func settleForTimeout() {
        switch phase {
        case .idle, .waiting: settle(.timedOutBeforeSend)
        case .sending: settle(.timedOutAfterSendAttempt)
        case .settled: break
        }
    }

    private func settleForCancellation() {
        switch phase {
        case .idle, .waiting: settle(.cancelledBeforeSend)
        case .sending: settle(.cancelledAfterSendAttempt)
        case .settled: break
        }
    }

    private func settle(_ next: RawTCPAttemptResult) {
        guard phase != .settled else { return }
        phase = .settled
        result = next
        let completion = self.completion
        self.completion = nil
        cancelTransport()
        completion?(next)
    }
}

private final class ConnectionAttempt: @unchecked Sendable {
    private let connection: NWConnection
    private let timeoutMilliseconds: Int
    private let machine: RawTCPAttemptStateMachine

    init(connection: NWConnection, payload: Data, timeoutMilliseconds: Int) {
        self.connection = connection
        self.timeoutMilliseconds = timeoutMilliseconds
        let callbackQueue = DispatchQueue(label: "org.bherila.label-driver.raw-tcp.network")
        machine = RawTCPAttemptStateMachine(
            startTransport: { connection.start(queue: callbackQueue) },
            send: { completion in
                connection.send(content: payload, completion: .contentProcessed { error in
                    completion(error == nil)
                })
            },
            cancelTransport: { connection.cancel() }
        )
        connection.stateUpdateHandler = { [weak machine] state in
            switch state {
            case .ready: machine?.ready()
            case .failed, .cancelled: machine?.connectionEnded()
            default: break
            }
        }
    }

    func run() async -> RawTCPAttemptResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                machine.setCompletion { continuation.resume(returning: $0) }
                machine.start()
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + .milliseconds(timeoutMilliseconds)
                ) { [weak machine] in
                    machine?.timedOut()
                }
            }
        } onCancel: { [machine] in
            machine.cancelled()
        }
    }
}
