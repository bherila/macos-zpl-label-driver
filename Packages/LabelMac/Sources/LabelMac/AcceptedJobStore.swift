import CryptoKit
import Darwin
import Foundation
import LabelCore

public struct AcceptedJobBundle: Equatable, Sendable {
    public let ticket: ResolvedJobTicket
    public let acceptedTicketSHA256: String
    public let sourcePDF: Data
}

private final class AcceptedJobDirectoryCapability: @unchecked Sendable {
    let descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }
}

/// Private immutable publication of an accepted ticket and its exact original
/// PDF as one directory transaction. A prepared artifact may be appended later
/// only through `AcceptedJobStateStore` under the bundle's lifecycle lock.
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
        case afterStateWrite
        case beforeRename
        case afterRename
    }

    public let root: URL
    private let directoryName = "accepted-jobs"
    private let directoryCapability: AcceptedJobDirectoryCapability
    private let syncParentDirectory: @Sendable (Int32) -> Int32
    private let injectFault: @Sendable (FaultPoint) throws -> Void

    public init(root: URL) throws {
        try self.init(
            root: root, syncParentDirectory: { fsync($0) },
            injectFault: { _ in }
        )
    }

    init(
        root: URL,
        injectFault: @escaping @Sendable (FaultPoint) throws -> Void
    ) throws {
        try self.init(
            root: root, syncParentDirectory: { fsync($0) },
            injectFault: injectFault
        )
    }

    init(
        root: URL,
        syncParentDirectory: @escaping @Sendable (Int32) -> Int32,
        injectFault: @escaping @Sendable (FaultPoint) throws -> Void = { _ in }
    ) throws {
        self.root = root
        self.syncParentDirectory = syncParentDirectory
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
        do {
            try Self.validateDirectory(directory)
        } catch {
            close(directory)
            throw error
        }
        self.directoryCapability = AcceptedJobDirectoryCapability(descriptor: directory)
    }

    public func save(
        _ ticket: ResolvedJobTicket,
        sourcePDF: Data,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws {
        let ticketBytes = try ResolvedJobTicketJSON.encode(ticket)
        let ticketDigest = Self.digest(ticketBytes)
        let stateBytes = try AcceptedJobStateJSON.encode(
            AcceptedJobStateRecord.accepted(
                acceptanceID: ticket.acceptanceID,
                acceptedTicketSHA256: ticketDigest
            )
        )
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
            try Self.write(
                stateBytes, name: "state.json", directory: temporary,
                maximumBytes: AcceptedJobStateJSON.maximumBytes
            )
            try injectFault(.afterStateWrite)
            guard fsync(temporary) == 0 else { throw Error.cannotWrite }
            try injectFault(.beforeRename)

            if renameatx_np(
                directory, temporaryName, directory, finalName, UInt32(RENAME_EXCL)
            ) != 0 {
                guard errno == EEXIST else { throw Error.cannotWrite }
                let existing = try readBundleBytes(
                    directory: directory, name: finalName
                )
                guard existing.ticket == ticketBytes, existing.source == sourcePDF,
                      existing.state.acceptanceID == ticket.acceptanceID,
                      existing.state.acceptedTicketSHA256 == ticketDigest else {
                    throw Error.jobConflict
                }
                guard syncParentDirectory(directory) == 0 else {
                    throw Error.commitUncertain
                }
                return
            }
            removeTemporary = false
            do { try injectFault(.afterRename) }
            catch { throw Error.commitUncertain }
            // The rename is visible. Failure to confirm parent durability is
            // not safely distinguishable from a committed publication.
            guard syncParentDirectory(directory) == 0 else { throw Error.commitUncertain }
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
            let ticketDigest = Self.digest(bytes.ticket)
            guard bytes.state.acceptanceID == ticket.acceptanceID,
                  bytes.state.acceptedTicketSHA256 == ticketDigest else {
                throw Error.jobIdentityMismatch
            }
            return AcceptedJobBundle(
                ticket: ticket,
                acceptedTicketSHA256: ticketDigest,
                sourcePDF: bytes.source
            )
        }
    }

    func loadBundle(
        from bundle: Int32,
        acceptanceID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobBundle {
        try Self.validateAcceptanceID(acceptanceID)
        try Self.validateDirectory(bundle)
        let ticketBytes = try Self.read(
            name: "ticket.json", directory: bundle,
            maximumBytes: ResolvedJobTicketJSON.maximumBytes
        )
        let source = try Self.read(
            name: "source.pdf", directory: bundle,
            maximumBytes: ResolvedJobTicket.maximumSourceBytes
        )
        let ticket = try validateTicket(
            ticketBytes, sourcePDF: source,
            expectedAcceptanceID: acceptanceID,
            queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore
        )
        return AcceptedJobBundle(
            ticket: ticket,
            acceptedTicketSHA256: Self.digest(ticketBytes),
            sourcePDF: source
        )
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
        let directory = fcntl(directoryCapability.descriptor, F_DUPFD_CLOEXEC, 0)
        guard directory >= 0 else { throw Error.cannotOpenStore }
        defer { close(directory) }
        try Self.validateDirectory(directory)
        return try body(directory)
    }

    func withLockedBundle<T>(
        acceptanceID: String,
        body: (Int32) throws -> T
    ) throws -> T {
        try Self.validateAcceptanceID(acceptanceID)
        return try withStoreDirectory { jobs in
            let bundle = openat(
                jobs, Self.directoryName(acceptanceID),
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard bundle >= 0 else { throw Error.cannotOpenStore }
            defer { close(bundle) }
            try Self.validateDirectory(bundle)
            let lock = openat(
                bundle, ".state.lock",
                O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
            guard lock >= 0 else { throw Error.cannotOpenStore }
            defer { close(lock) }
            var info = stat()
            guard fstat(lock, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_uid == geteuid(), info.st_nlink == 1,
                  (info.st_mode & 0o077) == 0 else {
                throw Error.unsafeStoreDirectory
            }
            while flock(lock, LOCK_EX) != 0 {
                if errno == EINTR { continue }
                throw Error.cannotOpenStore
            }
            defer { _ = flock(lock, LOCK_UN) }
            return try body(bundle)
        }
    }

    private func readBundleBytes(
        directory: Int32, name: String
    ) throws -> (ticket: Data, source: Data, state: AcceptedJobStateRecord) {
        let bundle = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard bundle >= 0 else { throw Error.cannotRead }
        defer { close(bundle) }
        try Self.validateDirectory(bundle)
        let ticket = try Self.read(
                name: "ticket.json", directory: bundle,
                maximumBytes: ResolvedJobTicketJSON.maximumBytes
            )
        let source = try Self.read(
                name: "source.pdf", directory: bundle,
                maximumBytes: ResolvedJobTicket.maximumSourceBytes
            )
        let stateBytes = try Self.read(
            name: "state.json", directory: bundle,
            maximumBytes: AcceptedJobStateJSON.maximumBytes
        )
        let state: AcceptedJobStateRecord
        if let current = try? AcceptedJobStateJSON.decode(stateBytes),
           (try? AcceptedJobStateJSON.encode(current)) == stateBytes {
            state = current
        } else {
            do {
                state = try AcceptedJobStateJSON.migrateLegacyV1(
                    stateBytes, acceptedTicketSHA256: Self.digest(ticket)
                )
            } catch { throw Error.cannotRead }
        }
        return (ticket, source, state)
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
        let descriptor = NonblockingRegularFileDescriptor.open(at: directory, name: name)
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
            _ = unlinkat(directory, "state.json", 0)
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
