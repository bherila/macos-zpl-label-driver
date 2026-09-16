import Darwin
import Foundation

public struct ImmutablePublicationIdentity: Equatable, Sendable {
    public let id: String
    public let schemaVersion: Int
    public let revision: Int
    public let sha256: String

    init(id: String, schemaVersion: Int, revision: Int, sha256: String) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.sha256 = sha256
    }
}

/// Shared descriptor-relative storage primitive for private immutable product
/// configuration. Public stores map these internal errors to domain errors.
struct PrivateImmutableDirectory: @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case cannotCreate
        case cannotOpen
        case unsafeDirectory
        case cannotRead
        case notFound
        case cannotWrite
        case commitUncertain
        case conflict
    }

    enum FaultPoint: Equatable, Sendable {
        case beforeRename
    }

    let root: URL
    private let syncDirectory: @Sendable (Int32) -> Int32
    private let injectFault: @Sendable (FaultPoint) throws -> Void

    init(root: URL) throws {
        try self.init(
            root: root, syncDirectory: { fsync($0) }, injectFault: { _ in }
        )
    }

    init(
        root: URL,
        syncDirectory: @escaping @Sendable (Int32) -> Int32 = { fsync($0) },
        injectFault: @escaping @Sendable (FaultPoint) throws -> Void = { _ in }
    ) throws {
        self.root = root
        self.syncDirectory = syncDirectory
        self.injectFault = injectFault
        if mkdir(root.path, 0o700) != 0, errno != EEXIST { throw Error.cannotCreate }
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Error.cannotOpen }
        defer { close(descriptor) }
        try Self.validateDirectory(descriptor)
    }

    func publish(
        _ data: Data,
        directory name: String,
        fileName: String,
        maximumBytes: Int
    ) throws {
        guard data.count <= maximumBytes else { throw Error.cannotWrite }
        try withDirectory(name, syncRootAfterBody: true) { directory in
            if try reconcileExisting(
                data, directory: directory, fileName: fileName,
                maximumBytes: maximumBytes
            ) { return }
            do {
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
                do { try injectFault(.beforeRename) }
                catch { throw Error.cannotWrite }
                if renameatx_np(
                    directory, temporary, directory, fileName, UInt32(RENAME_EXCL)
                ) != 0 {
                    guard errno == EEXIST else { throw Error.cannotWrite }
                    guard try reconcileExisting(
                        data, directory: directory, fileName: fileName,
                        maximumBytes: maximumBytes
                    ) else { throw Error.cannotWrite }
                } else {
                    shouldUnlink = false
                    guard syncDirectory(directory) == 0 else {
                        throw Error.commitUncertain
                    }
                }
            } catch let failure as Error {
                if failure == .conflict || failure == .commitUncertain {
                    throw failure
                }
                if try reconcileExisting(
                    data, directory: directory, fileName: fileName,
                    maximumBytes: maximumBytes
                ) { return }
                throw failure
            }
        }
    }

    func read(directory name: String, fileName: String, maximumBytes: Int) throws -> Data {
        try withDirectory(name) { directory in
            try read(
                directoryDescriptor: directory,
                fileName: fileName,
                maximumBytes: maximumBytes
            )
        }
    }

    /// A bounded catalog, not an atomic snapshot of the entire namespace.
    /// Every candidate is opened relative to the same validated directory.
    func catalog(directory name: String, maximumRecords: Int,
        maximumRecordBytes: Int, maximumTotalBytes: Int
    ) throws -> [(name: String, data: Data)] {
        guard (1...256).contains(maximumRecords), maximumRecordBytes > 0,
              maximumRecordBytes <= 256 * 1024,
              maximumTotalBytes > 0, maximumTotalBytes <= 64 * 1024 * 1024 else {
            throw Error.cannotRead
        }
        return try withDirectory(name) { directory in
            // Reopen '.', not dup: enumeration must not share directory offsets.
            let enumeration = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard enumeration >= 0 else { throw Error.cannotRead }
            guard let stream = fdopendir(enumeration) else {
                close(enumeration)
                throw Error.cannotRead
            }
            defer { closedir(stream) }
            var result: [(name: String, data: Data)] = []
            var entries = 0
            var totalBytes = 0
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw Error.cannotRead }
                    break
                }
                entries += 1
                guard entries <= 4096 else { throw Error.cannotRead }
                let fileName = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(validatingUTF8: $0)
                    }
                }
                // Unpublished hidden staging records are never catalog entries.
                guard let fileName else { throw Error.cannotRead }
                guard !fileName.hasPrefix("."), fileName.hasSuffix(".json") else { continue }
                guard result.count < maximumRecords else { throw Error.cannotRead }
                let data = try read(directoryDescriptor: directory, fileName: fileName,
                    maximumBytes: min(maximumRecordBytes, maximumTotalBytes - totalBytes))
                totalBytes += data.count
                result.append((fileName, data))
            }
            return result
        }
    }

    private func withDirectory<T>(
        _ name: String,
        syncRootAfterBody: Bool = false,
        body: (Int32) throws -> T
    ) throws -> T {
        let rootDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootDescriptor >= 0 else { throw Error.cannotOpen }
        defer { close(rootDescriptor) }
        try Self.validateDirectory(rootDescriptor)
        if mkdirat(rootDescriptor, name, 0o700) != 0, errno != EEXIST {
            throw Error.cannotCreate
        }
        let directory = openat(
            rootDescriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else { throw Error.cannotOpen }
        defer { close(directory) }
        try Self.validateDirectory(directory)
        let result = try body(directory)
        if syncRootAfterBody {
            guard syncDirectory(rootDescriptor) == 0 else {
                throw Error.commitUncertain
            }
            try syncContainingDirectory(of: rootDescriptor)
        }
        return result
    }

    private func reconcileExisting(
        _ expected: Data,
        directory: Int32,
        fileName: String,
        maximumBytes: Int
    ) throws -> Bool {
        let existing: Data
        do {
            existing = try read(
                directoryDescriptor: directory, fileName: fileName,
                maximumBytes: maximumBytes
            )
        } catch Error.notFound {
            return false
        }
        guard existing == expected else { throw Error.conflict }
        guard syncDirectory(directory) == 0 else { throw Error.commitUncertain }
        return true
    }

    private func syncContainingDirectory(of rootDescriptor: Int32) throws {
        let name = root.lastPathComponent
        let parentURL = root.deletingLastPathComponent()
        guard !name.isEmpty, parentURL.path != root.path else {
            throw Error.commitUncertain
        }
        let parent = open(
            parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard parent >= 0 else { throw Error.commitUncertain }
        defer { close(parent) }
        let reopened = openat(
            parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard reopened >= 0 else { throw Error.commitUncertain }
        defer { close(reopened) }
        do {
            try Self.validateDirectory(reopened)
        } catch {
            throw Error.commitUncertain
        }
        var originalInfo = stat()
        var reopenedInfo = stat()
        guard fstat(rootDescriptor, &originalInfo) == 0,
              fstat(reopened, &reopenedInfo) == 0,
              originalInfo.st_dev == reopenedInfo.st_dev,
              originalInfo.st_ino == reopenedInfo.st_ino,
              syncDirectory(parent) == 0 else {
            throw Error.commitUncertain
        }
    }

    private func read(
        directoryDescriptor: Int32,
        fileName: String,
        maximumBytes: Int
    ) throws -> Data {
        guard maximumBytes > 0 else { throw Error.cannotRead }
        let descriptor = NonblockingRegularFileDescriptor.open(
            at: directoryDescriptor, name: fileName
        )
        if descriptor < 0, errno == ENOENT { throw Error.notFound }
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
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, maximumBytes + 1))
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

    private static func validateDirectory(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & 0o077) == 0 else {
            throw Error.unsafeDirectory
        }
    }
}
