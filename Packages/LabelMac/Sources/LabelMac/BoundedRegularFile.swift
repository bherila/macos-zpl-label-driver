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
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Error.cannotOpen }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw Error.readFailed }
        try validate(
            before,
            maximumBytes: maximumBytes,
            requireCurrentUserOwner: requireCurrentUserOwner,
            requireSingleLink: requireSingleLink
        )

        var data = Data()
        data.reserveCapacity(min(Int(before.st_size), maximumBytes))
        do {
            while data.count <= maximumBytes {
                let remainingThroughSentinel = maximumBytes - data.count + 1
                guard let chunk = try handle.read(upToCount: min(64 * 1024, remainingThroughSentinel)),
                      !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch {
            throw Error.readFailed
        }
        guard data.count <= maximumBytes else { throw Error.tooLarge }

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
