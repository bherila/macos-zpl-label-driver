import CryptoKit
import Foundation

/// Conservative job-level intent. Artifact identifiers are deliberately absent
/// from the key/API. Publication is idempotent persistence, never send authority.
public struct AcceptedFinishingAttemptStore: @unchecked Sendable {
    public enum RecoveryObservation: Equatable, Sendable {
        case noRecordedIntent
        case uncertainAfterRecordedIntent
    }
    public enum Error: Swift.Error, Equatable, Sendable {
        case contextMismatch, invalidRecord, cannotRead, cannotWrite, unsafeStore
        case conflict, capacityReached, publicationBusy, commitUncertain
    }
    private let accepted: AcceptedFinishingJobStore
    private let storage: PrivateImmutableDirectory
    public init(root: URL) throws {
        accepted = try AcceptedFinishingJobStore(root: root)
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Error.unsafeStore }
    }
    init(root: URL, storage: PrivateImmutableDirectory) throws {
        accepted = try AcceptedFinishingJobStore(root: root); self.storage = storage
    }
    public func recordPotentialAttempt(reference: AcceptedFinishingReference, against job: AcceptedFinishingJob,
        queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore,
        workerExecutable: URL, deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        let start = DispatchTime.now().uptimeNanoseconds
        try validate(reference: reference, job: job, queueStore: queueStore, workflowStore: workflowStore,
                     printerStore: printerStore, workerExecutable: workerExecutable,
                     deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        try Self.check(start: start, deadline: deadlineSeconds, cancellation: cancellation)
        do { try storage.publish(Self.record(reference), directory: "accepted-finishing-attempts",
            fileName: Self.fileName(reference), maximumBytes: 1024, maximumRecords: 4, recordFormat: .binary) }
        catch { throw Self.map(error) }
        do { try Self.check(start: start, deadline: deadlineSeconds, cancellation: cancellation) }
        catch { throw Error.commitUncertain }
    }
    public func recoveryObservation(reference: AcceptedFinishingReference, against job: AcceptedFinishingJob,
        queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore,
        workerExecutable: URL, deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()) throws -> RecoveryObservation {
        let start = DispatchTime.now().uptimeNanoseconds
        try validate(reference: reference, job: job, queueStore: queueStore, workflowStore: workflowStore,
                     printerStore: printerStore, workerExecutable: workerExecutable,
                     deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        try Self.check(start: start, deadline: deadlineSeconds, cancellation: cancellation)
        let bytes: Data
        do { bytes = try storage.read(directory: "accepted-finishing-attempts", fileName: Self.fileName(reference), maximumBytes: 1024, createDirectoryIfMissing: false) }
        catch PrivateImmutableDirectory.Error.notFound {
            try Self.check(start: start, deadline: deadlineSeconds, cancellation: cancellation)
            return .noRecordedIntent
        }
        catch { throw Self.map(error) }
        guard bytes == Self.record(reference) else { throw Error.invalidRecord }
        try Self.check(start: start, deadline: deadlineSeconds, cancellation: cancellation)
        return .uncertainAfterRecordedIntent
    }
    /// Observation from a context this same catalog already verified. Absence
    /// remains observation only and never becomes retry or replay authority.
    public func recoveryObservation(validated context: ValidatedAcceptedFinishingContext,
                                    deadline: FinishingDeadline) throws -> RecoveryObservation {
        guard context.bound(to: accepted.root) else { throw Error.contextMismatch }
        try deadline.check()
        let bytes: Data
        do { bytes = try storage.read(directory: "accepted-finishing-attempts", fileName: Self.fileName(context.reference), maximumBytes: 1024, createDirectoryIfMissing: false) }
        catch PrivateImmutableDirectory.Error.notFound { try deadline.check(); return .noRecordedIntent }
        catch { throw Self.map(error) }
        guard bytes == Self.record(context.reference) else { throw Error.invalidRecord }
        try deadline.check()
        return .uncertainAfterRecordedIntent
    }
    private func validate(reference: AcceptedFinishingReference, job: AcceptedFinishingJob,
        queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore,
        workerExecutable: URL, deadlineSeconds: Double, cancellation: OfflineRenderWorkerCancellation) throws {
        let loaded = try accepted.load(reference: reference, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable,
            deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        guard loaded == job else { throw Error.contextMismatch }
    }
    private static func check(start: UInt64, deadline: Double, cancellation: OfflineRenderWorkerCancellation) throws {
        guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
        guard Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000 < deadline else { throw AcceptedFinishingJob.Error.timedOut }
    }
    private static func record(_ ref: AcceptedFinishingReference) -> Data {
        Data("LABEL_ACCEPTED_FINISHING_ATTEMPT_V1\n\(ref.acceptanceID)\n\(ref.sha256)\n".utf8)
    }
    static func fileName(_ ref: AcceptedFinishingReference) -> String {
        SHA256.hash(data: Data(ref.acceptanceID.utf8)).map { String(format: "%02x", $0) }.joined() + ".bin"
    }
    private static func map(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .conflict: .conflict
        case .recordCapacityReached: .capacityReached
        case .publicationBusy: .publicationBusy
        case .cannotRead, .notFound: .cannotRead
        case .cannotWrite: .cannotWrite
        case .commitUncertain: .commitUncertain
        case .cannotCreate, .cannotOpen, .unsafeDirectory, .none: .unsafeStore
        }
    }
}
