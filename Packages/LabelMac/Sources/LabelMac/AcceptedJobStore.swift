import CryptoKit
import Darwin
import Foundation
import LabelCore

public struct AcceptedJobBundle: Equatable, Sendable {
    public let ticket: ResolvedJobTicket
    public let acceptedTicketSHA256: String
    public let sourcePDF: Data
}

/// Bounded, read-only discovery of the private accepted-job namespace. Job
/// identities are returned for in-process reconciliation and must not be
/// written to general logs.
public struct AcceptedJobInventorySnapshot: Equatable, Sendable {
    public let acceptanceIDs: [String]
    public let stagedArtifactCount: Int
    public let invalidArtifactCount: Int
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
        case invalidInventoryLimit
        case inventoryLimitExceeded
        case inventorySourceLimitExceeded
        case inventoryPreparedLimitExceeded
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

    /// Returns nil only when the immutable bundle name is absent. A present
    /// but unreadable, unsafe, or invalid bundle remains an error and must not
    /// be treated as permission to create a replacement job.
    public func loadIfPresent(
        acceptanceID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobBundle? {
        try Self.validateAcceptanceID(acceptanceID)
        let exists = try withStoreDirectory { directory in
            var information = stat()
            if fstatat(
                directory, Self.directoryName(acceptanceID),
                &information, AT_SYMLINK_NOFOLLOW
            ) == 0 {
                return true
            }
            guard errno == ENOENT else { throw Error.cannotRead }
            return false
        }
        guard exists else { return nil }
        return try load(
            acceptanceID: acceptanceID, queueStore: queueStore,
            workflowStore: workflowStore, printerStore: printerStore
        )
    }

    /// Inventories final and unpublished staging entries through the pinned
    /// store-directory capability. It never deletes, repairs, or changes a job.
    /// Invalid entries are counted rather than silently treated as absent.
    /// Concurrent publication may change what is observed; this is not an
    /// atomic namespace snapshot or permission to discard upstream jobs.
    public func inventory(
        maximumEntries: Int = 4_096,
        maximumSourceBytes: Int = 512 * 1024 * 1024,
        maximumPreparedBytes: Int = 512 * 1024 * 1024,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobInventorySnapshot {
        guard (1...4_096).contains(maximumEntries),
              (1...(1024 * 1024 * 1024)).contains(maximumSourceBytes),
              (1...(1024 * 1024 * 1024)).contains(maximumPreparedBytes) else {
            throw Error.invalidInventoryLimit
        }
        return try withStoreDirectory { directory in
            let scanDescriptor = openat(
                directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard scanDescriptor >= 0 else { throw Error.cannotRead }
            guard let stream = fdopendir(scanDescriptor) else {
                close(scanDescriptor)
                throw Error.cannotRead
            }
            defer { closedir(stream) }

            var acceptanceIDs: [String] = []
            var stagedArtifactCount = 0
            var invalidArtifactCount = 0
            var entryCount = 0
            var remainingSourceBytes = maximumSourceBytes
            var remainingPreparedBytes = maximumPreparedBytes
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw Error.cannotRead }
                    break
                }
                guard let name = Self.entryName(entry) else {
                    entryCount += 1
                    guard entryCount <= maximumEntries else {
                        throw Error.inventoryLimitExceeded
                    }
                    invalidArtifactCount += 1
                    continue
                }
                if name == "." || name == ".." { continue }
                entryCount += 1
                guard entryCount <= maximumEntries else {
                    throw Error.inventoryLimitExceeded
                }
                if name.hasPrefix(".tmp-") {
                    if Self.isStagingDirectoryName(name),
                       Self.isOwnedPrivateDirectory(parent: directory, name: name) {
                        stagedArtifactCount += 1
                    } else {
                        invalidArtifactCount += 1
                    }
                    continue
                }
                guard Self.isPublishedDirectoryName(name) else {
                    invalidArtifactCount += 1
                    continue
                }
                do {
                    let declaredSourceBytes = try declaredSourceByteCount(
                        directory: directory, name: name
                    )
                    guard declaredSourceBytes <= remainingSourceBytes else {
                        throw Error.inventorySourceLimitExceeded
                    }
                    // Reserve the read budget before source ingestion, even
                    // if subsequent source/state validation fails.
                    remainingSourceBytes -= declaredSourceBytes
                    let bytes = try readBundleBytes(
                        directory: directory,
                        name: name,
                        maximumSourceBytes: declaredSourceBytes
                    )
                    if let preparedCount = Self.preparedByteCount(bytes.state.phase) {
                        guard preparedCount <= PreparedJobPayload.maximumBytes else {
                            throw Error.cannotRead
                        }
                        guard preparedCount <= remainingPreparedBytes else {
                            throw Error.inventoryPreparedLimitExceeded
                        }
                        remainingPreparedBytes -= preparedCount
                    }
                    let acceptanceID = try ResolvedJobTicketJSON.acceptanceID(bytes.ticket)
                    guard Self.directoryName(acceptanceID) == name else {
                        throw Error.jobIdentityMismatch
                    }
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
                    acceptanceIDs.append(ticket.acceptanceID)
                } catch Error.inventorySourceLimitExceeded {
                    throw Error.inventorySourceLimitExceeded
                } catch Error.inventoryPreparedLimitExceeded {
                    throw Error.inventoryPreparedLimitExceeded
                } catch {
                    invalidArtifactCount += 1
                }
            }
            return AcceptedJobInventorySnapshot(
                acceptanceIDs: acceptanceIDs.sorted(),
                stagedArtifactCount: stagedArtifactCount,
                invalidArtifactCount: invalidArtifactCount
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
        directory: Int32,
        name: String,
        maximumSourceBytes: Int? = nil
    ) throws -> (ticket: Data, source: Data, state: AcceptedJobStateRecord) {
        let bundle = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard bundle >= 0 else { throw Error.cannotRead }
        defer { close(bundle) }
        try Self.validateDirectory(bundle)
        let ticket = try Self.read(
                name: "ticket.json", directory: bundle,
                maximumBytes: ResolvedJobTicketJSON.maximumBytes
            )
        if let maximumSourceBytes {
            let declaredSourceBytes: Int
            do { declaredSourceBytes = try ResolvedJobTicketJSON.sourceByteCount(ticket) }
            catch { throw Error.cannotRead }
            guard declaredSourceBytes <= maximumSourceBytes else {
                throw Error.inventorySourceLimitExceeded
            }
        }
        let source = try Self.read(
                name: "source.pdf", directory: bundle,
                maximumBytes: maximumSourceBytes ?? ResolvedJobTicket.maximumSourceBytes
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

    private func declaredSourceByteCount(directory: Int32, name: String) throws -> Int {
        let bundle = openat(
            directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard bundle >= 0 else { throw Error.cannotRead }
        defer { close(bundle) }
        try Self.validateDirectory(bundle)
        let ticket = try Self.read(
            name: "ticket.json", directory: bundle,
            maximumBytes: ResolvedJobTicketJSON.maximumBytes
        )
        do { return try ResolvedJobTicketJSON.sourceByteCount(ticket) }
        catch { throw Error.cannotRead }
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

    private static func entryName(_ entry: UnsafeMutablePointer<dirent>) -> String? {
        let length = Int(entry.pointee.d_namlen)
        guard length > 0, length <= Int(MAXNAMLEN) else { return nil }
        return withUnsafePointer(to: entry.pointee.d_name) { name in
            name.withMemoryRebound(to: UInt8.self, capacity: length) { bytes in
                String(bytes: UnsafeBufferPointer(start: bytes, count: length), encoding: .utf8)
            }
        }
    }

    private static func isPublishedDirectoryName(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func preparedByteCount(_ phase: AcceptedJobPhase) -> Int? {
        switch phase {
        case let .prepared(_, count), let .waiting(_, count),
             let .transmitting(_, count, _), let .transmitted(_, count),
             let .deviceConfirmed(_, count), let .uncertain(_, count, _):
            return count
        case .accepted, .failedBeforeTransmission, .cancelledBeforeTransmission:
            return nil
        }
    }

    private static func isStagingDirectoryName(_ value: String) -> Bool {
        guard value.utf8.count == 41, value.hasPrefix(".tmp-") else { return false }
        return UUID(uuidString: String(value.dropFirst(5))) != nil
    }

    private static func isOwnedPrivateDirectory(parent: Int32, name: String) -> Bool {
        let descriptor = openat(
            parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return (try? validateDirectory(descriptor)) != nil
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
