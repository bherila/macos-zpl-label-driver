import Foundation

/// In-memory accounting for a framed candidate; not device-write authority or
/// a hardware receipt. A future qualified adapter must verify correlated status
/// and hold the physical-device lease through every file and status step.
public struct FinishingDeliveryTracker: Sendable {
    public enum State: Equatable, Sendable {
        case ready, sending, awaitingStatus, confirmed
        case failedBeforeAttempt, cancelledBeforeAttempt, uncertain
    }
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidTransition, stepMismatch, payloadMismatch, invalidByteCount
    }
    public enum StatusObservation: Equatable, Sendable {
        case unknown, notSatisfied, confirmed
    }
    public let output: FinishingFramedOutput
    public private(set) var state: State = .ready
    public private(set) var nextStepIndex = 0
    public private(set) var bytesAccepted = 0
    public private(set) var attemptedAnyFile = false
    /// Cumulative accepted count for the file currently being offered. A short
    /// final value is a partial transmission, which is uncertain, not a failure
    /// before accepted bytes.
    public private(set) var acceptedBytesInCurrentFile = 0

    public init(output: FinishingFramedOutput) { self.output = output }

    public var nextStep: FinishingOutputStep? {
        guard nextStepIndex < output.steps.count else { return nil }
        return output.steps[nextStepIndex]
    }
    public var mayRetryAutomatically: Bool { state == .failedBeforeAttempt }

    /// Call before the external send API. An unsuccessful or zero-byte attempt
    /// cannot subsequently be reclassified as a safe pre-transmission failure.
    public mutating func beginFile(stepIndex: Int, bytes: Data) throws {
        guard state == .ready else { throw Error.invalidTransition }
        guard stepIndex == nextStepIndex else { throw Error.stepMismatch }
        guard let expected = fileBytes(nextStep) else { throw Error.invalidTransition }
        guard expected == bytes else { throw Error.payloadMismatch }
        attemptedAnyFile = true
        acceptedBytesInCurrentFile = 0
        state = .sending
    }

    /// Cumulative accepted count for the current complete file. Invalid or
    /// decreasing accounting after an attempt is itself ambiguous, not retryable.
    public mutating func acceptedByTransport(byteCount: Int) throws {
        guard state == .sending, let expected = fileBytes(nextStep) else {
            throw Error.invalidTransition
        }
        guard byteCount >= acceptedBytesInCurrentFile, byteCount <= expected.count else {
            state = .uncertain
            throw Error.invalidByteCount
        }
        bytesAccepted += byteCount - acceptedBytesInCurrentFile
        acceptedBytesInCurrentFile = byteCount
    }

    public mutating func fileFinished() throws {
        guard state == .sending, let expected = fileBytes(nextStep),
              acceptedBytesInCurrentFile == expected.count else { throw Error.invalidTransition }
        advance()
    }

    /// The caller must correlate a supported status observation to the exact
    /// requested step. Unknown/unsatisfied observations do not advance anything.
    @discardableResult
    public mutating func observeStatus(stepIndex: Int, step: FinishingOutputStep,
                                      observation: StatusObservation) throws -> Bool {
        guard state == .awaitingStatus else { throw Error.invalidTransition }
        guard stepIndex == nextStepIndex, step == nextStep else { throw Error.stepMismatch }
        guard observation == .confirmed else { return false }
        advance()
        return true
    }

    /// Timeout, cancellation, disconnect or status-provider failure. After any
    /// attempted file, even while waiting for removal, completion is uncertain.
    public mutating func stop(cancelled: Bool) throws {
        guard state == .ready || state == .sending || state == .awaitingStatus else {
            throw Error.invalidTransition
        }
        state = attemptedAnyFile ? .uncertain : (cancelled ? .cancelledBeforeAttempt : .failedBeforeAttempt)
    }

    private mutating func advance() {
        nextStepIndex += 1
        acceptedBytesInCurrentFile = 0
        guard let step = nextStep else { state = .confirmed; return }
        state = fileBytes(step) == nil ? .awaitingStatus : .ready
    }
    private func fileBytes(_ step: FinishingOutputStep?) -> Data? {
        switch step {
        case let .formatFile(_, bytes), let .delayedCutFile(_, bytes): return bytes
        default: return nil
        }
    }
}
