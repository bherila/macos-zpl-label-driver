import CryptoKit
import Foundation
import LabelCore

public struct FinishingArtifactReference: Equatable, Sendable, RedactedDiagnosticValue {
    public enum Error: Swift.Error, Equatable, Sendable { case invalidReference }
    public let id: String
    public let revision: Int
    public let sha256: String
    public init(id: String, revision: Int, sha256: String) throws {
        // Reuse only the established bounded identifier/digest validator; this
        // distinct reference is not a printer profile or accepted job ticket.
        guard (try? ImmutableProfileReference(id: id, revision: revision, sha256: sha256)) != nil else {
            throw Error.invalidReference
        }
        self.id = id; self.revision = revision; self.sha256 = sha256
    }
}

/// Private immutable archives, not spooler admission or delivery lifecycle.
/// Each reopen needs independently bound context. No enumeration/replay action.
public struct FinishingArtifactStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsafeDirectory, cannotRead, cannotWrite, capacityReached, publicationBusy
        case conflict, referenceMismatch, commitUncertain(FinishingArtifactReference)
    }
    public static let maximumRecords = 4
    public let root: URL
    private let storage: PrivateImmutableDirectory
    public init(root: URL) throws {
        self.root = root
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Self.mapStorage(error) }
    }
    init(root: URL, storage: PrivateImmutableDirectory) { self.root = root; self.storage = storage }

    @discardableResult
    public func save(id: String, revision: Int, output: FinishingFramedOutput,
                     cancellation: OfflineRenderWorkerCancellation = .init()) throws -> FinishingArtifactReference {
        _ = try FinishingArtifactReference(id: id, revision: revision, sha256: String(repeating: "0", count: 64))
        let artifact = try FinishingFramedArtifact.encode(output, cancellation: cancellation)
        let reference = try FinishingArtifactReference(id: id, revision: revision, sha256: artifact.sha256)
        guard !cancellation.isCancelled else { throw FinishingFramedArtifact.Error.cancelled }
        do {
            try storage.publish(artifact.bytes, directory: "finishing-artifacts", fileName: Self.fileName(reference),
                maximumBytes: FinishingFramedArtifact.maximumBytes,
                maximumRecords: Self.maximumRecords, recordFormat: .binary)
        } catch PrivateImmutableDirectory.Error.conflict { throw Error.conflict }
        catch PrivateImmutableDirectory.Error.commitUncertain { throw Error.commitUncertain(reference) }
        catch { throw Self.mapStorage(error) }
        guard !cancellation.isCancelled else { throw Error.commitUncertain(reference) }
        return reference
    }

    public func load(reference: FinishingArtifactReference, against output: FinishingFramedOutput,
                     cancellation: OfflineRenderWorkerCancellation = .init()) throws -> FinishingFramedArtifact {
        guard !cancellation.isCancelled else { throw FinishingFramedArtifact.Error.cancelled }
        let bytes: Data
        do {
            bytes = try storage.read(directory: "finishing-artifacts", fileName: Self.fileName(reference),
                maximumBytes: FinishingFramedArtifact.maximumBytes)
        } catch { throw Self.mapStorage(error) }
        let artifact = try FinishingFramedArtifact.reopen(bytes, against: output, cancellation: cancellation)
        guard artifact.sha256 == reference.sha256 else { throw Error.referenceMismatch }
        return artifact
    }
    private static func fileName(_ reference: FinishingArtifactReference) -> String {
        let id = SHA256.hash(data: Data(reference.id.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(id)-r\(reference.revision).bin"
    }
    private static func mapStorage(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .cannotCreate, .cannotOpen, .unsafeDirectory: .unsafeDirectory
        case .recordCapacityReached: .capacityReached
        case .publicationBusy: .publicationBusy
        case .conflict: .conflict
        case .cannotWrite, .commitUncertain: .cannotWrite
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }
}
