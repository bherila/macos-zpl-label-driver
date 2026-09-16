import Darwin
import Foundation

/// Reads an already-existing regular file through one no-follow descriptor.
/// The byte cap is enforced while reading, not merely before allocation.
public enum BoundedRegularFile {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimit
        case cannotOpen
        case notRegular
        case unexpectedOwner
        case unexpectedLinkCount
        case tooLarge
        case changedDuringRead
        case readFailed
    }

    public static func read(
        _ url: URL,
        maximumBytes: Int,
        requireCurrentUserOwner: Bool = false,
        requireSingleLink: Bool = false
    ) throws -> Data {
        guard maximumBytes > 0, maximumBytes < Int.max else { throw Error.invalidLimit }
        let descriptor = NonblockingRegularFileDescriptor.open(path: url.path)
        guard descriptor >= 0 else { throw Error.cannotOpen }
        defer { close(descriptor) }
        return try read(
            openFileDescriptor: descriptor,
            maximumBytes: maximumBytes,
            requireCurrentUserOwner: requireCurrentUserOwner,
            requireSingleLink: requireSingleLink
        )
    }

    /// Reads the regular file already named by `descriptor` without changing
    /// its shared file offset or resolving a pathname again. The caller keeps
    /// ownership of the descriptor. This is the intake form used when an
    /// upstream scheduler has already opened the submitted document.
    public static func read(
        openFileDescriptor descriptor: Int32,
        maximumBytes: Int,
        requireCurrentUserOwner: Bool = false,
        requireSingleLink: Bool = false
    ) throws -> Data {
        guard maximumBytes > 0, maximumBytes < Int.max else { throw Error.invalidLimit }
        guard descriptor >= 0 else { throw Error.cannotOpen }

        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw Error.readFailed }
        try validate(
            before,
            maximumBytes: maximumBytes,
            requireCurrentUserOwner: requireCurrentUserOwner,
            requireSingleLink: requireSingleLink
        )

        let expectedCount = Int(before.st_size)
        var data = Data(count: expectedCount)
        var offset = 0
        while offset < expectedCount {
            let count = data.withUnsafeMutableBytes { raw in
                pread(
                    descriptor, raw.baseAddress?.advanced(by: offset),
                    raw.count - offset, off_t(offset)
                )
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw Error.readFailed }
            offset += count
        }
        var sentinel: UInt8 = 0
        var sentinelCount: Int
        repeat {
            sentinelCount = pread(descriptor, &sentinel, 1, off_t(expectedCount))
        } while sentinelCount < 0 && errno == EINTR
        guard sentinelCount == 0 else { throw Error.changedDuringRead }

        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw Error.readFailed }
        try validate(
            after,
            maximumBytes: maximumBytes,
            requireCurrentUserOwner: requireCurrentUserOwner,
            requireSingleLink: requireSingleLink
        )
        guard before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              after.st_size == data.count else {
            throw Error.changedDuringRead
        }
        return data
    }

    private static func validate(
        _ info: stat,
        maximumBytes: Int,
        requireCurrentUserOwner: Bool,
        requireSingleLink: Bool
    ) throws {
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw Error.notRegular }
        guard !requireCurrentUserOwner || info.st_uid == geteuid() else {
            throw Error.unexpectedOwner
        }
        guard !requireSingleLink || info.st_nlink == 1 else {
            throw Error.unexpectedLinkCount
        }
        guard info.st_size >= 0, info.st_size <= maximumBytes else { throw Error.tooLarge }
    }
}
