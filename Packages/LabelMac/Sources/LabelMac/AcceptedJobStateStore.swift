import CryptoKit
import Darwin
import Foundation
import LabelCore

/// A prepared artifact returned only after its bytes, lifecycle binding,
/// resolved output order, controls, and immutable printer snapshot agree.
public struct StoredPreparedJob: Equatable, Sendable {
    public let bytes: Data
    public let outputLabels: [ResolvedOutputLabel]
    public let monochromeConversion: MonochromeConversion
    public let profileSnapshot: JobProfileSnapshot
    public let resolvedControls: ResolvedPrinterControls
    public let state: AcceptedJobStateRecord
}

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
        case preparedPayloadRequired
        case preparedPayloadMismatch
        case preparedPayloadConflict
        case preparedPayloadUnavailable
    }

    enum FaultPoint: Equatable, Sendable {
        case afterPreparedRename
        case afterPreparedDirectorySync
        case afterStateRename
    }

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
            try validatePreparedArtifact(state: state, directory: directory)
            return state
        }
    }

    /// Publishes complete typed prepared bytes before making their state
    /// visible. An exact orphan left while state is still accepted is safe to
    /// reuse; different bytes conflict and can never replace it.
    public func publishPrepared(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        payload: PreparedJobPayload,
        acceptedJobStore: AcceptedJobStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        let bundle = try loadBundle(
            acceptanceID, acceptedJobStore, queueStore, workflowStore, printerStore
        )
        let profile: PrinterProfile
        do { profile = try printerStore.load(reference: bundle.ticket.printerProfile) }
        catch { throw Error.acceptedJobMismatch }
        guard bundle.ticket.acceptanceID == acceptanceID,
              expected.acceptanceID == acceptanceID else {
            throw Error.acceptedJobMismatch
        }
        guard payload.outputLabels == bundle.ticket.outputLabels,
              payload.monochromeConversion == bundle.ticket.monochromeConversion,
              payload.profileSnapshot == JobProfileSnapshot(profile: profile),
              payload.resolvedControls == bundle.ticket.controls else {
            throw Error.preparedPayloadMismatch
        }
        return try withLockedBundle(acceptanceID: acceptanceID) { directory in
            let current = try read(directory)
            guard current == expected else { throw Error.stateConflict }
            guard current.phase == .accepted else { throw Error.invalidTransition }
            try persistPrepared(payload.bytes, directory: directory)
            let next = AcceptedJobPhase.prepared(
                payloadSHA256: Self.digest(payload.bytes),
                byteCount: payload.bytes.count
            )
            let nextRecord = try advance(current, to: next)
            try replace(try canonical(nextRecord, readFailure: false), directory: directory)
            return nextRecord
        }
    }

    /// Loads bytes only when a payload-bearing state and the stored artifact
    /// agree. Accepted jobs and terminal pre-transmission failures expose no
    /// deliverable payload even if an inert orphan file exists.
    public func loadPrepared(
        acceptanceID: String,
        acceptedJobStore: AcceptedJobStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> StoredPreparedJob {
        let bundle = try loadBundle(
            acceptanceID, acceptedJobStore, queueStore, workflowStore, printerStore
        )
        let profile: PrinterProfile
        do { profile = try printerStore.load(reference: bundle.ticket.printerProfile) }
        catch { throw Error.acceptedJobMismatch }
        return try withLockedBundle(acceptanceID: acceptanceID) { directory in
            let state = try read(directory)
            guard state.acceptanceID == bundle.ticket.acceptanceID else {
                throw Error.acceptedJobMismatch
            }
            guard let binding = Self.payloadBinding(state.phase) else {
                throw Error.preparedPayloadUnavailable
            }
            let bytes = try readPrepared(directory)
            guard bytes.count == binding.byteCount,
                  Self.digest(bytes) == binding.sha256 else {
                throw Error.preparedPayloadMismatch
            }
            return StoredPreparedJob(
                bytes: bytes,
                outputLabels: bundle.ticket.outputLabels,
                monochromeConversion: bundle.ticket.monochromeConversion,
                profileSnapshot: JobProfileSnapshot(profile: profile),
                resolvedControls: bundle.ticket.controls,
                state: state
            )
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
        if case .prepared = next { throw Error.preparedPayloadRequired }
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
            try validatePreparedArtifact(state: current, directory: directory)
            let nextRecord = try advance(current, to: next)
            try replace(try canonical(nextRecord, readFailure: false), directory: directory)
            return nextRecord
        }
    }

    private func advance(
        _ current: AcceptedJobStateRecord, to next: AcceptedJobPhase
    ) throws -> AcceptedJobStateRecord {
        let currentBytes = try canonical(current, readFailure: true)
        do {
            return try current.advanced(
                to: next, previousStateSHA256: Self.digest(currentBytes)
            )
        } catch { throw Error.invalidTransition }
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

    private func readPrepared(_ directory: Int32) throws -> Data {
        let descriptor = openat(
            directory, "prepared.zpl", O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw Error.preparedPayloadUnavailable }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1,
              (before.st_mode & 0o077) == 0, before.st_size > 0,
              before.st_size <= PreparedJobPayload.maximumBytes else {
            throw Error.preparedPayloadMismatch
        }
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
        return bytes
    }

    private func validatePreparedArtifact(
        state: AcceptedJobStateRecord, directory: Int32
    ) throws {
        guard let binding = Self.payloadBinding(state.phase) else { return }
        let bytes = try readPrepared(directory)
        guard bytes.count == binding.byteCount,
              Self.digest(bytes) == binding.sha256 else {
            throw Error.preparedPayloadMismatch
        }
    }

    private func persistPrepared(_ bytes: Data, directory: Int32) throws {
        guard !bytes.isEmpty, bytes.count <= PreparedJobPayload.maximumBytes else {
            throw Error.preparedPayloadMismatch
        }
        let temporary = ".prepared.tmp-\(UUID().uuidString)"
        let descriptor = openat(
            directory, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Error.cannotWrite }
        var cleanup = true
        defer {
            close(descriptor)
            if cleanup { _ = unlinkat(directory, temporary, 0) }
        }
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
        guard fsync(descriptor) == 0 else { throw Error.cannotWrite }
        if renameatx_np(
            directory, temporary, directory, "prepared.zpl", UInt32(RENAME_EXCL)
        ) != 0 {
            guard errno == EEXIST else { throw Error.cannotWrite }
            let existing = try readPrepared(directory)
            guard existing == bytes else { throw Error.preparedPayloadConflict }
            guard fsync(directory) == 0 else { throw Error.cannotWrite }
            try injectFault(.afterPreparedDirectorySync)
            return
        }
        cleanup = false
        try injectFault(.afterPreparedRename)
        guard fsync(directory) == 0 else { throw Error.cannotWrite }
        try injectFault(.afterPreparedDirectorySync)
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
        do { try injectFault(.afterStateRename) } catch { throw Error.commitUncertain }
        guard fsync(directory) == 0 else { throw Error.commitUncertain }
    }

    private static func payloadBinding(
        _ phase: AcceptedJobPhase
    ) -> (sha256: String, byteCount: Int)? {
        switch phase {
        case let .prepared(hash, count), let .waiting(hash, count),
             let .transmitted(hash, count), let .deviceConfirmed(hash, count):
            return (hash, count)
        case let .transmitting(hash, count, _), let .uncertain(hash, count, _):
            return (hash, count)
        case .accepted, .failedBeforeTransmission, .cancelledBeforeTransmission:
            return nil
        }
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
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
