import CryptoKit
import Darwin
import Foundation
import LabelCore

public struct AcceptedJobBundle: Equatable, Sendable {
    public let ticket: ResolvedJobTicket
    public let sourcePDF: Data
}

/// Private immutable publication of an accepted ticket and its exact original
/// PDF as one directory transaction. No rendered or printer-language payload is
/// stored here.
public struct AcceptedJobStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotCreateStore
        case cannotOpenStore
        case unsafeStoreDirectory
        case cannotRead
        case cannotWrite
        case commitUncertain
        case jobConflict
        case jobIdentityMismatch
        case sourceMismatch
        case queueReferenceMismatch
        case workflowReferenceMismatch
        case printerReferenceMismatch
    }

    enum FaultPoint: Equatable, Sendable {
        case afterTicketWrite
        case afterSourceWrite
        case beforeRename
        case afterRename
    }

    public let root: URL
    private let directoryName = "accepted-jobs"
    private let injectFault: @Sendable (FaultPoint) throws -> Void

    public init(root: URL) throws {
        try self.init(root: root, injectFault: { _ in })
    }

    init(
        root: URL,
        injectFault: @escaping @Sendable (FaultPoint) throws -> Void
    ) throws {
        self.root = root
        self.injectFault = injectFault
        if mkdir(root.path, 0o700) != 0, errno != EEXIST { throw Error.cannotCreateStore }
        let rootDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootDescriptor >= 0 else { throw Error.cannotOpenStore }
        defer { close(rootDescriptor) }
        try Self.validateDirectory(rootDescriptor)
        if mkdirat(rootDescriptor, directoryName, 0o700) != 0, errno != EEXIST {
            throw Error.cannotCreateStore
        }
        let directory = openat(
            rootDescriptor, directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else { throw Error.cannotOpenStore }
        defer { close(directory) }
        try Self.validateDirectory(directory)
    }

    public func save(
        _ ticket: ResolvedJobTicket,
        sourcePDF: Data,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws {
        let ticketBytes = try ResolvedJobTicketJSON.encode(ticket)
        try Self.validateSource(sourcePDF, ticket: ticket)
        _ = try validateTicket(
            ticketBytes, sourcePDF: sourcePDF,
            expectedAcceptanceID: ticket.acceptanceID,
            queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore
        )
        try withStoreDirectory { directory in
            let finalName = Self.directoryName(ticket.acceptanceID)
            let temporaryName = ".tmp-\(UUID().uuidString)"
            guard mkdirat(directory, temporaryName, 0o700) == 0 else {
                throw Error.cannotWrite
            }
            var removeTemporary = true
            defer {
                if removeTemporary {
                    Self.removeTemporaryBundle(parent: directory, name: temporaryName)
                }
            }
            let temporary = openat(
                directory, temporaryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard temporary >= 0 else { throw Error.cannotWrite }
            defer { close(temporary) }
            try Self.write(
                ticketBytes, name: "ticket.json", directory: temporary,
                maximumBytes: ResolvedJobTicketJSON.maximumBytes
            )
            try injectFault(.afterTicketWrite)
            try Self.write(
                sourcePDF, name: "source.pdf", directory: temporary,
                maximumBytes: ResolvedJobTicket.maximumSourceBytes
            )
            try injectFault(.afterSourceWrite)
            guard fsync(temporary) == 0 else { throw Error.cannotWrite }
            try injectFault(.beforeRename)

            if renameatx_np(
                directory, temporaryName, directory, finalName, UInt32(RENAME_EXCL)
            ) != 0 {
                guard errno == EEXIST else { throw Error.cannotWrite }
                let existing = try readBundleBytes(
                    directory: directory, name: finalName
                )
                guard existing.ticket == ticketBytes, existing.source == sourcePDF else {
                    throw Error.jobConflict
                }
                return
            }
            removeTemporary = false
            do { try injectFault(.afterRename) }
            catch { throw Error.commitUncertain }
            // The rename is visible. Failure to confirm parent durability is
            // not safely distinguishable from a committed publication.
            guard fsync(directory) == 0 else { throw Error.commitUncertain }
        }
    }

    public func load(
        acceptanceID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobBundle {
        try Self.validateAcceptanceID(acceptanceID)
        return try withStoreDirectory { directory in
            let bytes = try readBundleBytes(
                directory: directory, name: Self.directoryName(acceptanceID)
            )
            let ticket = try validateTicket(
                bytes.ticket, sourcePDF: bytes.source,
                expectedAcceptanceID: acceptanceID,
                queueStore: queueStore, workflowStore: workflowStore,
                printerStore: printerStore
            )
            return AcceptedJobBundle(ticket: ticket, sourcePDF: bytes.source)
        }
    }

    static func directoryName(_ acceptanceID: String) -> String {
        digest(Data(acceptanceID.utf8))
    }

    private func validateTicket(
        _ bytes: Data,
        sourcePDF: Data,
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
        try Self.validateSource(sourcePDF, ticket: ticket)
        return ticket
    }

    private func withStoreDirectory<T>(_ body: (Int32) throws -> T) throws -> T {
        let rootDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootDescriptor >= 0 else { throw Error.cannotOpenStore }
        defer { close(rootDescriptor) }
        try Self.validateDirectory(rootDescriptor)
        let directory = openat(
            rootDescriptor, directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else { throw Error.cannotOpenStore }
        defer { close(directory) }
        try Self.validateDirectory(directory)
        return try body(directory)
    }

    private func readBundleBytes(
        directory: Int32, name: String
    ) throws -> (ticket: Data, source: Data) {
        let bundle = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard bundle >= 0 else { throw Error.cannotRead }
        defer { close(bundle) }
        try Self.validateDirectory(bundle)
        return (
            try Self.read(
                name: "ticket.json", directory: bundle,
                maximumBytes: ResolvedJobTicketJSON.maximumBytes
            ),
            try Self.read(
                name: "source.pdf", directory: bundle,
                maximumBytes: ResolvedJobTicket.maximumSourceBytes
            )
        )
    }

    private static func validateSource(
        _ sourcePDF: Data, ticket: ResolvedJobTicket
    ) throws {
        guard !sourcePDF.isEmpty,
              sourcePDF.count == ticket.sourceByteCount,
              digest(sourcePDF) == ticket.sourceDocumentSHA256 else {
            throw Error.sourceMismatch
        }
    }

    private static func validateAcceptanceID(_ acceptanceID: String) throws {
        guard (try? ImmutableProfileReference(
            id: acceptanceID, revision: 1,
            sha256: String(repeating: "0", count: 64)
        )) != nil else {
            throw Error.jobIdentityMismatch
        }
    }

    private static func write(
        _ data: Data, name: String, directory: Int32, maximumBytes: Int
    ) throws {
        guard !data.isEmpty, data.count <= maximumBytes else { throw Error.cannotWrite }
        let descriptor = openat(
            directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Error.cannotWrite }
        defer { close(descriptor) }
        try data.withUnsafeBytes { raw in
            guard var cursor = raw.baseAddress else { throw Error.cannotWrite }
            var remaining = raw.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, cursor, remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw Error.cannotWrite }
                cursor = cursor.advanced(by: count)
                remaining -= count
            }
        }
        guard fsync(descriptor) == 0 else { throw Error.cannotWrite }
    }

    private static func read(
        name: String, directory: Int32, maximumBytes: Int
    ) throws -> Data {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Error.cannotRead }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1,
              (before.st_mode & 0o077) == 0,
              before.st_size > 0, before.st_size <= maximumBytes else {
            throw Error.cannotRead
        }
        var result = Data(count: Int(before.st_size))
        var offset = 0
        while offset < result.count {
            let count = result.withUnsafeMutableBytes { raw in
                Darwin.read(descriptor, raw.baseAddress?.advanced(by: offset), raw.count - offset)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw Error.cannotRead }
            offset += count
        }
        var extra: UInt8 = 0
        var extraCount: Int
        repeat { extraCount = Darwin.read(descriptor, &extra, 1) }
        while extraCount < 0 && errno == EINTR
        guard extraCount == 0 else { throw Error.cannotRead }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw Error.cannotRead
        }
        return result
    }

    private static func removeTemporaryBundle(parent: Int32, name: String) {
        let directory = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if directory >= 0 {
            _ = unlinkat(directory, "ticket.json", 0)
            _ = unlinkat(directory, "source.pdf", 0)
            close(directory)
        }
        _ = unlinkat(parent, name, AT_REMOVEDIR)
    }

    private static func validateDirectory(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & 0o077) == 0 else {
            throw Error.unsafeStoreDirectory
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
