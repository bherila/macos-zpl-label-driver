import Foundation
import LabelCore

/// Finite discard-only execution. Synthetic status is never hardware evidence.
/// The supplied coordination domain is a simulator input, not accepted-device
/// admission. Production must derive it from an immutable accepted job ticket.
public enum InertFinishingDelivery {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidScenario, deviceBusy, leaseUnavailable
    }
    public struct Scenario: Equatable, Sendable {
        public let maximumChunkBytes: Int
        public let stopBeforeStep: Int?
        public let failAfterAttemptAtStep: Int?
        public let unknownStatusAtStep: Int?
        public init(maximumChunkBytes: Int = 64 * 1024, stopBeforeStep: Int? = nil,
                    failAfterAttemptAtStep: Int? = nil, unknownStatusAtStep: Int? = nil) {
            self.maximumChunkBytes = maximumChunkBytes; self.stopBeforeStep = stopBeforeStep
            self.failAfterAttemptAtStep = failAfterAttemptAtStep; self.unknownStatusAtStep = unknownStatusAtStep
        }
    }
    enum Event: Equatable {
        case fileAttempt(Int), bytesDiscarded(Int, Int), statusWait(Int)
    }

    public static func run(output: FinishingFramedOutput, coordinationID: PhysicalDeviceCoordinationID,
                           leaseDirectory: URL, scenario: Scenario = .init(),
                           deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                           cancellation: OfflineRenderWorkerCancellation = .init()) throws -> FinishingDeliveryTracker {
        try run(output: output, coordinationID: coordinationID, leaseDirectory: leaseDirectory,
                scenario: scenario, deadlineSeconds: deadlineSeconds, cancellation: cancellation, observe: { _ in })
    }

    /// Synchronous internal test seam. It performs no transport or device query.
    static func run(output: FinishingFramedOutput, coordinationID: PhysicalDeviceCoordinationID,
                    leaseDirectory: URL, scenario: Scenario, deadlineSeconds: Double,
                    cancellation: OfflineRenderWorkerCancellation,
                    observe: (Event) throws -> Void) throws -> FinishingDeliveryTracker {
        guard (1...FinishingFramedOutput.maximumBytes).contains(scenario.maximumChunkBytes),
              deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else { throw Error.invalidScenario }
        for index in [scenario.stopBeforeStep, scenario.failAfterAttemptAtStep, scenario.unknownStatusAtStep].compactMap({ $0 }) {
            guard output.steps.indices.contains(index) else { throw Error.invalidScenario }
        }
        if let index = scenario.failAfterAttemptAtStep {
            switch output.steps[index] {
            case .formatFile, .delayedCutFile: break
            default: throw Error.invalidScenario
            }
        }
        if let index = scenario.unknownStatusAtStep {
            switch output.steps[index] {
            case .formatFile, .delayedCutFile: throw Error.invalidScenario
            default: break
            }
        }
        var tracker = FinishingDeliveryTracker(output: output)
        let started = DispatchTime.now().uptimeNanoseconds
        func exhausted() -> Bool {
            cancellation.isCancelled || Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000 >= deadlineSeconds
        }
        if exhausted() { try tracker.stop(cancelled: cancellation.isCancelled); return tracker }
        let lease: PhysicalDeviceLease
        do {
            lease = try PhysicalDeviceLease(acquiring: .init(coordinationID: coordinationID), inExistingDirectory: leaseDirectory)
        } catch PhysicalDeviceLeaseError.alreadyHeld { throw Error.deviceBusy }
        catch { throw Error.leaseUnavailable }
        defer { lease.release() }
        while let step = tracker.nextStep {
            let index = tracker.nextStepIndex
            if exhausted() || scenario.stopBeforeStep == index {
                try tracker.stop(cancelled: cancellation.isCancelled); return tracker
            }
            switch step {
            case let .formatFile(_, bytes), let .delayedCutFile(_, bytes):
                try tracker.beginFile(stepIndex: index, bytes: bytes)
                try observe(.fileAttempt(index))
                if exhausted() || scenario.failAfterAttemptAtStep == index {
                    try tracker.stop(cancelled: cancellation.isCancelled); return tracker
                }
                var accepted = 0
                while accepted < bytes.count {
                    if exhausted() { try tracker.stop(cancelled: cancellation.isCancelled); return tracker }
                    accepted += min(scenario.maximumChunkBytes, bytes.count - accepted)
                    // Only account for discarded bytes; there is no output sink.
                    try tracker.acceptedByTransport(byteCount: accepted)
                    try observe(.bytesDiscarded(index, accepted))
                }
                if exhausted() { try tracker.stop(cancelled: cancellation.isCancelled); return tracker }
                try tracker.fileFinished()
            default:
                try observe(.statusWait(index))
                if exhausted() || scenario.unknownStatusAtStep == index {
                    _ = try tracker.observeStatus(stepIndex: index, step: step, observation: .unknown)
                    try tracker.stop(cancelled: cancellation.isCancelled); return tracker
                }
                // Explicit synthetic status, never a physical printer receipt.
                _ = try tracker.observeStatus(stepIndex: index, step: step, observation: .confirmed)
            }
        }
        return tracker
    }
}
