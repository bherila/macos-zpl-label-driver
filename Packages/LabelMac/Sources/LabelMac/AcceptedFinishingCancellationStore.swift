import CryptoKit
import Foundation

/// Durable local cancellation request. It sends no device command and cannot
/// undo accepted bytes or resolve recorded delivery uncertainty.
public struct AcceptedFinishingCancellationStore: @unchecked Sendable {
    public enum Observation: Equatable, Sendable { case noRecordedRequest, requested }
    public enum Error: Swift.Error, Equatable, Sendable {
        case unauthorized, contextMismatch, invalidRecord, cannotRead, cannotWrite
        case unsafeStore, conflict, capacityReached, publicationBusy, commitUncertain
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
    public func request(reference: AcceptedFinishingReference, against job: AcceptedFinishingJob,
                        token: Data, queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore,
                        printerStore: PrinterProfileStore, workerExecutable: URL,
                        deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                        cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        guard !token.isEmpty, token.count <= 256 else { throw Error.unauthorized }
        let supplied = Array(SHA256.hash(data: token).map { String(format: "%02x", $0) }.joined().utf8)
        let expected = Array(job.cancellationSHA256.utf8)
        guard supplied.count == expected.count else { throw Error.unauthorized }
        var difference: UInt8 = 0
        for index in supplied.indices { difference |= supplied[index] ^ expected[index] }
        guard difference == 0 else { throw Error.unauthorized }
        let start = DispatchTime.now().uptimeNanoseconds
        try validate(reference, job: job, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable,
            deadline: deadlineSeconds, cancellation: cancellation)
        try Self.check(start, deadline: deadlineSeconds, cancellation: cancellation)
        do { try storage.publish(Self.record(reference), directory: "accepted-finishing-cancellations",
            fileName: Self.fileName(reference), maximumBytes: 1024, maximumRecords: 4, recordFormat: .binary) }
        catch { throw Self.map(error) }
        do { try Self.check(start, deadline: deadlineSeconds, cancellation: cancellation) }
        catch { throw Error.commitUncertain }
    }
    public func observation(reference: AcceptedFinishingReference, against job: AcceptedFinishingJob,
                            queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore,
                            printerStore: PrinterProfileStore, workerExecutable: URL,
                            deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                            cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Observation {
        let start = DispatchTime.now().uptimeNanoseconds
        try validate(reference, job: job, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable,
            deadline: deadlineSeconds, cancellation: cancellation)
        try Self.check(start, deadline: deadlineSeconds, cancellation: cancellation)
        let result = try Self.read(storage: storage, reference: reference)
        try Self.check(start, deadline: deadlineSeconds, cancellation: cancellation)
        return result
    }
    /// Monitor construction validates durable context once. Polling reads only
    /// the bounded immutable request; it does not repeatedly parse the PDF.
    public struct Monitor: @unchecked Sendable {
        private let storage: PrivateImmutableDirectory
        public let reference: AcceptedFinishingReference
        fileprivate init(storage: PrivateImmutableDirectory, reference: AcceptedFinishingReference) {
            self.storage = storage; self.reference = reference
        }
        public func poll() throws -> Observation {
            try AcceptedFinishingCancellationStore.read(storage: storage, reference: reference)
        }
    }
    public func monitor(reference: AcceptedFinishingReference, against job: AcceptedFinishingJob,
                        queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore,
                        printerStore: PrinterProfileStore, workerExecutable: URL,
                        deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                        cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Monitor {
        let start = DispatchTime.now().uptimeNanoseconds
        try validate(reference, job: job, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable,
            deadline: deadlineSeconds, cancellation: cancellation)
        try Self.check(start, deadline: deadlineSeconds, cancellation: cancellation)
        return Monitor(storage: storage, reference: reference)
    }
    /// Monitor from a context this same catalog already verified. Durable binding
    /// comes from that verification rather than a second reopen of the record;
    /// polling, cancellation and uncertainty semantics are unchanged.
    public func monitor(validated context: ValidatedAcceptedFinishingContext,
                        deadline: FinishingDeadline) throws -> Monitor {
        guard context.bound(to: accepted.root) else { throw Error.contextMismatch }
        try deadline.check()
        return Monitor(storage: storage, reference: context.reference)
    }
    private static func read(storage: PrivateImmutableDirectory, reference: AcceptedFinishingReference) throws -> Observation {
        let bytes: Data
        do { bytes = try storage.read(directory: "accepted-finishing-cancellations", fileName: Self.fileName(reference), maximumBytes: 1024, createDirectoryIfMissing: false) }
        catch PrivateImmutableDirectory.Error.notFound { return .noRecordedRequest }
        catch { throw Self.map(error) }
        guard bytes == Self.record(reference) else { throw Error.invalidRecord }
        return .requested
    }
    private func validate(_ reference: AcceptedFinishingReference, job: AcceptedFinishingJob,
                          queueStore: FinishingQueueStore, workflowStore: WorkflowProfileStore,
                          printerStore: PrinterProfileStore, workerExecutable: URL,
                          deadline: Double, cancellation: OfflineRenderWorkerCancellation) throws {
        let loaded = try accepted.load(reference: reference, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable,
            deadlineSeconds: deadline, cancellation: cancellation)
        guard loaded == job else { throw Error.contextMismatch }
    }
    private static func check(_ start: UInt64, deadline: Double, cancellation: OfflineRenderWorkerCancellation) throws {
        guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
        guard Double(DispatchTime.now().uptimeNanoseconds-start) / 1_000_000_000 < deadline else { throw AcceptedFinishingJob.Error.timedOut }
    }
    private static func record(_ ref: AcceptedFinishingReference) -> Data {
        Data("LABEL_ACCEPTED_FINISHING_CANCELLATION_V1\n\(ref.acceptanceID)\n\(ref.sha256)\n".utf8)
    }
    static func fileName(_ ref: AcceptedFinishingReference) -> String {
        SHA256.hash(data: Data(ref.acceptanceID.utf8)).map { String(format: "%02x", $0) }.joined()+".bin"
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
