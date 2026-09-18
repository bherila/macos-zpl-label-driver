import CryptoKit
import Foundation
import LabelCore

/// Discard-only integration of durable intent and lease lifetime. No printer
/// commands are delivered and synthetic status never resolves persisted uncertainty.
public enum InertPersistedFinishingDelivery {
    public enum Error: Swift.Error, Equatable, Sendable {
        case artifactBusy, leaseUnavailable, recordedIntentRequiresReview
    }
    public static func run(output: FinishingFramedOutput, reference: FinishingArtifactReference,
                           attemptStore: FinishingAttemptStore,
                           coordinationID: PhysicalDeviceCoordinationID, leaseDirectory: URL,
                           scenario: InertFinishingDelivery.Scenario = .init(),
                           deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                           cancellation: OfflineRenderWorkerCancellation = .init()) throws -> FinishingDeliveryTracker {
        try run(output: output, reference: reference, attemptStore: attemptStore,
            coordinationID: coordinationID, leaseDirectory: leaseDirectory, scenario: scenario,
            deadlineSeconds: deadlineSeconds, cancellation: cancellation, observe: { _ in })
    }
    static func run(output: FinishingFramedOutput, reference: FinishingArtifactReference,
                    attemptStore: FinishingAttemptStore,
                    coordinationID: PhysicalDeviceCoordinationID, leaseDirectory: URL,
                    scenario: InertFinishingDelivery.Scenario,
                    deadlineSeconds: Double, cancellation: OfflineRenderWorkerCancellation,
                    observe: (InertFinishingDelivery.Event) throws -> Void) throws -> FinishingDeliveryTracker {
        // Serialize this artifact independently of caller-provided simulator
        // device aliases. Both leases are nonblocking and scoped through waits.
        let key = Data("LABEL_INERT_FINISHING_ARTIFACT_V1\n\(reference.id)\n\(reference.revision)\n\(reference.sha256)\n".utf8)
        let digest = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        let artifactLease: PhysicalDeviceLease
        do {
            artifactLease = try PhysicalDeviceLease(acquiring: .init(coordinationID: .init(sha256: digest)),
                                                    inExistingDirectory: leaseDirectory)
        } catch PhysicalDeviceLeaseError.alreadyHeld { throw Error.artifactBusy }
        catch { throw Error.leaseUnavailable }
        defer { artifactLease.release() }
        var intentRecorded = false
        return try InertFinishingDelivery.run(output: output, coordinationID: coordinationID,
            leaseDirectory: leaseDirectory, scenario: scenario, deadlineSeconds: deadlineSeconds,
            cancellation: cancellation) { event in
                if case .fileAttempt = event, !intentRecorded {
                    guard try attemptStore.recoveryObservation(reference: reference, against: output,
                        cancellation: cancellation) == .noRecordedIntent else {
                        throw Error.recordedIntentRequiresReview
                    }
                    try attemptStore.recordPotentialAttempt(reference: reference, against: output,
                                                            cancellation: cancellation)
                    intentRecorded = true
                }
                try observe(event)
            }
    }
}
