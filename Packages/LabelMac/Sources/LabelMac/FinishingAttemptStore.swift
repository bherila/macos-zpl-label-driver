import CryptoKit
import Foundation

/// Durable conservative intent for an offline framed artifact. This is neither
/// accepted-job admission nor permission to send/retry. A future adapter must
/// coordinate intent publication before its first external file attempt.
public struct FinishingAttemptStore: @unchecked Sendable {
    public enum RecoveryObservation: Equatable, Sendable {
        /// Absence is not proof that some other sender never transmitted.
        case noRecordedIntent
        /// Includes a crash between durable intent and the external send call.
        case uncertainAfterRecordedIntent
    }
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsafeDirectory, cannotRead, cannotWrite, conflict, invalidRecord
        case capacityReached, publicationBusy, commitUncertain
    }
    private let archives: FinishingArtifactStore
    private let storage: PrivateImmutableDirectory
    public init(root: URL) throws {
        archives = try FinishingArtifactStore(root: root)
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Error.unsafeDirectory }
    }
    init(root: URL, storage: PrivateImmutableDirectory) throws {
        archives = try FinishingArtifactStore(root: root)
        self.storage = storage
    }

    /// Idempotent persistence only, never fresh-send authorization. Do not send
    /// after an error or uncertain commit. There is deliberately no clear/reset.
    public func recordPotentialAttempt(reference: FinishingArtifactReference,
                                       against output: FinishingFramedOutput,
                                       cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        _ = try archives.load(reference: reference, against: output, cancellation: cancellation)
        guard !cancellation.isCancelled else { throw FinishingFramedArtifact.Error.cancelled }
        do {
            try storage.publish(Self.record(reference), directory: "finishing-attempts",
                fileName: Self.fileName(reference), maximumBytes: 1024,
                maximumRecords: FinishingArtifactStore.maximumRecords, recordFormat: .binary)
        } catch { throw Self.map(error) }
        guard !cancellation.isCancelled else { throw Error.commitUncertain }
    }

    public func recoveryObservation(reference: FinishingArtifactReference,
                                    against output: FinishingFramedOutput,
                                    cancellation: OfflineRenderWorkerCancellation = .init()) throws -> RecoveryObservation {
        // Validate independently supplied complete context even when no marker exists.
        _ = try archives.load(reference: reference, against: output, cancellation: cancellation)
        let bytes: Data
        do {
            bytes = try storage.read(directory: "finishing-attempts", fileName: Self.fileName(reference),
                                     maximumBytes: 1024)
        } catch PrivateImmutableDirectory.Error.notFound { return .noRecordedIntent }
        catch { throw Self.map(error) }
        guard bytes == Self.record(reference) else { throw Error.invalidRecord }
        guard !cancellation.isCancelled else { throw FinishingFramedArtifact.Error.cancelled }
        return .uncertainAfterRecordedIntent
    }
    private static func record(_ reference: FinishingArtifactReference) -> Data {
        // Validated identifier alphabet and digest cannot inject delimiters.
        Data("LABEL_FINISHING_ATTEMPT_V1\n\(reference.id)\n\(reference.revision)\n\(reference.sha256)\n".utf8)
    }
    private static func fileName(_ reference: FinishingArtifactReference) -> String {
        let id = SHA256.hash(data: Data(reference.id.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(id)-r\(reference.revision).bin"
    }
    private static func map(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .cannotCreate, .cannotOpen, .unsafeDirectory: .unsafeDirectory
        case .recordCapacityReached: .capacityReached
        case .publicationBusy: .publicationBusy
        case .conflict: .conflict
        case .commitUncertain: .commitUncertain
        case .cannotWrite: .cannotWrite
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }
}
