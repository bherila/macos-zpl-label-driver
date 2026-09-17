import Foundation
import LabelCore

/// Framing retains durable acceptance identity alongside exact packed preparation.
/// Qualification declarations are not physical receipts or delivery permission.
public struct AcceptedFinishingFramedJob: Equatable, Sendable {
    public let prepared: PreparedAcceptedFinishingJob
    public let output: FinishingFramedOutput
    public var reference: AcceptedFinishingReference { prepared.reference }
    fileprivate init(prepared: PreparedAcceptedFinishingJob, output: FinishingFramedOutput) {
        self.prepared = prepared; self.output = output
    }
}

public extension PreparedAcceptedFinishingJob {
    func frame(qualification: FinishingOutputQualification,
               maximumBytes: Int = FinishingFramedOutput.maximumBytes,
               deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
               cancellation: OfflineRenderWorkerCancellation = .init()) throws -> AcceptedFinishingFramedJob {
        let output = try FinishingFramedOutput.prepare(preparation, qualification: qualification,
            maximumBytes: maximumBytes, deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        return AcceptedFinishingFramedJob(prepared: self, output: output)
    }
}
