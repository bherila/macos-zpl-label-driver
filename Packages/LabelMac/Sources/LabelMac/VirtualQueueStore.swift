import CryptoKit
import Darwin
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
        case queueConflict
        case queueIdentityMismatch
        case workflowReferenceMismatch
        case workflowNotQualified
        case printerReferenceMismatch
    }

    public let root: URL

    public init(root: URL) throws {
        self.root = root
        if mkdir(root.path, 0o700) != 0, errno != EEXIST { throw Error.cannotCreateStore }
        try withQueueDirectory { _ in }
    }

    public func save(
        _ queue: VirtualQueueDefinition,
        workflowStore: WorkflowProfileStore,
        printerProfile: PrinterProfile,
        printerProfileSHA256: String
    ) throws {
        try validateReferences(
            queue, workflowStore: workflowStore,
            printerProfile: printerProfile, printerProfileSHA256: printerProfileSHA256
        )
        let bytes = try VirtualQueueJSON.encode(queue)
        try withQueueDirectory { directory in
            try publishImmutable(bytes, named: Self.fileName(queue.id, queue.revision), in: directory)
        }
    }

    public func load(
        queueID: String,
        revision: Int,
        workflowStore: WorkflowProfileStore,
        printerProfile: PrinterProfile,
        printerProfileSHA256: String
    ) throws -> VirtualQueueDefinition {
        let bytes: Data
        do {
            bytes = try withQueueDirectory { directory in
                try readRegular(
                    named: Self.fileName(queueID, revision),
                    in: directory, maximumBytes: VirtualQueueJSON.maximumBytes
                )
            }
        } catch ReadError.notFound {
            throw Error.cannotRead
        }
        let queue = try VirtualQueueJSON.decode(bytes, validatingAgainst: printerProfile)
        guard queue.id == queueID, queue.revision == revision else {
            throw Error.queueIdentityMismatch
        }
        try validateReferences(
            queue, workflowStore: workflowStore,
            printerProfile: printerProfile, printerProfileSHA256: printerProfileSHA256
        )
        return queue
    }

    static func fileName(_ id: String, _ revision: Int) -> String {
        "\(digest(Data(id.utf8)))-r\(revision).json"
    }

    private func validateReferences(
        _ queue: VirtualQueueDefinition,
        workflowStore: WorkflowProfileStore,
        printerProfile: PrinterProfile,
        printerProfileSHA256: String
    ) throws {
        guard queue.printerProfile.schemaVersion == printerProfile.schemaVersion,
              queue.printerProfile.revision == printerProfile.revision,
              queue.printerProfile.sha256 == printerProfileSHA256 else {
            throw Error.printerReferenceMismatch
        }
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

    private enum ReadError: Swift.Error { case notFound }

    private func withQueueDirectory<T>(_ body: (Int32) throws -> T) throws -> T {
        let rootDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootDescriptor >= 0 else { throw Error.cannotOpenStore }
        defer { close(rootDescriptor) }
        try validateDirectory(rootDescriptor)
        if mkdirat(rootDescriptor, "queues", 0o700) != 0, errno != EEXIST {
            throw Error.cannotCreateStore
        }
        let queues = openat(
            rootDescriptor, "queues", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard queues >= 0 else { throw Error.cannotOpenStore }
        defer { close(queues) }
        try validateDirectory(queues)
        return try body(queues)
    }

    private func validateDirectory(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & 0o077) == 0 else {
            throw Error.unsafeStoreDirectory
        }
    }

    private func publishImmutable(_ data: Data, named name: String, in directory: Int32) throws {
        let temporary = ".tmp-\(UUID().uuidString)"
        let descriptor = openat(
            directory, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Error.cannotWrite }
        var shouldUnlink = true
        defer {
            close(descriptor)
            if shouldUnlink { unlinkat(directory, temporary, 0) }
        }
        try data.withUnsafeBytes { raw in
            guard var cursor = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, cursor, remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw Error.cannotWrite }
                remaining -= count
                cursor = cursor.advanced(by: count)
            }
        }
        guard fsync(descriptor) == 0 else { throw Error.cannotWrite }
        if renameatx_np(directory, temporary, directory, name, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST else { throw Error.cannotWrite }
            let existing = try readRegular(
                named: name, in: directory, maximumBytes: VirtualQueueJSON.maximumBytes
            )
            guard existing == data else { throw Error.queueConflict }
        } else {
            shouldUnlink = false
            guard fsync(directory) == 0 else { throw Error.cannotWrite }
        }
    }

    private func readRegular(named name: String, in directory: Int32, maximumBytes: Int) throws -> Data {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { throw ReadError.notFound }
        guard descriptor >= 0 else { throw Error.cannotRead }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1,
              before.st_size >= 0, before.st_size <= maximumBytes else {
            throw Error.cannotRead
        }
        var result = Data()
        result.reserveCapacity(Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: maximumBytes + 1)
        while result.count <= maximumBytes {
            let requested = min(buffer.count, maximumBytes - result.count + 1)
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, requested)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw Error.cannotRead }
            if count == 0 { break }
            result.append(contentsOf: buffer[0..<count])
        }
        guard result.count <= maximumBytes else { throw Error.cannotRead }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_uid == geteuid(), after.st_nlink == 1,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              after.st_size == result.count else {
            throw Error.cannotRead
        }
        return result
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
