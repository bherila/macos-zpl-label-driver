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

private struct AcceptedJobStateStoreBodyFailure: Swift.Error {
    let underlying: Swift.Error
}

/// Mutable lifecycle state inside an immutable accepted-job bundle. All
/// replacements are serialized across processes and compare the complete
/// expected record before publication.
public struct AcceptedJobStateStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotOpenStore
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

    private let acceptedJobs: AcceptedJobStore
    private let injectFault: @Sendable (FaultPoint) throws -> Void

    public init(acceptedJobStore: AcceptedJobStore) {
        acceptedJobs = acceptedJobStore
        injectFault = { _ in }
    }

    init(
        acceptedJobStore: AcceptedJobStore,
        injectFault: @escaping @Sendable (FaultPoint) throws -> Void
    ) {
        acceptedJobs = acceptedJobStore
        self.injectFault = injectFault
    }

    public func load(
        acceptanceID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        try withLockedBundle(
            acceptanceID: acceptanceID, queueStore: queueStore,
            workflowStore: workflowStore, printerStore: printerStore
        ) { directory, bundle in
            try read(directory, bundle: bundle)
        }
    }

    /// Publishes complete typed prepared bytes before making their state
    /// visible. An exact orphan left while state is still accepted is safe to
    /// reuse; different bytes conflict and can never replace it.
    public func publishPrepared(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        payload: PreparedJobPayload,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        return try withLockedBundle(
            acceptanceID: acceptanceID, queueStore: queueStore,
            workflowStore: workflowStore, printerStore: printerStore
        ) { directory, bundle in
            let profile: PrinterProfile
            do { profile = try printerStore.load(reference: bundle.ticket.printerProfile) }
            catch { throw Error.acceptedJobMismatch }
            guard expected.acceptanceID == acceptanceID,
                  expected.acceptedTicketSHA256 == bundle.acceptedTicketSHA256 else {
                throw Error.acceptedJobMismatch
            }
            guard payload.outputLabels == bundle.ticket.outputLabels,
                  payload.monochromeConversion == bundle.ticket.monochromeConversion,
                  payload.profileSnapshot == JobProfileSnapshot(profile: profile),
                  payload.resolvedControls == bundle.ticket.controls else {
                throw Error.preparedPayloadMismatch
            }
            let current = try read(directory, bundle: bundle)
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
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> StoredPreparedJob {
        try withLockedBundle(
            acceptanceID: acceptanceID, queueStore: queueStore,
            workflowStore: workflowStore, printerStore: printerStore
        ) { directory, bundle in
            let profile: PrinterProfile
            do { profile = try printerStore.load(reference: bundle.ticket.printerProfile) }
            catch { throw Error.acceptedJobMismatch }
            let state = try read(directory, bundle: bundle)
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
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        guard next != .cancelledBeforeTransmission else { throw Error.cancellationUnauthorized }
        if case .prepared = next { throw Error.preparedPayloadRequired }
        return try update(
            acceptanceID: acceptanceID, expected: expected, next: next,
            queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore
        )
    }

    public func cancel(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        cancellationToken: Data,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        guard !cancellationToken.isEmpty, cancellationToken.count <= 256 else {
            throw Error.cancellationUnauthorized
        }
        return try withLockedBundle(
            acceptanceID: acceptanceID, queueStore: queueStore,
            workflowStore: workflowStore, printerStore: printerStore
        ) { directory, bundle in
            let supplied = Array(SHA256.hash(data: cancellationToken))
            guard let expectedDigest = Self.hexBytes(bundle.ticket.cancellationSHA256),
                  Self.constantTimeEqual(supplied, expectedDigest) else {
                throw Error.cancellationUnauthorized
            }
            return try updateLocked(
                acceptanceID: acceptanceID, expected: expected,
                next: .cancelledBeforeTransmission,
                bundle: bundle, directory: directory
            )
        }
    }

    private func update(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        next: AcceptedJobPhase,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore
    ) throws -> AcceptedJobStateRecord {
        try withLockedBundle(
            acceptanceID: acceptanceID, queueStore: queueStore,
            workflowStore: workflowStore, printerStore: printerStore
        ) { directory, bundle in
            try updateLocked(
                acceptanceID: acceptanceID, expected: expected,
                next: next, bundle: bundle, directory: directory
            )
        }
    }

    private func updateLocked(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        next: AcceptedJobPhase,
        bundle: AcceptedJobBundle,
        directory: Int32
    ) throws -> AcceptedJobStateRecord {
        guard bundle.ticket.acceptanceID == acceptanceID,
              expected.acceptanceID == acceptanceID,
              expected.acceptedTicketSHA256 == bundle.acceptedTicketSHA256 else {
            throw Error.acceptedJobMismatch
        }
        let current = try read(directory, bundle: bundle)
        guard current == expected else { throw Error.stateConflict }
        let nextRecord = try advance(current, to: next)
        try replace(try canonical(nextRecord, readFailure: false), directory: directory)
        return nextRecord
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

    private func withLockedBundle<T>(
        acceptanceID: String,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore,
        body: (Int32, AcceptedJobBundle) throws -> T
    ) throws -> T {
        do {
            return try acceptedJobs.withLockedBundle(acceptanceID: acceptanceID) { directory in
                do {
                    let bundle: AcceptedJobBundle
                    do {
                        bundle = try acceptedJobs.loadBundle(
                            from: directory, acceptanceID: acceptanceID,
                            queueStore: queueStore, workflowStore: workflowStore,
                            printerStore: printerStore
                        )
                    } catch {
                        throw Error.acceptedJobMismatch
                    }
                    return try body(directory, bundle)
                } catch {
                    throw AcceptedJobStateStoreBodyFailure(underlying: error)
                }
            }
        } catch let failure as AcceptedJobStateStoreBodyFailure {
            throw failure.underlying
        } catch {
            throw Error.cannotOpenStore
        }
    }

    private func read(
        _ directory: Int32, bundle: AcceptedJobBundle
    ) throws -> AcceptedJobStateRecord {
        let descriptor = NonblockingRegularFileDescriptor.open(at: directory, name: "state.json")
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
        let decoded: (state: AcceptedJobStateRecord, needsMigration: Bool)
        do {
            let state = try AcceptedJobStateJSON.decode(bytes)
            guard try AcceptedJobStateJSON.encode(state) == bytes else {
                throw Error.cannotRead
            }
            decoded = (state, false)
        } catch {
            do {
                decoded = (try AcceptedJobStateJSON.migrateLegacyV1(
                    bytes, acceptedTicketSHA256: bundle.acceptedTicketSHA256
                ), true)
            } catch { throw Error.cannotRead }
        }
        let state = decoded.state
        guard state.acceptanceID == bundle.ticket.acceptanceID,
              state.acceptedTicketSHA256 == bundle.acceptedTicketSHA256 else {
            throw Error.acceptedJobMismatch
        }
        try validatePreparedArtifact(state: state, directory: directory)
        if decoded.needsMigration {
            try replace(try canonical(state, readFailure: false), directory: directory)
        }
        return state
    }

    private func readPrepared(_ directory: Int32) throws -> Data {
        let descriptor = NonblockingRegularFileDescriptor.open(
            at: directory, name: "prepared.zpl"
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
