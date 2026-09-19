import Foundation

/// Discard-only file/status provider for offline validation. It opens no socket,
/// performs no transport, never invokes `lpr` and keeps no output sink: complete
/// files are counted and dropped. Every reading is scripted simulator input and
/// is never a device receipt, so `.satisfied` here is synthetic satisfaction of a
/// requirement rather than evidence that a label printed, was cut or was taken.
public final class InertFinishingDeliveryProvider: FinishingDeliveryProvider {
    public struct Script: Equatable, Sendable {
        public var maximumChunkBytes: Int
        public var refuseBeforeAnyBytes: Bool
        public var stopAcceptingAtStep: Int?
        public var acceptedBytesBeforeStopping: Int
        public var ambiguousPublicationAtStep: Int?
        public var unknownStatusAtStep: Int?
        public var notSatisfiedStatusAtStep: Int?
        public var failAtStep: Int?
        public var statusWaitSeconds: Double
        public init(maximumChunkBytes: Int = 64 * 1024, refuseBeforeAnyBytes: Bool = false,
                    stopAcceptingAtStep: Int? = nil, acceptedBytesBeforeStopping: Int = 0,
                    ambiguousPublicationAtStep: Int? = nil, unknownStatusAtStep: Int? = nil,
                    notSatisfiedStatusAtStep: Int? = nil, failAtStep: Int? = nil,
                    statusWaitSeconds: Double = 0) {
            self.maximumChunkBytes = maximumChunkBytes; self.refuseBeforeAnyBytes = refuseBeforeAnyBytes
            self.stopAcceptingAtStep = stopAcceptingAtStep
            self.acceptedBytesBeforeStopping = acceptedBytesBeforeStopping
            self.ambiguousPublicationAtStep = ambiguousPublicationAtStep
            self.unknownStatusAtStep = unknownStatusAtStep
            self.notSatisfiedStatusAtStep = notSatisfiedStatusAtStep
            self.failAtStep = failAtStep; self.statusWaitSeconds = statusWaitSeconds
        }
    }
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidScript, ownershipNotHeld, scriptedProviderFailure
    }
    public enum Event: Equatable, Sendable {
        case prepared, offered(step: Int, discarded: Int), waited(step: Int)
    }
    public static let maximumStatusWaitSeconds: Double = 1
    public let script: Script
    public private(set) var events: [Event] = []
    public private(set) var discardedBytes = 0

    public init(script: Script = .init()) throws {
        guard (1...FinishingFramedOutput.maximumBytes).contains(script.maximumChunkBytes),
              script.acceptedBytesBeforeStopping >= 0, script.statusWaitSeconds.isFinite,
              script.statusWaitSeconds >= 0, script.statusWaitSeconds <= Self.maximumStatusWaitSeconds,
              [script.stopAcceptingAtStep, script.ambiguousPublicationAtStep, script.unknownStatusAtStep,
               script.notSatisfiedStatusAtStep, script.failAtStep].compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
            throw Error.invalidScript
        }
        self.script = script
    }

    public func prepare(ownership: FinishingDeviceOwnership) throws -> FinishingDeliveryReadiness {
        guard ownership.isHeld else { throw Error.ownershipNotHeld }
        events.append(.prepared)
        return script.refuseBeforeAnyBytes ? .refusedBeforeAnyBytes : .ready
    }

    public func transmit(stepIndex: Int, file: FinishingOutputStep, bytes: Data,
                         ownership: FinishingDeviceOwnership,
                         accepted: (Int) throws -> Void) throws -> FinishingFilePublication {
        guard ownership.isHeld else { throw Error.ownershipNotHeld }
        if script.failAtStep == stepIndex { throw Error.scriptedProviderFailure }
        let limit = script.stopAcceptingAtStep == stepIndex
            ? min(script.acceptedBytesBeforeStopping, bytes.count) : bytes.count
        var total = 0
        while total < limit {
            guard ownership.isHeld else { throw Error.ownershipNotHeld }
            let chunk = min(script.maximumChunkBytes, limit - total)
            // Counted and dropped. There is deliberately no output destination.
            total += chunk; discardedBytes += chunk
            try accepted(total)
        }
        events.append(.offered(step: stepIndex, discarded: total))
        guard ownership.isHeld else { throw Error.ownershipNotHeld }
        // A short file cannot claim publication, and an explicitly scripted
        // ambiguous publication is neither success nor a safe not-sent state.
        if total < bytes.count || script.ambiguousPublicationAtStep == stepIndex { return .ambiguous }
        return .published
    }

    public func awaitStatus(stepIndex: Int, requirement: FinishingOutputStep,
                            ownership: FinishingDeviceOwnership) throws -> FinishingStatusReading {
        guard ownership.isHeld else { throw Error.ownershipNotHeld }
        if script.failAtStep == stepIndex { throw Error.scriptedProviderFailure }
        // Finite simulated wait; ownership must still cover the whole of it.
        if script.statusWaitSeconds > 0 { Thread.sleep(forTimeInterval: script.statusWaitSeconds) }
        events.append(.waited(step: stepIndex))
        guard ownership.isHeld else { throw Error.ownershipNotHeld }
        if script.unknownStatusAtStep == stepIndex { return .unknown }
        if script.notSatisfiedStatusAtStep == stepIndex { return .notSatisfied }
        return .satisfied
    }
}
