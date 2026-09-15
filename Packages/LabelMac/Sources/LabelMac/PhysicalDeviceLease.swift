import CryptoKit
import Darwin
import Foundation

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
/// their scheduler boundary.
public final class PhysicalDeviceLease: @unchecked Sendable {
    let lockFileURL: URL
    private let stateLock = NSLock()
    private var descriptor: Int32

    public init(acquiring identity: PhysicalDeviceIdentity, inExistingDirectory directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PhysicalDeviceLeaseError.invalidLockDirectory
        }

        lockFileURL = directory.appendingPathComponent(identity.filename, isDirectory: false)
        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw PhysicalDeviceLeaseError.systemFailure }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_nlink == 1
        else {
            Darwin.close(descriptor)
            throw PhysicalDeviceLeaseError.unsafeLockFile
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            Darwin.close(descriptor)
            if lockError == EWOULDBLOCK || lockError == EAGAIN { throw PhysicalDeviceLeaseError.alreadyHeld }
            throw PhysicalDeviceLeaseError.systemFailure
        }
        self.descriptor = descriptor
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
