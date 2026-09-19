import Foundation

/// Cold observations only. Neither case grants delivery/replay permission, and
/// absence of local intent is not evidence that no external transmission occurred.
public struct AcceptedFinishingRecovery: Equatable, Sendable {
    public enum Observation: Equatable, Sendable {
        case noRecordedIntent(cancellationRequested: Bool)
        case uncertainAfterRecordedIntent(cancellationRequested: Bool)
    }
    public let reference: AcceptedFinishingReference
    public let observation: Observation
    private init(reference: AcceptedFinishingReference, observation: Observation) {
        self.reference = reference; self.observation = observation
    }
    public static func inspect(reference: AcceptedFinishingReference, against job: AcceptedFinishingJob,
                               attemptStore: AcceptedFinishingAttemptStore,
                               cancellationStore: AcceptedFinishingCancellationStore,
                               queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore,
                               printerStore: PrinterProfileStore, workerExecutable: URL,
                               deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                               cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Self {
        guard deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else {
            throw AcceptedFinishingJob.Error.invalidLimit
        }
        let start = DispatchTime.now().uptimeNanoseconds
        func remaining() throws -> Double {
            guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
            let value = deadlineSeconds - Double(DispatchTime.now().uptimeNanoseconds-start) / 1_000_000_000
            guard value > 0 else { throw AcceptedFinishingJob.Error.timedOut }
            return value
        }
        let monitor = try cancellationStore.monitor(reference: reference, against: job,
            queueStore: queueStore, workflowStore: workflowStore, printerStore: printerStore,
            workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
        let intent = try attemptStore.recoveryObservation(reference: reference, against: job,
            queueStore: queueStore, workflowStore: workflowStore, printerStore: printerStore,
            workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
        let requested = try monitor.poll() == .requested
        _ = try remaining()
        let observation: Observation
        switch intent {
        case .noRecordedIntent: observation = .noRecordedIntent(cancellationRequested: requested)
        case .uncertainAfterRecordedIntent: observation = .uncertainAfterRecordedIntent(cancellationRequested: requested)
        }
        return Self(reference: reference, observation: observation)
    }
    /// Cold observation from a context this same catalog already verified, under
    /// the command's shared budget. Intent is read before the cancellation poll
    /// so a request recorded between the two is still reported, and neither case
    /// grants delivery or replay permission.
    public static func inspect(validated context: ValidatedAcceptedFinishingContext,
                               attemptStore: AcceptedFinishingAttemptStore,
                               cancellationStore: AcceptedFinishingCancellationStore,
                               deadline: FinishingDeadline) throws -> Self {
        let monitor = try cancellationStore.monitor(validated: context, deadline: deadline)
        let intent = try attemptStore.recoveryObservation(validated: context, deadline: deadline)
        let requested = try monitor.poll() == .requested
        try deadline.check()
        let observation: Observation
        switch intent {
        case .noRecordedIntent: observation = .noRecordedIntent(cancellationRequested: requested)
        case .uncertainAfterRecordedIntent: observation = .uncertainAfterRecordedIntent(cancellationRequested: requested)
        }
        return Self(reference: context.reference, observation: observation)
    }
}
