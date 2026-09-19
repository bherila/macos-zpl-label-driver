import Foundation
import LabelCore

/// Scoped evidence that the executor holds both the artifact (job) lease and the
/// physical-device lease for the whole provider call, including every bounded
/// status wait. A Swift actor or any in-process object is not a cross-process
/// device lock, so ownership is carried by kernel `flock` descriptors owned by
/// `BoundedFinishingDelivery`. Providers may observe it and must never release,
/// re-acquire, copy or outlive it.
public struct FinishingDeviceOwnership: Sendable {
    public let coordinationID: PhysicalDeviceCoordinationID
    let device: PhysicalDeviceLease
    let artifact: PhysicalDeviceLease
    init(coordinationID: PhysicalDeviceCoordinationID, device: PhysicalDeviceLease, artifact: PhysicalDeviceLease) {
        self.coordinationID = coordinationID; self.device = device; self.artifact = artifact
    }
    /// Check before and after every bounded wait. A previous successful call is
    /// never evidence that ownership still covers the next one.
    public var isHeld: Bool { device.isHeld && artifact.isHeld }
}

/// One bounded readiness answer before any file is attempted. A refusal here is
/// the only proven not-sent state this project can currently produce.
public enum FinishingDeliveryReadiness: Equatable, Sendable {
    case ready, refusedBeforeAnyBytes
}

/// Publication of exactly one complete finishing file. Files are never split
/// into raw transport frames by this layer and never concatenated together.
public enum FinishingFilePublication: Equatable, Sendable {
    /// The provider observed that the exact complete file was published.
    case published
    /// Every byte left this process but publication cannot be distinguished from
    /// a truncated or lost file. This is uncertainty, never success or failure.
    case ambiguous
}

/// Distinct status facts. `unknown` is never false, zero, supported or completed,
/// and `notSatisfied` is a real negative observation rather than an absent one.
public enum FinishingStatusReading: Equatable, Sendable {
    case unknown, notSatisfied, satisfied
}

/// Bounded file/status provider contract. Implementations in this project are
/// inert: no transport, socket, `lpr`, network or device command is performed,
/// and no implementation may report physical completion. The executor holds the
/// leases; an implementation receives only the scoped ownership witness.
public protocol FinishingDeliveryProvider: AnyObject {
    /// Exactly one bounded readiness check, before the durable send-attempt
    /// record and before any file is offered.
    func prepare(ownership: FinishingDeviceOwnership) throws -> FinishingDeliveryReadiness

    /// Offer one complete file. Report cumulative accepted counts through
    /// `accepted` as they are observed; it must not be called after returning.
    /// A short final count is a partial transmission, which is uncertain.
    func transmit(stepIndex: Int, file: FinishingOutputStep, bytes: Data,
                  ownership: FinishingDeviceOwnership,
                  accepted: (Int) throws -> Void) throws -> FinishingFilePublication

    /// Bounded wait for one correlated status requirement while ownership is
    /// held. Returning `.satisfied` without an actual correlated observation
    /// would be an invented completion and is a provider defect.
    func awaitStatus(stepIndex: Int, requirement: FinishingOutputStep,
                     ownership: FinishingDeviceOwnership) throws -> FinishingStatusReading
}

/// Terminal delivery observation. Every case is a distinct durable state; none of
/// them is physical-completion evidence and only one authorizes a bounded retry.
public enum FinishingDeliveryDisposition: Equatable, Sendable {
    /// Every framed step was satisfied by the provider's own observations. For an
    /// inert provider this is synthetic satisfaction, not a printed label.
    case allStepsSatisfied
    /// Refused before any byte was offered: the single proven not-sent state.
    case failedBeforeAttempt
    case cancelledBeforeAttempt
    case timedOutBeforeAttempt
    case cancelledAfterAttempt(step: Int)
    case timedOutAfterAttempt(step: Int)
    case partialTransmission(step: Int, accepted: Int, expected: Int)
    case ambiguousPublication(step: Int)
    case statusUnknown(step: Int)
    case statusNotSatisfied(step: Int)
    /// The shared coordination lease stopped covering the operation, so another
    /// owner may have interleaved on the same physical device.
    case ownershipLost(step: Int)
    case providerFailedAfterAttempt(step: Int)

    public var isUncertain: Bool {
        switch self {
        case .allStepsSatisfied, .failedBeforeAttempt, .cancelledBeforeAttempt, .timedOutBeforeAttempt: false
        default: true
        }
    }
    /// Synthetic satisfaction of every step is not a printed label, a performed
    /// cut or a removed label. No path in this package converts it into device
    /// confirmation, and no accepted sender or device status exists yet.
    public var establishesPhysicalCompletion: Bool { false }
    /// Only a proven pre-attempt refusal. Cancellation, timeout, partial
    /// transmission, ambiguity, unknown status and the absence of any durable
    /// record never authorize an automatic retry.
    public var authorizesBoundedRetry: Bool { self == .failedBeforeAttempt }
}
