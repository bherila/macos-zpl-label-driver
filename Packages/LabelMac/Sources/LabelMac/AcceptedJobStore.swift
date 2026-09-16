import CryptoKit
import Foundation
import LabelCore

/// Private immutable persistence for accepted job semantics. Source documents
/// and rendered payloads are deliberately outside this store.
public struct AcceptedJobStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotCreateStore
        case cannotOpenStore
        case unsafeStoreDirectory
        case cannotRead
        case cannotWrite
        case jobConflict
        case jobIdentityMismatch
        case queueReferenceMismatch
        case workflowReferenceMismatch
        case printerReferenceMismatch
    }

    public let root: URL
    private let storage: PrivateImmutableDirectory

    public init(root: URL) throws {
        self.root = root
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Self.mapStorage(error) }
    }

    public func save(
        _ ticket: ResolvedJobTicket,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws {
        let bytes = try ResolvedJobTicketJSON.encode(ticket)
        _ = try validate(
            bytes, expectedAcceptanceID: ticket.acceptanceID,
            queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore
        )
        do {
            try storage.publish(
                bytes, directory: "accepted-jobs",
                fileName: Self.fileName(ticket.acceptanceID),
                maximumBytes: ResolvedJobTicketJSON.maximumBytes
            )
        } catch PrivateImmutableDirectory.Error.conflict {
            throw Error.jobConflict
        } catch {
            throw Self.mapStorage(error)
        }
    }

    public func load(
        acceptanceID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> ResolvedJobTicket {
        guard (try? ImmutableProfileReference(
            id: acceptanceID, revision: 1,
            sha256: String(repeating: "0", count: 64)
        )) != nil else {
            throw Error.jobIdentityMismatch
        }
        let bytes: Data
        do {
            bytes = try storage.read(
                directory: "accepted-jobs", fileName: Self.fileName(acceptanceID),
                maximumBytes: ResolvedJobTicketJSON.maximumBytes
            )
        } catch {
            throw Self.mapStorage(error)
        }
        return try validate(
            bytes, expectedAcceptanceID: acceptanceID,
            queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore
        )
    }

    static func fileName(_ acceptanceID: String) -> String {
        "\(digest(Data(acceptanceID.utf8))).json"
    }

    private func validate(
        _ bytes: Data,
        expectedAcceptanceID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> ResolvedJobTicket {
        let queueReference: ImmutableProfileReference
        do { queueReference = try ResolvedJobTicketJSON.queueReference(bytes) }
        catch { throw Error.cannotRead }

        let queue: VirtualQueueDefinition
        do {
            queue = try queueStore.load(
                reference: queueReference, workflowStore: workflowStore,
                printerStore: printerStore
            )
        } catch {
            throw Error.queueReferenceMismatch
        }

        let workflow: WorkflowProfile
        do {
            workflow = try workflowStore.load(
                profileID: queue.workflowProfile.id,
                revision: queue.workflowProfile.revision
            )
            let canonical = try WorkflowProfileJSON.encode(workflow)
            guard queue.workflowProfile.schemaVersion == workflow.schemaVersion,
                  queue.workflowProfile.id == workflow.id,
                  queue.workflowProfile.revision == workflow.revision,
                  queue.workflowProfile.sha256 == Self.digest(canonical) else {
                throw Error.workflowReferenceMismatch
            }
        } catch let error as Error {
            throw error
        } catch {
            throw Error.workflowReferenceMismatch
        }

        let printer: PrinterProfile
        do { printer = try printerStore.load(reference: queue.printerProfile) }
        catch { throw Error.printerReferenceMismatch }

        let ticket: ResolvedJobTicket
        do {
            ticket = try ResolvedJobTicketJSON.decode(
                bytes, queueReference: queueReference, queueDefinition: queue,
                workflowProfile: workflow, printerProfile: printer
            )
        } catch {
            throw Error.cannotRead
        }
        guard ticket.acceptanceID == expectedAcceptanceID else {
            throw Error.jobIdentityMismatch
        }
        guard (try? ResolvedJobTicketJSON.encode(ticket)) == bytes else {
            throw Error.cannotRead
        }
        return ticket
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mapStorage(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .cannotCreate: .cannotCreateStore
        case .cannotOpen: .cannotOpenStore
        case .unsafeDirectory: .unsafeStoreDirectory
        case .cannotWrite, .conflict: .cannotWrite
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }
}
