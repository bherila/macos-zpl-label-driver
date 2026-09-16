import CryptoKit
import Darwin
import Foundation
import LabelCore

/// Mutable lifecycle state inside an immutable accepted-job bundle. All
/// replacements are serialized across processes and compare the complete
/// expected record before publication.
public struct AcceptedJobStateStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotOpenStore
        case unsafeStore
        case cannotRead
        case cannotWrite
        case commitUncertain
        case acceptedJobMismatch
        case stateConflict
        case invalidTransition
        case cancellationUnauthorized
    }

    enum FaultPoint: Equatable, Sendable { case afterRename }

    public let root: URL
    private let injectFault: @Sendable (FaultPoint) throws -> Void

    public init(root: URL) { self.root = root; injectFault = { _ in } }
    init(root: URL, injectFault: @escaping @Sendable (FaultPoint) throws -> Void) {
        self.root = root; self.injectFault = injectFault
    }

    public func load(
        acceptanceID: String,
        acceptedJobStore: AcceptedJobStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        let bundle = try loadBundle(
            acceptanceID, acceptedJobStore, queueStore, workflowStore, printerStore
        )
        return try withLockedBundle(acceptanceID: acceptanceID) { directory in
            let state = try read(directory)
            guard state.acceptanceID == bundle.ticket.acceptanceID else {
                throw Error.acceptedJobMismatch
            }
            return state
        }
    }

    public func compareAndSwap(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        next: AcceptedJobPhase,
        acceptedJobStore: AcceptedJobStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        guard next != .cancelledBeforeTransmission else { throw Error.cancellationUnauthorized }
        let bundle = try loadBundle(
            acceptanceID, acceptedJobStore, queueStore, workflowStore, printerStore
        )
        return try update(
            acceptanceID: acceptanceID, expected: expected, next: next,
            bundle: bundle
        )
    }

    public func cancel(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        cancellationToken: Data,
        acceptedJobStore: AcceptedJobStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        guard !cancellationToken.isEmpty, cancellationToken.count <= 256 else {
            throw Error.cancellationUnauthorized
        }
        let bundle = try loadBundle(
            acceptanceID, acceptedJobStore, queueStore, workflowStore, printerStore
        )
        let supplied = Array(SHA256.hash(data: cancellationToken))
        guard let expectedDigest = Self.hexBytes(bundle.ticket.cancellationSHA256),
              Self.constantTimeEqual(supplied, expectedDigest) else {
            throw Error.cancellationUnauthorized
        }
        return try update(
            acceptanceID: acceptanceID, expected: expected,
            next: .cancelledBeforeTransmission, bundle: bundle
        )
    }

    private func update(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        next: AcceptedJobPhase,
        bundle: AcceptedJobBundle
    ) throws -> AcceptedJobStateRecord {
        guard bundle.ticket.acceptanceID == acceptanceID,
              expected.acceptanceID == acceptanceID else {
            throw Error.acceptedJobMismatch
        }
        return try withLockedBundle(acceptanceID: acceptanceID) { directory in
            let current = try read(directory)
            guard current == expected else { throw Error.stateConflict }
            let currentBytes = try canonical(current, readFailure: true)
            let digest = SHA256.hash(data: currentBytes).map {
                String(format: "%02x", $0)
            }.joined()
            let nextRecord: AcceptedJobStateRecord
            do { nextRecord = try current.advanced(to: next, previousStateSHA256: digest) }
            catch { throw Error.invalidTransition }
            try replace(try canonical(nextRecord, readFailure: false), directory: directory)
            return nextRecord
        }
    }

    private func loadBundle(
        _ acceptanceID: String,
        _ jobs: AcceptedJobStore,
        _ queues: VirtualQueueStore,
        _ workflows: WorkflowProfileStore,
        _ printers: PrinterProfileStore
    ) throws -> AcceptedJobBundle {
        do {
            return try jobs.load(
                acceptanceID: acceptanceID, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            )
        } catch { throw Error.acceptedJobMismatch }
    }

    private func withLockedBundle<T>(
        acceptanceID: String, body: (Int32) throws -> T
    ) throws -> T {
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw Error.cannotOpenStore }
        defer { close(rootFD) }
        try Self.validateDirectory(rootFD)
        let jobs = openat(rootFD, "accepted-jobs", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard jobs >= 0 else { throw Error.cannotOpenStore }
        defer { close(jobs) }
        try Self.validateDirectory(jobs)
        let bundle = openat(
            jobs, AcceptedJobStore.directoryName(acceptanceID),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard bundle >= 0 else { throw Error.cannotOpenStore }
        defer { close(bundle) }
        try Self.validateDirectory(bundle)
        let lock = openat(bundle, ".state.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard lock >= 0 else { throw Error.cannotOpenStore }
        defer { close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1,
              (info.st_mode & 0o077) == 0 else { throw Error.unsafeStore }
        while flock(lock, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw Error.cannotOpenStore
        }
        defer { _ = flock(lock, LOCK_UN) }
        return try body(bundle)
    }

    private func read(_ directory: Int32) throws -> AcceptedJobStateRecord {
        let descriptor = openat(directory, "state.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Error.cannotRead }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1,
              (before.st_mode & 0o077) == 0, before.st_size > 0,
              before.st_size <= AcceptedJobStateJSON.maximumBytes else { throw Error.cannotRead }
        var bytes = Data(count: Int(before.st_size)); var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress?.advanced(by: offset), $0.count - offset)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw Error.cannotRead }
            offset += count
        }
        var extra: UInt8 = 0
        var extraCount: Int
        repeat { extraCount = Darwin.read(descriptor, &extra, 1) }
        while extraCount < 0 && errno == EINTR
        var after = stat()
        guard extraCount == 0, fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw Error.cannotRead
        }
        return try canonicalDecode(bytes)
    }

    private func canonicalDecode(_ bytes: Data) throws -> AcceptedJobStateRecord {
        do {
            let state = try AcceptedJobStateJSON.decode(bytes)
            guard try AcceptedJobStateJSON.encode(state) == bytes else { throw Error.cannotRead }
            return state
        } catch { throw Error.cannotRead }
    }

    private func canonical(
        _ state: AcceptedJobStateRecord, readFailure: Bool
    ) throws -> Data {
        do { return try AcceptedJobStateJSON.encode(state) }
        catch { throw readFailure ? Error.cannotRead : Error.cannotWrite }
    }

    private func replace(_ bytes: Data, directory: Int32) throws {
        let temporary = ".state.tmp-\(UUID().uuidString)"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw Error.cannotWrite }
        var cleanup = true
        defer { close(descriptor); if cleanup { _ = unlinkat(directory, temporary, 0) } }
        try bytes.withUnsafeBytes { raw in
            guard var cursor = raw.baseAddress else { throw Error.cannotWrite }
            var remaining = raw.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, cursor, remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw Error.cannotWrite }
                cursor = cursor.advanced(by: count); remaining -= count
            }
        }
        guard fsync(descriptor) == 0,
              renameat(directory, temporary, directory, "state.json") == 0 else {
            throw Error.cannotWrite
        }
        cleanup = false
        do { try injectFault(.afterRename) } catch { throw Error.commitUncertain }
        guard fsync(directory) == 0 else { throw Error.commitUncertain }
    }

    private static func validateDirectory(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(), (info.st_mode & 0o077) == 0 else {
            throw Error.unsafeStore
        }
    }

    private static func hexBytes(_ value: String) -> [UInt8]? {
        guard value.count == 64 else { return nil }
        var result: [UInt8] = []; result.reserveCapacity(32)
        var index = value.startIndex
        for _ in 0..<32 {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            result.append(byte); index = next
        }
        return result
    }

    private static func constantTimeEqual(_ left: [UInt8], _ right: [UInt8]) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}
