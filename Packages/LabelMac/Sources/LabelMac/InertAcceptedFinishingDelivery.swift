import CryptoKit
import Foundation
import LabelCore

/// Discard-only admission bound to a durable acceptance, never a printer sender.
public enum InertAcceptedFinishingDelivery {
    public enum Error: Swift.Error, Equatable, Sendable {
        case jobBusy, leaseUnavailable, recordedIntentRequiresReview, cancellationRequested
    }
    public static func run(framed: AcceptedFinishingFramedJob, attemptStore: AcceptedFinishingAttemptStore,
                           cancellationStore: AcceptedFinishingCancellationStore,
                           queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore,
                           printerStore: PrinterProfileStore, workerExecutable: URL, leaseDirectory: URL,
                           scenario: InertFinishingDelivery.Scenario = .init(),
                           deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                           cancellation: OfflineRenderWorkerCancellation = .init()) throws -> FinishingDeliveryTracker {
        try run(framed: framed, attemptStore: attemptStore, cancellationStore: cancellationStore, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable, leaseDirectory: leaseDirectory,
            scenario: scenario, deadlineSeconds: deadlineSeconds, cancellation: cancellation, observe: { _ in })
    }
    static func run(framed: AcceptedFinishingFramedJob, attemptStore: AcceptedFinishingAttemptStore,
                           cancellationStore: AcceptedFinishingCancellationStore,
                    queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore,
                    printerStore: PrinterProfileStore, workerExecutable: URL, leaseDirectory: URL,
                    scenario: InertFinishingDelivery.Scenario, deadlineSeconds: Double,
                    cancellation: OfflineRenderWorkerCancellation,
                    observe: (InertFinishingDelivery.Event) throws -> Void) throws -> FinishingDeliveryTracker {
        guard deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else {
            throw InertFinishingDelivery.Error.invalidScenario
        }
        let start = DispatchTime.now().uptimeNanoseconds
        func remaining() throws -> Double {
            guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
            let value = deadlineSeconds - Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            guard value > 0 else { throw AcceptedFinishingJob.Error.timedOut }
            return value
        }
        _ = try remaining()
        let key = Data("LABEL_INERT_ACCEPTED_FINISHING_V1\n\(framed.reference.acceptanceID)\n".utf8)
        let digest = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        let jobLease: PhysicalDeviceLease
        do { jobLease = try PhysicalDeviceLease(acquiring: .init(coordinationID: .init(sha256: digest)),
                                               inExistingDirectory: leaseDirectory) }
        catch PhysicalDeviceLeaseError.alreadyHeld { throw Error.jobBusy }
        catch { throw Error.leaseUnavailable }
        defer { jobLease.release() }
        let job = framed.prepared.acceptance
        let monitor = try cancellationStore.monitor(reference: framed.reference, against: job,
            queueStore: queueStore, workflowStore: workflowStore, printerStore: printerStore,
            workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
        func requireNoCancellation() throws {
            guard try monitor.poll() == .noRecordedRequest else { throw Error.cancellationRequested }
            _ = try remaining()
        }
        func requireNoIntent() throws {
            guard try attemptStore.recoveryObservation(reference: framed.reference, against: job,
                queueStore: queueStore, workflowStore: workflowStore, printerStore: printerStore,
                workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
                == .noRecordedIntent else { throw Error.recordedIntentRequiresReview }
        }
        try requireNoIntent()
        try requireNoCancellation()
        var intentRecorded = false
        let result = try InertFinishingDelivery.run(output: framed.output, coordinationID: job.geometry.physicalDevice,
            leaseDirectory: leaseDirectory, scenario: scenario, deadlineSeconds: remaining(), cancellation: cancellation) { event in
                _ = try remaining()
                try requireNoCancellation()
                if case .fileAttempt = event, !intentRecorded {
                    try requireNoIntent()
                    try attemptStore.recordPotentialAttempt(reference: framed.reference, against: job,
                        queueStore: queueStore, workflowStore: workflowStore, printerStore: printerStore,
                        workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
                    intentRecorded = true
                }
                _ = try remaining()
                try requireNoCancellation()
                try observe(event)
                try requireNoCancellation()
            }
        _ = try remaining()
        try requireNoCancellation()
        return result
    }
}
