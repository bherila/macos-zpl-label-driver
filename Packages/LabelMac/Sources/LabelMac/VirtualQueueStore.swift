import CryptoKit
import Foundation
import LabelCore

/// Private immutable publication for virtual-queue intent. This store does not
/// create scheduler queues. Loading always re-resolves both immutable profile
/// references before returning a definition to a future publisher.
public struct VirtualQueueStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotCreateStore
        case cannotOpenStore
        case unsafeStoreDirectory
        case cannotRead
        case cannotWrite
        case commitUncertain(ImmutablePublicationIdentity)
        case queueConflict
        case queueIdentityMismatch
        case workflowReferenceMismatch
        case workflowNotQualified
        case printerReferenceMismatch
    }

    public let root: URL
    private let storage: PrivateImmutableDirectory

    public init(root: URL) throws {
        self.root = root
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Self.mapStorage(error) }
    }

    init(root: URL, storage: PrivateImmutableDirectory) {
        self.root = root
        self.storage = storage
    }

    @discardableResult
    public func save(
        _ queue: VirtualQueueDefinition,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> ImmutableProfileReference {
        try validateReferences(
            queue, workflowStore: workflowStore, printerStore: printerStore
        )
        let bytes = try VirtualQueueJSON.encode(queue)
        let reference = try ImmutableProfileReference(
            id: queue.id, schemaVersion: queue.schemaVersion,
            revision: queue.revision, sha256: Self.digest(bytes)
        )
        do {
            try storage.publish(
                bytes, directory: "queues",
                fileName: Self.fileName(queue.id, queue.revision),
                maximumBytes: VirtualQueueJSON.maximumBytes
            )
        } catch PrivateImmutableDirectory.Error.conflict {
            throw Error.queueConflict
        } catch PrivateImmutableDirectory.Error.commitUncertain {
            throw Error.commitUncertain(ImmutablePublicationIdentity(
                id: reference.id, schemaVersion: reference.schemaVersion,
                revision: reference.revision, sha256: reference.sha256
            ))
        } catch {
            throw Self.mapStorage(error)
        }
        return reference
    }

    public func load(
        reference: ImmutableProfileReference,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> VirtualQueueDefinition {
        let queue = try load(
            queueID: reference.id, revision: reference.revision,
            workflowStore: workflowStore, printerStore: printerStore
        )
        let bytes = try VirtualQueueJSON.encode(queue)
        guard reference.schemaVersion == queue.schemaVersion,
              reference.sha256 == Self.digest(bytes) else {
            throw Error.queueIdentityMismatch
        }
        return queue
    }

    public func load(
        queueID: String,
        revision: Int,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> VirtualQueueDefinition {
        let selector: ImmutableProfileReference
        do {
            selector = try ImmutableProfileReference(
                id: queueID, revision: revision, sha256: String(repeating: "0", count: 64)
            )
        } catch {
            throw Error.queueIdentityMismatch
        }
        let bytes: Data
        do {
            bytes = try storage.read(
                directory: "queues", fileName: Self.fileName(selector.id, selector.revision),
                maximumBytes: VirtualQueueJSON.maximumBytes
            )
        } catch {
            throw Self.mapStorage(error)
        }
        let printerReference = try VirtualQueueJSON.printerProfileReference(in: bytes)
        let printerProfile: PrinterProfile
        do { printerProfile = try printerStore.load(reference: printerReference) }
        catch { throw Error.printerReferenceMismatch }
        let queue = try VirtualQueueJSON.decode(bytes, validatingAgainst: printerProfile)
        guard queue.id == selector.id, queue.revision == selector.revision else {
            throw Error.queueIdentityMismatch
        }
        try validateReferences(
            queue, workflowStore: workflowStore, printerStore: printerStore
        )
        return queue
    }

    static func fileName(_ id: String, _ revision: Int) -> String {
        "\(digest(Data(id.utf8)))-r\(revision).json"
    }

    private func validateReferences(
        _ queue: VirtualQueueDefinition,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws {
        do { _ = try printerStore.load(reference: queue.printerProfile) }
        catch { throw Error.printerReferenceMismatch }
        let workflow: WorkflowProfile
        do {
            workflow = try workflowStore.load(
                profileID: queue.workflowProfile.id,
                revision: queue.workflowProfile.revision
            )
        } catch {
            throw Error.workflowReferenceMismatch
        }
        let bytes = try WorkflowProfileJSON.encode(workflow)
        guard workflow.schemaVersion == queue.workflowProfile.schemaVersion,
              workflow.id == queue.workflowProfile.id,
              workflow.revision == queue.workflowProfile.revision,
              Self.digest(bytes) == queue.workflowProfile.sha256 else {
            throw Error.workflowReferenceMismatch
        }
        do {
            guard try workflowStore.qualification(for: workflow) != nil else {
                throw Error.workflowNotQualified
            }
        } catch let error as Error {
            throw error
        } catch {
            throw Error.workflowReferenceMismatch
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mapStorage(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .cannotCreate: .cannotCreateStore
        case .cannotOpen: .cannotOpenStore
        case .unsafeDirectory: .unsafeStoreDirectory
        case .cannotWrite, .commitUncertain, .conflict: .cannotWrite
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }
}
