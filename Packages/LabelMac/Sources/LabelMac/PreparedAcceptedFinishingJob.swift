import Foundation
import LabelCore

/// Preparation carries the exact durable acceptance identity. Construction is
/// available only through the verified store path; it grants no device delivery.
public struct PreparedAcceptedFinishingJob: Equatable, Sendable {
    public let reference: AcceptedFinishingReference
    public let acceptance: AcceptedFinishingJob
    public let preparation: FinishingRasterPreparation
    fileprivate init(reference: AcceptedFinishingReference, acceptance: AcceptedFinishingJob,
                     preparation: FinishingRasterPreparation) {
        self.reference = reference; self.acceptance = acceptance; self.preparation = preparation
    }
}

public extension AcceptedFinishingJobStore {
    func prepare(reference: AcceptedFinishingReference, queueStore: FinishingQueueStore,
                 workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore,
                 workerExecutable: URL,
                 deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                 cancellation: OfflineRenderWorkerCancellation = .init()) throws -> PreparedAcceptedFinishingJob {
        guard deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else { throw AcceptedFinishingJob.Error.invalidLimit }
        let start = DispatchTime.now().uptimeNanoseconds
        func remaining() throws -> Double {
            guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
            let value = deadlineSeconds - Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            guard value > 0 else { throw AcceptedFinishingJob.Error.timedOut }; return value
        }
        let accepted = try load(reference: reference, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
        let preparation = try accepted.prepare(workerExecutable: workerExecutable,
                                               deadlineSeconds: remaining(), cancellation: cancellation)
        _ = try remaining()
        return PreparedAcceptedFinishingJob(reference: reference, acceptance: accepted, preparation: preparation)
    }
}
