import CryptoKit
import Darwin
import Foundation
import LabelCore

/// A stable physical-device identifier used only to derive an opaque lock-file
/// name. It is intentionally not a transport URI and must never be emitted in
/// normal diagnostics.
public struct PhysicalDeviceIdentity: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable { case invalidIdentifier }

    private let lockName: String

    public init(stableIdentifier: String) throws {
        guard !stableIdentifier.isEmpty, stableIdentifier.utf8.count <= 512,
              stableIdentifier.unicodeScalars.allSatisfy({
                  !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
              })
        else { throw ValidationError.invalidIdentifier }
        lockName = SHA256.hash(data: Data(stableIdentifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Uses the already-opaque immutable coordination domain carried by a
    /// resolved job ticket. Delivery must use this initializer rather than a
    /// separately supplied transport alias.
    public init(coordinationID: PhysicalDeviceCoordinationID) {
        lockName = coordinationID.sha256
    }

    fileprivate var filename: String { "device-\(lockName).lock" }
}

public enum PhysicalDeviceLeaseError: Error, Equatable, Sendable {
    case invalidLockDirectory
    case unsafeLockFile
    case alreadyHeld
    case systemFailure
}

/// A non-blocking advisory lease held by an open file descriptor. The kernel
/// drops an `flock` lock when its owning process exits or closes the descriptor,
/// so no PID file can become a permanent stale owner. Every queue/backend and
/// maintenance action must use the same identity and lock root once M1 proves
/// their scheduler boundary. The root must be a private 0700 directory owned
/// by the effective user; named locks must remain empty private regular files.
/// Acquisition detects namespace replacement, but a trusted owner must preserve
/// the root/lock names throughout delivery. This is not a defense against that
/// owner deliberately unlinking a held lock or privileged namespace mutation.
public final class PhysicalDeviceLease: @unchecked Sendable {
    let lockFileURL: URL
    private let stateLock = NSLock()
    private var descriptor: Int32

    public convenience init(acquiring identity: PhysicalDeviceIdentity, inExistingDirectory directory: URL) throws {
        try self.init(acquiring: identity, inExistingDirectory: directory, checkpoint: { _ in })
    }

    enum AcquisitionCheckpoint { case opened, locked }

    /// Synchronous fault seam; never stored or invoked after acquisition.
    init(acquiring identity: PhysicalDeviceIdentity, inExistingDirectory directory: URL,
         checkpoint: (AcquisitionCheckpoint) throws -> Void) throws {
        guard directory.isFileURL else { throw PhysicalDeviceLeaseError.invalidLockDirectory }
        let root = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw PhysicalDeviceLeaseError.invalidLockDirectory }
        defer { Darwin.close(root) }
        try Self.validateRoot(root, at: directory)
        lockFileURL = directory.appendingPathComponent(identity.filename, isDirectory: false)
        let descriptor = openat(root, identity.filename,
            O_CREAT | O_RDWR | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw PhysicalDeviceLeaseError.systemFailure }
        var acquired = false
        defer { if !acquired { Darwin.close(descriptor) } }
        try Self.validateLock(descriptor, root: root, name: identity.filename)
        try checkpoint(.opened)
        try Self.validateRoot(root, at: directory)
        try Self.validateLock(descriptor, root: root, name: identity.filename)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            if lockError == EWOULDBLOCK || lockError == EAGAIN { throw PhysicalDeviceLeaseError.alreadyHeld }
            throw PhysicalDeviceLeaseError.systemFailure
        }
        try checkpoint(.locked)
        // Closing on any validation failure also releases the kernel lock.
        try Self.validateRoot(root, at: directory)
        try Self.validateLock(descriptor, root: root, name: identity.filename)
        self.descriptor = descriptor
        acquired = true
    }

    private static func validateRoot(_ descriptor: Int32, at directory: URL) throws {
        var opened = stat(), named = stat()
        guard fstat(descriptor, &opened) == 0, lstat(directory.path, &named) == 0,
              (opened.st_mode & S_IFMT) == S_IFDIR, (named.st_mode & S_IFMT) == S_IFDIR,
              opened.st_uid == geteuid(), (opened.st_mode & 0o7777) == 0o700,
              named.st_uid == opened.st_uid, named.st_mode == opened.st_mode,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino else {
            throw PhysicalDeviceLeaseError.invalidLockDirectory
        }
    }

    private static func validateLock(_ descriptor: Int32, root: Int32, name: String) throws {
        var opened = stat(), named = stat()
        guard fstat(descriptor, &opened) == 0,
              fstatat(root, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              (opened.st_mode & S_IFMT) == S_IFREG, (named.st_mode & S_IFMT) == S_IFREG,
              opened.st_uid == geteuid(), opened.st_nlink == 1, opened.st_size == 0,
              (opened.st_mode & 0o7777) == 0o600,
              named.st_uid == opened.st_uid, named.st_mode == opened.st_mode,
              named.st_nlink == 1, named.st_size == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino else {
            throw PhysicalDeviceLeaseError.unsafeLockFile
        }
    }

    public var isHeld: Bool { stateLock.withLock { descriptor >= 0 } }

    /// Explicitly releases the lease. It is also released by deinitialization
    /// and by process exit, but callers should bound its lifetime around actual
    /// readiness and delivery rather than relying on either fallback.
    public func release() {
        let descriptor: Int32? = stateLock.withLock {
            guard self.descriptor >= 0 else { return nil }
            defer { self.descriptor = -1 }
            return self.descriptor
        }
        if let descriptor {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
    }

    deinit { release() }
}
