import CryptoKit
import Foundation
import LabelCore

/// Separate offline policy reference; it cannot substitute for an ordinary queue reference.
public struct FinishingQueueReference: Equatable, Sendable, RedactedDiagnosticValue {
    public let id: String
    public let revision: Int
    public let sha256: String
    public init(id: String, revision: Int, sha256: String) throws {
        _ = try ImmutableProfileReference(id: id, revision: revision, sha256: sha256)
        self.id = id; self.revision = revision; self.sha256 = sha256
    }
}

/// Private immutable offline intent, never a scheduler queue or accepted job.
public struct FinishingQueueStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case referenceMismatch, workflowReferenceMismatch, printerReferenceMismatch
        case workflowNotQualified, snapshotMismatch, conflict
        case unsafeStore, cannotRead, cannotWrite, capacityReached, publicationBusy
        case commitUncertain(FinishingQueueReference)
    }
    public let root: URL
    private let storage: PrivateImmutableDirectory
    public init(root: URL) throws {
        self.root = root
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Self.mapStorage(error) }
    }
    init(root: URL, storage: PrivateImmutableDirectory) {
        self.root = root; self.storage = storage
    }
    @discardableResult
    public func save(_ queue: FinishingQueueDefinition, workflowStore: WorkflowProfileStore,
                     printerStore: PrinterProfileStore) throws -> FinishingQueueReference {
        let snapshots = try resolve(workflow: queue.workflowProfile, printer: queue.printerProfile,
                                    workflowStore: workflowStore, printerStore: printerStore)
        do { _ = try queue.resolve(outputLabelCount: 1, workflow: snapshots.workflow, printer: snapshots.printer) }
        catch { throw Error.snapshotMismatch }
        let bytes = try FinishingQueueJSON.encode(queue)
        let reference = try FinishingQueueReference(id: queue.id, revision: queue.revision, sha256: Self.digest(bytes))
        do {
            try storage.publish(bytes, directory: "finishing-queues", fileName: Self.fileName(reference),
                maximumBytes: FinishingQueueJSON.maximumBytes, maximumRecords: 256)
        } catch PrivateImmutableDirectory.Error.commitUncertain { throw Error.commitUncertain(reference) }
        catch { throw Self.mapStorage(error) }
        return reference
    }
    public func load(reference: FinishingQueueReference, workflowStore: WorkflowProfileStore,
                     printerStore: PrinterProfileStore) throws -> FinishingQueueDefinition {
        let bytes: Data
        do { bytes = try storage.read(directory: "finishing-queues", fileName: Self.fileName(reference),
                                      maximumBytes: FinishingQueueJSON.maximumBytes) }
        catch { throw Self.mapStorage(error) }
        guard Self.digest(bytes) == reference.sha256 else { throw Error.referenceMismatch }
        let refs = try FinishingQueueJSON.references(in: bytes)
        let snapshots = try resolve(workflow: refs.workflow, printer: refs.printer,
                                    workflowStore: workflowStore, printerStore: printerStore)
        let queue = try FinishingQueueJSON.decode(bytes, workflow: snapshots.workflow, printer: snapshots.printer)
        guard queue.id == reference.id, queue.revision == reference.revision else { throw Error.referenceMismatch }
        return queue
    }
    private func resolve(workflow reference: ImmutableProfileReference, printer: ImmutableProfileReference,
                         workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore) throws
        -> (workflow: WorkflowProfile, printer: PrinterProfile) {
        let profile: PrinterProfile
        do { profile = try printerStore.load(reference: printer) }
        catch { throw Error.printerReferenceMismatch }
        let workflow: WorkflowProfile
        do { workflow = try workflowStore.load(profileID: reference.id, revision: reference.revision) }
        catch { throw Error.workflowReferenceMismatch }
        guard reference.schemaVersion == workflow.schemaVersion,
              reference.sha256 == Self.digest(try WorkflowProfileJSON.encode(workflow)) else {
            throw Error.workflowReferenceMismatch
        }
        guard try workflowStore.qualification(for: workflow) != nil else { throw Error.workflowNotQualified }
        return (workflow, profile)
    }
    static func fileName(_ reference: FinishingQueueReference) -> String {
        "\(digest(Data(reference.id.utf8)))-r\(reference.revision).json"
    }
    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private static func mapStorage(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .conflict: .conflict
        case .recordCapacityReached: .capacityReached
        case .publicationBusy: .publicationBusy
        case .cannotRead, .notFound: .cannotRead
        case .cannotWrite, .commitUncertain: .cannotWrite
        case .cannotCreate, .cannotOpen, .unsafeDirectory, .none: .unsafeStore
        }
    }
}
