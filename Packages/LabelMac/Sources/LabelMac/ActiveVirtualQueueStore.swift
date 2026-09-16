import CryptoKit
import Darwin
import Foundation
import LabelCore

/// Private mutable pointer to an immutable virtual-queue revision.
///
/// Publication is serialized with a descriptor-relative `flock`, compares the
/// complete expected selection, and replaces canonical bytes atomically. This
/// does not create or modify a scheduler queue.
public struct ActiveVirtualQueueStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotCreateStore
        case cannotOpenStore
        case unsafeStoreDirectory
        case cannotRead
        case cannotWrite
        case commitUncertain
        case selectionConflict
        case queueReferenceMismatch
        case invalidTransition
    }

    public let root: URL
    private let directoryName = "active-queues"

    public init(root: URL) throws {
        self.root = root
        if mkdir(root.path, 0o700) != 0, errno != EEXIST {
            throw Error.cannotCreateStore
        }
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

    public func load(
        queueID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> ActiveVirtualQueueSelection? {
        try withLockedDirectory(queueID: queueID) { directory, stem in
            guard let selection = try read(directory: directory, stem: stem) else { return nil }
            try validate(
                selection, queueID: queueID, queueStore: queueStore,
                workflowStore: workflowStore, printerStore: printerStore
            )
            return selection
        }
    }

    /// Activates `queue` only if the complete on-disk selection equals
    /// `expected`. Pass nil only for the initial publication.
    @discardableResult
    public func compareAndSwap(
        queue: ImmutableProfileReference,
        expected: ActiveVirtualQueueSelection?,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> ActiveVirtualQueueSelection {
        do {
            _ = try queueStore.load(
                reference: queue, workflowStore: workflowStore, printerStore: printerStore
            )
        } catch {
            throw Error.queueReferenceMismatch
        }
        return try withLockedDirectory(queueID: queue.id) { directory, stem in
            let current = try read(directory: directory, stem: stem)
            if let current {
                try validate(
                    current, queueID: queue.id, queueStore: queueStore,
                    workflowStore: workflowStore, printerStore: printerStore
                )
            }
            guard current == expected else { throw Error.selectionConflict }
            guard expected == nil || expected?.queue.id == queue.id,
                  expected?.queue != queue,
                  expected?.generation != Int.max else {
                throw Error.invalidTransition
            }
            let next: ActiveVirtualQueueSelection
            do {
                next = try ActiveVirtualQueueSelection(
                    generation: (expected?.generation ?? 0) + 1,
                    queue: queue,
                    previousQueueSHA256: expected?.queue.sha256
                )
            } catch {
                throw Error.invalidTransition
            }
            let bytes: Data
            do { bytes = try ActiveVirtualQueueJSON.encode(next) }
            catch { throw Error.cannotWrite }
            try replace(bytes, directory: directory, stem: stem)
            return next
        }
    }

    static func fileStem(_ queueID: String) -> String {
        SHA256.hash(data: Data(queueID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func validate(
        _ selection: ActiveVirtualQueueSelection,
        queueID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws {
        guard selection.queue.id == queueID else { throw Error.cannotRead }
        do {
            _ = try queueStore.load(
                reference: selection.queue,
                workflowStore: workflowStore,
                printerStore: printerStore
            )
        } catch {
            throw Error.queueReferenceMismatch
        }
    }

    private func withLockedDirectory<T>(
        queueID: String,
        body: (Int32, String) throws -> T
    ) throws -> T {
        do {
            _ = try ImmutableProfileReference(
                id: queueID, revision: 1, sha256: String(repeating: "0", count: 64)
            )
        } catch {
            throw Error.queueReferenceMismatch
        }
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

        let stem = Self.fileStem(queueID)
        let lock = openat(
            directory, ".\(stem).lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
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
        return try body(directory, stem)
    }

    private func read(directory: Int32, stem: String) throws -> ActiveVirtualQueueSelection? {
        let descriptor = openat(directory, "\(stem).json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw Error.cannotRead }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1,
              before.st_size >= 0, before.st_size <= ActiveVirtualQueueJSON.maximumBytes else {
            throw Error.cannotRead
        }
        var bytes = Data(count: Int(before.st_size))
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { raw in
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
        do { return try ActiveVirtualQueueJSON.decode(bytes) }
        catch { throw Error.cannotRead }
    }

    private func replace(_ bytes: Data, directory: Int32, stem: String) throws {
        guard bytes.count <= ActiveVirtualQueueJSON.maximumBytes else { throw Error.cannotWrite }
        let temporary = ".tmp-\(UUID().uuidString)"
        let descriptor = openat(
            directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Error.cannotWrite }
        var removeTemporary = true
        defer {
            close(descriptor)
            if removeTemporary { unlinkat(directory, temporary, 0) }
        }
        do {
            try bytes.withUnsafeBytes { raw in
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
            guard fsync(descriptor) == 0,
                  renameat(directory, temporary, directory, "\(stem).json") == 0 else {
                throw Error.cannotWrite
            }
            removeTemporary = false
            // The rename is already visible. A directory-fsync failure cannot
            // safely be reported as a retryable pre-commit write failure.
            guard fsync(directory) == 0 else { throw Error.commitUncertain }
        } catch let error as Error {
            throw error
        } catch {
            throw Error.cannotWrite
        }
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
}
