import CryptoKit
import Foundation
import LabelCore

/// Bounded execution of one immutable framed artifact through a file/status
/// provider. The artifact (job) lease and the physical-device lease are both
/// acquired before any provider call and held through every complete file and
/// every status wait, then released on scope exit including thrown errors.
/// Nothing here opens a transport: the provider is the only outward boundary and
/// every provider in this package is inert.
public enum BoundedFinishingDelivery {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimit, artifactBusy, deviceBusy, leaseUnavailable
        case recordedDeliveryRequiresReview, providerContract
    }
    public struct Outcome: Sendable {
        public let reference: FinishingArtifactReference
        public let disposition: FinishingDeliveryDisposition
        public let tracker: FinishingDeliveryTracker
        public var isUncertain: Bool { disposition.isUncertain }
        public var authorizesBoundedRetry: Bool { disposition.authorizesBoundedRetry }
        /// Never true. Synthetic step satisfaction is not a physical label.
        public var establishesPhysicalCompletion: Bool { disposition.establishesPhysicalCompletion }
        fileprivate init(reference: FinishingArtifactReference, disposition: FinishingDeliveryDisposition,
                         tracker: FinishingDeliveryTracker) {
            self.reference = reference; self.disposition = disposition; self.tracker = tracker
        }
    }

    /// The artifact-lease domain must stay identical to the one the existing
    /// persisted coordinator derives, so both paths serialize the same immutable
    /// reference across caller-provided simulator device aliases.
    static func artifactIdentity(for reference: FinishingArtifactReference) throws -> PhysicalDeviceIdentity {
        let key = Data("LABEL_INERT_FINISHING_ARTIFACT_V1\n\(reference.id)\n\(reference.revision)\n\(reference.sha256)\n".utf8)
        let digest = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        return try .init(coordinationID: .init(sha256: digest))
    }

    public static func run(output: FinishingFramedOutput, reference: FinishingArtifactReference,
                           store: FinishingDeliveryOutcomeStore, provider: FinishingDeliveryProvider,
                           coordinationID: PhysicalDeviceCoordinationID, leaseDirectory: URL,
                           deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                           cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Outcome {
        guard deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else { throw Error.invalidLimit }
        let started = DispatchTime.now().uptimeNanoseconds
        func exhausted() -> Bool {
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000 >= deadlineSeconds
        }
        // Both leases are nonblocking and scoped: a busy artifact or device is a
        // refusal, never a wait that could outlive the bounded deadline.
        let artifactLease: PhysicalDeviceLease
        do { artifactLease = try PhysicalDeviceLease(acquiring: artifactIdentity(for: reference),
                                                     inExistingDirectory: leaseDirectory) }
        catch PhysicalDeviceLeaseError.alreadyHeld { throw Error.artifactBusy }
        catch { throw Error.leaseUnavailable }
        defer { artifactLease.release() }
        let deviceLease: PhysicalDeviceLease
        do { deviceLease = try PhysicalDeviceLease(acquiring: .init(coordinationID: coordinationID),
                                                   inExistingDirectory: leaseDirectory) }
        catch PhysicalDeviceLeaseError.alreadyHeld { throw Error.deviceBusy }
        catch { throw Error.leaseUnavailable }
        defer { deviceLease.release() }
        let ownership = FinishingDeviceOwnership(coordinationID: coordinationID, device: deviceLease,
                                                 artifact: artifactLease)
        // Any durable lifecycle record stops this run. Absence authorizes nothing
        // by itself; it only means no record was written under this reference.
        // Store calls use their own fresh token because this executor owns the
        // cancellation and deadline policy, and a terminal state must stay
        // recordable after a cancelled or expired run.
        guard try store.observation(reference: reference, against: output,
                                    cancellation: .init()) == .noRecordedDelivery else {
            throw Error.recordedDeliveryRequiresReview
        }
        var tracker = FinishingDeliveryTracker(output: output)
        func halt(_ cancelled: Bool) throws {
            switch tracker.state {
            case .ready, .sending, .awaitingStatus: try tracker.stop(cancelled: cancelled)
            default: break
            }
        }
        var disposition: FinishingDeliveryDisposition?
        var intentRecorded = false
        if cancellation.isCancelled {
            disposition = .cancelledBeforeAttempt
            try halt(true)
        } else if exhausted() {
            disposition = .timedOutBeforeAttempt
            try halt(false)
        } else if try provider.prepare(ownership: ownership) == .refusedBeforeAnyBytes {
            disposition = .failedBeforeAttempt
            try halt(false)
        }
        while let step = tracker.nextStep, disposition == nil {
            let index = tracker.nextStepIndex
            if cancellation.isCancelled {
                disposition = tracker.attemptedAnyFile ? .cancelledAfterAttempt(step: index) : .cancelledBeforeAttempt
                try halt(true)
            } else if exhausted() {
                disposition = tracker.attemptedAnyFile ? .timedOutAfterAttempt(step: index) : .timedOutBeforeAttempt
                try halt(false)
            } else if !ownership.isHeld {
                disposition = .ownershipLost(step: index)
                try halt(false)
            } else {
                switch step {
                case let .formatFile(_, bytes), let .delayedCutFile(_, bytes):
                    // Durable send-attempt state precedes the first provider call
                    // that could be effective, and precedes all byte accounting.
                    if !intentRecorded {
                        try store.recordAttemptIntent(reference: reference, against: output, cancellation: .init())
                        intentRecorded = true
                    }
                    try tracker.beginFile(stepIndex: index, bytes: bytes)
                    var publication: FinishingFilePublication?
                    do {
                        publication = try provider.transmit(stepIndex: index, file: step, bytes: bytes,
                            ownership: ownership) { count in try tracker.acceptedByTransport(byteCount: count) }
                    } catch { publication = nil }
                    let accepted = tracker.acceptedBytesInCurrentFile
                    if !ownership.isHeld { disposition = .ownershipLost(step: index) }
                    else if publication == nil { disposition = .providerFailedAfterAttempt(step: index) }
                    else if accepted < bytes.count {
                        disposition = .partialTransmission(step: index, accepted: accepted, expected: bytes.count)
                    } else if publication == .ambiguous { disposition = .ambiguousPublication(step: index) }
                    if disposition == nil { try tracker.fileFinished() }
                    else { try halt(cancellation.isCancelled) }
                default:
                    var reading: FinishingStatusReading?
                    do { reading = try provider.awaitStatus(stepIndex: index, requirement: step, ownership: ownership) }
                    catch { reading = nil }
                    // Ownership must still cover the completed wait, not only the
                    // moment the wait began.
                    if !ownership.isHeld { disposition = .ownershipLost(step: index) }
                    else if reading == nil { disposition = .providerFailedAfterAttempt(step: index) }
                    else if reading == .unknown {
                        _ = try tracker.observeStatus(stepIndex: index, step: step, observation: .unknown)
                        disposition = .statusUnknown(step: index)
                    } else if reading == .notSatisfied {
                        _ = try tracker.observeStatus(stepIndex: index, step: step, observation: .notSatisfied)
                        disposition = .statusNotSatisfied(step: index)
                    } else {
                        _ = try tracker.observeStatus(stepIndex: index, step: step, observation: .confirmed)
                    }
                    if disposition != nil { try halt(cancellation.isCancelled) }
                }
            }
        }
        let final: FinishingDeliveryDisposition
        if let disposition { final = disposition }
        else if tracker.state == .confirmed { final = .allStepsSatisfied }
        else { throw Error.providerContract }
        // Published while both leases are still held. A cancelled or expired run
        // must still record its terminal state, so this bounded write uses a
        // fresh token. An uncertain commit leaves the durable intent in place,
        // so a cold reopen still reports uncertainty rather than absence.
        try store.recordOutcome(reference: reference, against: output, disposition: final,
                                cancellation: .init())
        return Outcome(reference: reference, disposition: final, tracker: tracker)
    }
}
