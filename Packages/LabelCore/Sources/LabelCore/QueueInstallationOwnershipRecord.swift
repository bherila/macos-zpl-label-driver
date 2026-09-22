import Foundation

/// Typed vocabulary for a *planned* queue installation and the durable record of
/// what such a transaction created or was about to create.
///
/// Nothing in this file performs an installation. It builds no command line,
/// spawns no process, touches no filesystem, contacts no scheduler and reads no
/// device. It is the portable shape that ADR 0005 leaves common to every option
/// that ADR still holds open, and ADR 0005 remains *proposed*: this file selects
/// no mechanism, no adapter and no authorization flow.
public enum QueueInstallationError: Error, Equatable, Sendable {
    case invalidPath
    case invalidMode
    case invalidOwnership
    case invalidDigest
    case invalidQueueName
    case invalidTransactionID
    case invalidIncarnation
    case invalidObservation
    case artifactKindMismatch
    case artifactOutsideProtectedRoot
    case duplicateArtifactPath
    case tooManyArtifacts
    case refused(QueueInstallationRefusal)
    case invalidPhase
    case transactionMismatch
    /// Preconditions were captured for a different intent than the plan they
    /// were offered to.
    case preconditionsIntentMismatch
    case stagedArtifactInvalid(QueueInstallationArtifactKind, ArtifactValidationFailure)
    /// A queue was created but its configuration did not hand back the
    /// incarnation token this transaction wrote, so it cannot be claimed as
    /// this transaction's. It stays pending in the record for recovery.
    case queueIncarnationUnconfirmed
    case effectFailed
    case recoveryOrderingViolation
    /// A supplied recovery plan does not cover every artifact the record still
    /// names. Recovering part of a transaction is not recovering it.
    case incompleteRecoveryPlan
    case notOwnedByTransaction
    case invalidRecord
    /// A record's phase contradicts what it says it created.
    case inconsistentRecordPhase
    /// A record that should carry a journal artifact does not, so recovery has
    /// nowhere to read or write its own evidence.
    case recordHasNoJournal
}

// MARK: - Bounded primitive values

/// An absolute POSIX path with no relative component and no character that could
/// make the durable record's line encoding ambiguous. A selector or display name
/// is never converted into one of these; a path is supplied explicitly.
public struct AbsolutePath: Equatable, Hashable, Sendable {
    public static let maximumByteCount = 1024

    public let value: String

    public init(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard (2...Self.maximumByteCount).contains(bytes.count) else { throw QueueInstallationError.invalidPath }
        guard bytes.first == 0x2f, bytes.last != 0x2f else { throw QueueInstallationError.invalidPath }
        // Printable ASCII only, minus the three characters the record encoding
        // reserves as separators. This keeps decode(encode(x)) == x injective
        // rather than relying on a quoting scheme.
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f && $0 != 0x3d && $0 != 0x3a && $0 != 0x7c }) else {
            throw QueueInstallationError.invalidPath
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard components.count >= 1,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw QueueInstallationError.invalidPath
        }
        self.value = value
    }

    public var componentCount: Int {
        value.split(separator: "/", omittingEmptySubsequences: false).dropFirst().count
    }

    /// The containing directory, or nil when this path has a single component
    /// and its parent would be the filesystem root.
    public var parent: AbsolutePath? {
        guard componentCount >= 2, let index = value.lastIndex(of: "/") else { return nil }
        return try? AbsolutePath(String(value[value.startIndex..<index]))
    }

    /// True when `self` is exactly one component below `directory`. Deeper
    /// nesting is deliberately not accepted: recovery must be finite and must
    /// not become a recursive delete.
    public func isImmediateChild(of directory: AbsolutePath) -> Bool {
        parent == directory
    }
}

/// POSIX ownership as a pair of bounded identifiers.
public struct POSIXOwnership: Equatable, Hashable, Sendable {
    public static let rootWheel = POSIXOwnership(unchecked: 0, gid: 0)

    public let uid: Int
    public let gid: Int

    private init(unchecked uid: Int, gid: Int) {
        self.uid = uid
        self.gid = gid
    }

    public init(uid: Int, gid: Int) throws {
        guard (0...Int(Int32.max)).contains(uid), (0...Int(Int32.max)).contains(gid) else {
            throw QueueInstallationError.invalidOwnership
        }
        self.uid = uid
        self.gid = gid
    }
}

/// A permission word restricted to what a protected staging root may ever carry:
/// no set-user-ID, no set-group-ID, no sticky bit, and never group- or
/// world-writable. An invalid mode is rejected, never clamped.
public struct POSIXMode: Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) throws {
        guard (0...0o7777).contains(rawValue) else { throw QueueInstallationError.invalidMode }
        guard rawValue & 0o7000 == 0 else { throw QueueInstallationError.invalidMode }
        guard rawValue & 0o022 == 0 else { throw QueueInstallationError.invalidMode }
        self.rawValue = rawValue
    }

    /// Exactly four octal digits, so the record encoding is fixed width.
    public var octalText: String {
        var digits = ""
        var shift = 9
        while shift >= 0 {
            digits.append(Character(UnicodeScalar(UInt8(0x30 + ((rawValue >> shift) & 0o7)))))
            shift -= 3
        }
        return digits
    }

    public static func decodeOctal(_ text: String) throws -> POSIXMode {
        let bytes = Array(text.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ (0x30...0x37).contains($0) }) else {
            throw QueueInstallationError.invalidMode
        }
        var value = 0
        for byte in bytes {
            // Bounded by construction: four octal digits cannot exceed 0o7777.
            value = (value << 3) | Int(byte - 0x30)
        }
        return try POSIXMode(value)
    }
}

/// A scheduler queue *name*. It is an identifier, never a path, a URI or a
/// command fragment, and this type refuses anything that could be read as one.
public struct PlannedSchedulerQueue: Equatable, Hashable, Sendable {
    public let name: String

    public init(name: String) throws {
        let bytes = Array(name.utf8)
        guard (1...127).contains(bytes.count) else { throw QueueInstallationError.invalidQueueName }
        guard let first = bytes.first, first != 0x2d, first != 0x5f else {
            throw QueueInstallationError.invalidQueueName
        }
        guard bytes.allSatisfy({
            (0x41...0x5a).contains($0) || (0x61...0x7a).contains($0)
                || (0x30...0x39).contains($0) || $0 == 0x2d || $0 == 0x5f
        }) else { throw QueueInstallationError.invalidQueueName }
        self.name = name
    }
}

/// An *unrepeatable* token this transaction writes into the queue's own
/// configuration and reads back, so that one particular queue object can be
/// told apart from any later queue of the same name.
///
/// It must be freshly generated per transaction and must **not** be derived from
/// the queue's configuration. A digest of the configuration would be
/// reproducible: another administrator creating the same name with the same
/// device target and description would produce the same value, and a removal
/// gated on it would delete their queue. This model generates no randomness, so
/// the token is supplied by the caller and its unrepeatability is the caller's
/// obligation.
public struct SchedulerQueueIncarnation: Equatable, Hashable, Sendable {
    public let token: String

    public init(token: String) throws {
        guard isLowercaseSHA256(token) else { throw QueueInstallationError.invalidIncarnation }
        self.token = token
    }
}

/// What a create operation could prove about acquiring the queue *name*.
///
/// `lpadmin -p` is create-or-modify, not an exclusive namespace acquisition.
/// `docs/validation/M1-TRANSACTION-RECOVERY.md` states the consequence
/// directly: "even a successful response and exact discard URI readback cannot
/// prove that no competing queue was modified". A seam built on it must
/// therefore report `ambiguousCreateOrModify`, and this model refuses to call
/// such a transaction complete.
public enum SchedulerQueueAcquisition: String, Equatable, Sendable, CaseIterable {
    /// The seam proved that this operation created the name and did not modify
    /// an existing queue.
    case exclusiveCreation = "exclusive-creation"
    /// The operation reported success but cannot distinguish creation from
    /// modification of a queue that appeared first.
    case ambiguousCreateOrModify = "ambiguous-create-or-modify"
}

/// A caller-supplied identifier for one transaction: 32 lowercase hex digits.
/// This model generates no randomness and reads no clock.
public struct QueueInstallationTransactionID: Equatable, Hashable, Sendable {
    public let hex: String

    public init(hex: String) throws {
        let bytes = Array(hex.utf8)
        guard bytes.count == 32,
              bytes.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
            throw QueueInstallationError.invalidTransactionID
        }
        self.hex = hex
    }
}

func isLowercaseSHA256(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return bytes.count == 64 && bytes.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
}

/// Parses the one decimal spelling this encoding emits: digits only, no sign, no
/// leading zero unless the value is exactly `0`. `Int(_: String)` is deliberately
/// not used, because it also accepts `+0`, `-0` and `00`, which re-encode to `0`
/// and would give the same record several byte representations.
func canonicalDecimal(_ text: Substring) -> Int? {
    let bytes = Array(text.utf8)
    guard (1...10).contains(bytes.count), bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
    guard bytes.count == 1 || bytes[0] != 0x30 else { return nil }
    var value = 0
    for byte in bytes {
        // Bounded: at most ten digits, so the accumulator stays far below Int.max.
        value = value * 10 + Int(byte - 0x30)
    }
    return value
}

// MARK: - Planned artifacts

public enum QueueInstallationArtifactKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case protectedRoot = "protected-root"
    case ownershipRecord = "ownership-record"
    case filterExecutable = "filter-executable"
    case printerDescription = "printer-description"
}

/// One artifact the transaction *would* create, with its intended absolute path,
/// ownership and mode declared up front. A plan is a value; holding one performs
/// nothing.
///
/// A digest is declared for artifacts whose bytes are fixed before the
/// transaction starts. The protected root is a directory and has none, and the
/// ownership record is the transaction's own journal: its bytes change every
/// time the transaction takes ownership of something, so it is validated by
/// reading the record back and decoding it, not against a digest fixed in
/// advance.
public struct PlannedFileArtifact: Equatable, Hashable, Sendable {
    public let kind: QueueInstallationArtifactKind
    public let path: AbsolutePath
    public let ownership: POSIXOwnership
    public let mode: POSIXMode
    public let contentSHA256: String?

    public init(
        kind: QueueInstallationArtifactKind,
        path: AbsolutePath,
        ownership: POSIXOwnership = .rootWheel,
        mode: POSIXMode,
        contentSHA256: String?
    ) throws {
        guard ownership == .rootWheel else { throw QueueInstallationError.invalidOwnership }
        switch kind {
        case .protectedRoot:
            guard contentSHA256 == nil, mode.rawValue == 0o755 else {
                throw QueueInstallationError.artifactKindMismatch
            }
        case .ownershipRecord:
            guard contentSHA256 == nil, mode.rawValue == 0o644 else {
                throw QueueInstallationError.artifactKindMismatch
            }
        case .filterExecutable:
            guard mode.rawValue == 0o755 else { throw QueueInstallationError.artifactKindMismatch }
        case .printerDescription:
            guard mode.rawValue == 0o644 else { throw QueueInstallationError.artifactKindMismatch }
        }
        if kind == .filterExecutable || kind == .printerDescription {
            guard let digest = contentSHA256, isLowercaseSHA256(digest) else {
                throw QueueInstallationError.invalidDigest
            }
        }
        self.kind = kind
        self.path = path
        self.ownership = ownership
        self.mode = mode
        self.contentSHA256 = contentSHA256
    }

    public var expectedFileKind: ObservedFileKind {
        kind == .protectedRoot ? .directory : .regularFile
    }
}

/// Names one artifact inside a single transaction's ownership domain.
public enum QueueInstallationArtifactID: Equatable, Hashable, Sendable {
    case schedulerQueue
    case file(AbsolutePath)
}

// MARK: - Observation (tri-state, never collapsed)

public enum ObservedFileKind: String, Equatable, Hashable, Sendable {
    case directory
    case regularFile = "regular-file"
    case symbolicLink = "symbolic-link"
    case other
}

/// What a query reported about one path. Every field is optional because a
/// partially readable answer is *unknown for that field*, never a default.
public struct ObservedFileState: Equatable, Sendable {
    public let kind: ObservedFileKind
    public let uid: Int?
    public let gid: Int?
    public let modeBits: Int?
    public let contentSHA256: String?

    public init(
        kind: ObservedFileKind,
        uid: Int? = nil,
        gid: Int? = nil,
        modeBits: Int? = nil,
        contentSHA256: String? = nil
    ) throws {
        if let uid {
            guard (0...Int(Int32.max)).contains(uid) else { throw QueueInstallationError.invalidObservation }
        }
        if let gid {
            guard (0...Int(Int32.max)).contains(gid) else { throw QueueInstallationError.invalidObservation }
        }
        if let modeBits {
            guard (0...0o7777).contains(modeBits) else { throw QueueInstallationError.invalidObservation }
        }
        if let contentSHA256 {
            guard isLowercaseSHA256(contentSHA256) else { throw QueueInstallationError.invalidObservation }
        }
        self.kind = kind
        self.uid = uid
        self.gid = gid
        self.modeBits = modeBits
        self.contentSHA256 = contentSHA256
    }
}

/// Present, confirmed absent, or *the query failed*. A failed query is never
/// reinterpreted as absence, and there is no fourth, convenient reading.
public enum FileArtifactObservation: Equatable, Sendable {
    case present(ObservedFileState)
    case confirmedAbsent
    case queryFailed

    public var isConfirmedAbsent: Bool {
        if case .confirmedAbsent = self { return true }
        return false
    }
}

/// The same three answers for a queue, and for a present queue the incarnation
/// token the seam could read out of its configuration. `present(nil)` means a
/// queue of that name exists but carries no readable incarnation; that is
/// unknown, and unknown never authorizes a removal.
public enum SchedulerQueueObservation: Equatable, Sendable {
    case present(SchedulerQueueIncarnation?)
    case confirmedAbsent
    case queryFailed

    public var isConfirmedAbsent: Bool {
        if case .confirmedAbsent = self { return true }
        return false
    }

    public var isConfirmedPresent: Bool {
        if case .present = self { return true }
        return false
    }

    public var incarnation: SchedulerQueueIncarnation? {
        if case let .present(incarnation) = self { return incarnation }
        return nil
    }
}

/// The durable ownership record as it was read back, as text. A record the seam
/// could not read is not an empty record.
public enum OwnershipRecordObservation: Equatable, Sendable {
    case present(String)
    case confirmedAbsent
    case queryFailed
}

public enum ArtifactValidationFailure: Equatable, Sendable {
    case absent
    case observationFailed
    case symbolicLink
    case wrongFileKind
    case ownershipUnknown
    case ownershipMismatch
    case modeUnknown
    case modeMismatch
    case contentUnknown
    case contentMismatch
}

public extension PlannedFileArtifact {
    /// Returns nil when the observation matches this plan exactly, and otherwise
    /// the first reason it does not. An unreadable field fails as `unknown`; it
    /// never passes and never silently becomes a default.
    func validationFailure(against observation: FileArtifactObservation) -> ArtifactValidationFailure? {
        switch observation {
        case .queryFailed:
            return .observationFailed
        case .confirmedAbsent:
            return .absent
        case let .present(state):
            if state.kind == .symbolicLink { return .symbolicLink }
            guard state.kind == expectedFileKind else { return .wrongFileKind }
            guard let uid = state.uid, let gid = state.gid else { return .ownershipUnknown }
            guard uid == ownership.uid, gid == ownership.gid else { return .ownershipMismatch }
            guard let bits = state.modeBits else { return .modeUnknown }
            guard bits == mode.rawValue else { return .modeMismatch }
            if let expected = contentSHA256 {
                guard let observed = state.contentSHA256 else { return .contentUnknown }
                guard observed == expected else { return .contentMismatch }
            }
            return nil
        }
    }
}

// MARK: - Durable ownership record

public enum QueueInstallationRecordedPhase: String, Equatable, Sendable, CaseIterable {
    case inProgress = "in-progress"
    case completed
    case rolledBack = "rolled-back"
    case residual
}

/// The durable record naming every artifact the transaction created, plus the
/// one it is *about to* create, so recovery is finite and a human can recover
/// from evidence rather than from guesswork.
///
/// The pending entry exists because an effect and the note of it cannot happen
/// at the same instant. A step is written as pending *before* the effect runs
/// and moved to created afterwards, so an interruption at the worst moment
/// leaves an artifact whose existence is unknown but whose *name* is recorded.
/// Recovery probes a pending artifact and never assumes it was not created.
///
/// The encoding is a fixed, canonical line sequence, and decoding is strict: an
/// unknown key, a duplicate key, a reordered section, a non-canonical integer, a
/// phase that contradicts the artifact list, or any input whose re-encoding
/// differs by a single byte fails closed rather than being partly believed.
public struct QueueInstallationOwnershipRecord: Equatable, Sendable {
    public static let schemaVersion = 2
    public static let maximumFileArtifacts = 8
    public static let maximumCreatedArtifacts = 16
    public static let maximumEncodedByteCount = 16 * 1024

    public let transactionID: QueueInstallationTransactionID
    public let queue: PlannedSchedulerQueue
    /// The incarnation token confirmed for this transaction's own queue.
    /// Removal requires an exact match against it.
    public let queueIncarnation: SchedulerQueueIncarnation?
    /// What the create operation could prove about acquiring the name.
    public let queueAcquisition: SchedulerQueueAcquisition?
    public let phase: QueueInstallationRecordedPhase
    /// The step whose effect was about to run. Its existence is unknown.
    public let pendingArtifact: QueueInstallationArtifactID?
    /// Every planned file artifact, in the order the transaction would create them.
    public let files: [PlannedFileArtifact]
    /// The subset confirmed created, in creation order.
    public let createdArtifacts: [QueueInstallationArtifactID]

    private init(
        validated transactionID: QueueInstallationTransactionID,
        queue: PlannedSchedulerQueue,
        queueIncarnation: SchedulerQueueIncarnation?,
        queueAcquisition: SchedulerQueueAcquisition?,
        phase: QueueInstallationRecordedPhase,
        pendingArtifact: QueueInstallationArtifactID?,
        files: [PlannedFileArtifact],
        createdArtifacts: [QueueInstallationArtifactID]
    ) {
        self.transactionID = transactionID
        self.queue = queue
        self.queueIncarnation = queueIncarnation
        self.queueAcquisition = queueAcquisition
        self.phase = phase
        self.pendingArtifact = pendingArtifact
        self.files = files
        self.createdArtifacts = createdArtifacts
    }

    public init(
        transactionID: QueueInstallationTransactionID,
        queue: PlannedSchedulerQueue,
        queueIncarnation: SchedulerQueueIncarnation? = nil,
        queueAcquisition: SchedulerQueueAcquisition? = nil,
        phase: QueueInstallationRecordedPhase,
        pendingArtifact: QueueInstallationArtifactID? = nil,
        files: [PlannedFileArtifact],
        createdArtifacts: [QueueInstallationArtifactID]
    ) throws {
        guard (1...Self.maximumFileArtifacts).contains(files.count) else {
            throw QueueInstallationError.tooManyArtifacts
        }
        guard createdArtifacts.count <= Self.maximumCreatedArtifacts else {
            throw QueueInstallationError.tooManyArtifacts
        }
        var plannedPaths = Set<AbsolutePath>()
        for file in files {
            guard plannedPaths.insert(file.path).inserted else { throw QueueInstallationError.duplicateArtifactPath }
        }
        var seenCreated = Set<QueueInstallationArtifactID>()
        for created in createdArtifacts {
            guard seenCreated.insert(created).inserted else { throw QueueInstallationError.duplicateArtifactPath }
            if case let .file(path) = created {
                guard plannedPaths.contains(path) else { throw QueueInstallationError.notOwnedByTransaction }
            }
        }
        if let pendingArtifact {
            // A pending step is one this transaction planned and has not yet
            // confirmed. It cannot already be created.
            guard !seenCreated.contains(pendingArtifact) else { throw QueueInstallationError.duplicateArtifactPath }
            if case let .file(path) = pendingArtifact {
                guard plannedPaths.contains(path) else { throw QueueInstallationError.notOwnedByTransaction }
            }
        }
        let createdQueue = seenCreated.contains(.schedulerQueue)
        // An incarnation or an acquisition can only describe a queue this
        // transaction created, and they are recorded together.
        guard (queueIncarnation == nil) == (queueAcquisition == nil) else {
            throw QueueInstallationError.inconsistentRecordPhase
        }
        guard queueIncarnation == nil || createdQueue else {
            throw QueueInstallationError.inconsistentRecordPhase
        }
        switch phase {
        case .completed:
            // Completion means every planned artifact exists, in the order it
            // was planned, with nothing pending, the queue identified, and the
            // name provably acquired. Anything less is in progress or residual.
            let expected = files.map { QueueInstallationArtifactID.file($0.path) } + [.schedulerQueue]
            guard createdArtifacts == expected, pendingArtifact == nil,
                  queueIncarnation != nil, queueAcquisition == .exclusiveCreation else {
                throw QueueInstallationError.inconsistentRecordPhase
            }
        case .rolledBack:
            // Rolled back means nothing of this transaction remains, and nothing
            // is left in the unknown pending state either.
            guard createdArtifacts.isEmpty, pendingArtifact == nil else {
                throw QueueInstallationError.inconsistentRecordPhase
            }
        case .inProgress, .residual:
            break
        }
        self.transactionID = transactionID
        self.queue = queue
        self.queueIncarnation = queueIncarnation
        self.queueAcquisition = queueAcquisition
        self.phase = phase
        self.pendingArtifact = pendingArtifact
        self.files = files
        self.createdArtifacts = createdArtifacts
    }

    public func artifact(for id: QueueInstallationArtifactID) -> PlannedFileArtifact? {
        guard case let .file(path) = id else { return nil }
        return files.first { $0.path == path }
    }

    /// The journal this record lives in. Recovery needs it to read its own
    /// evidence back and to shorten it as it proceeds.
    public var journalArtifact: PlannedFileArtifact? {
        files.first { $0.kind == .ownershipRecord }
    }

    /// Created artifacts plus the pending one, in creation order. This is what
    /// recovery must cover: a pending step may or may not exist, and assuming it
    /// does not is exactly the mistake that leaves an orphan.
    public var ownedArtifactsInCreationOrder: [QueueInstallationArtifactID] {
        createdArtifacts + (pendingArtifact.map { [$0] } ?? [])
    }

    public func owns(_ id: QueueInstallationArtifactID) -> Bool {
        createdArtifacts.contains(id) || pendingArtifact == id
    }

    /// A phase must stay consistent with what the record says it created, so
    /// this revalidates rather than assuming.
    public func replacingPhase(_ phase: QueueInstallationRecordedPhase) throws -> Self {
        try Self(
            transactionID: transactionID, queue: queue,
            queueIncarnation: queueIncarnation, queueAcquisition: queueAcquisition,
            phase: phase, pendingArtifact: pendingArtifact,
            files: files, createdArtifacts: createdArtifacts
        )
    }

    /// `residual` places no requirement on the artifact list — it exists exactly
    /// to describe a state nobody can vouch for — so this cannot fail and does
    /// not need a throwing caller.
    public func markingResidual() -> Self {
        Self(
            validated: transactionID, queue: queue,
            queueIncarnation: queueIncarnation, queueAcquisition: queueAcquisition,
            phase: .residual, pendingArtifact: pendingArtifact,
            files: files, createdArtifacts: createdArtifacts
        )
    }

    /// Names the step whose effect is about to run. Written durably *before* the
    /// effect, so an interruption cannot hide it.
    public func markingPending(_ id: QueueInstallationArtifactID) throws -> Self {
        try Self(
            transactionID: transactionID, queue: queue,
            queueIncarnation: queueIncarnation, queueAcquisition: queueAcquisition,
            phase: phase, pendingArtifact: id,
            files: files, createdArtifacts: createdArtifacts
        )
    }

    /// Promotes the pending step to created, once its effect has been confirmed.
    public func confirmingPending(
        queueIncarnation incarnation: SchedulerQueueIncarnation? = nil,
        queueAcquisition acquisition: SchedulerQueueAcquisition? = nil
    ) throws -> Self {
        guard let pendingArtifact else { throw QueueInstallationError.invalidPhase }
        return try Self(
            transactionID: transactionID, queue: queue,
            queueIncarnation: incarnation ?? queueIncarnation,
            queueAcquisition: acquisition ?? queueAcquisition,
            phase: phase, pendingArtifact: nil,
            files: files, createdArtifacts: createdArtifacts + [pendingArtifact]
        )
    }

    /// Drops an artifact that is confirmed gone, and with the queue its
    /// incarnation and acquisition. This is what makes a second recovery pass
    /// idempotent rather than a second deletion.
    ///
    /// Shortening the list cannot break the `in-progress`, `residual` or
    /// `rolled-back` rules, but it can contradict `completed`, which asserts
    /// that everything planned exists. A record that loses an artifact is
    /// therefore no longer complete, and says so.
    public func removingCreatedArtifact(_ id: QueueInstallationArtifactID) -> Self {
        let droppedQueue = id == .schedulerQueue
        return Self(
            validated: transactionID, queue: queue,
            queueIncarnation: droppedQueue ? nil : queueIncarnation,
            queueAcquisition: droppedQueue ? nil : queueAcquisition,
            phase: phase == .completed ? .inProgress : phase,
            pendingArtifact: pendingArtifact == id ? nil : pendingArtifact,
            files: files, createdArtifacts: createdArtifacts.filter { $0 != id }
        )
    }

    public var canonicalText: String {
        var lines: [String] = []
        lines.append("schemaVersion=\(Self.schemaVersion)")
        lines.append("transactionID=\(transactionID.hex)")
        lines.append("queue=\(queue.name)")
        lines.append("queueIncarnation=\(queueIncarnation?.token ?? "-")")
        lines.append("queueAcquisition=\(queueAcquisition?.rawValue ?? "-")")
        lines.append("phase=\(phase.rawValue)")
        lines.append("pending=\(pendingArtifact.map(Self.encode(artifact:)) ?? "-")")
        for file in files {
            let fields = [
                file.kind.rawValue,
                file.path.value,
                String(file.ownership.uid),
                String(file.ownership.gid),
                file.mode.octalText,
                file.contentSHA256 ?? "-",
            ]
            lines.append("file=" + fields.joined(separator: "|"))
        }
        for created in createdArtifacts {
            lines.append("created=" + Self.encode(artifact: created))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func encode(artifact: QueueInstallationArtifactID) -> String {
        switch artifact {
        case .schedulerQueue: "queue"
        case let .file(path): path.value
        }
    }

    private static func decode(artifact value: String) throws -> QueueInstallationArtifactID {
        value == "queue" ? .schedulerQueue : .file(try AbsolutePath(value))
    }

    public static func decode(_ text: String) throws -> Self {
        guard text.utf8.count <= maximumEncodedByteCount, text.hasSuffix("\n") else {
            throw QueueInstallationError.invalidRecord
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else { throw QueueInstallationError.invalidRecord }
        lines.removeLast()
        guard lines.count >= 8 else { throw QueueInstallationError.invalidRecord }

        func field(_ line: Substring, _ key: String) throws -> String {
            let prefix = key + "="
            guard line.hasPrefix(prefix) else { throw QueueInstallationError.invalidRecord }
            return String(line.dropFirst(prefix.count))
        }

        guard try field(lines[0], "schemaVersion") == String(schemaVersion) else {
            throw QueueInstallationError.invalidRecord
        }
        let transactionID = try QueueInstallationTransactionID(hex: field(lines[1], "transactionID"))
        let queue = try PlannedSchedulerQueue(name: field(lines[2], "queue"))
        let incarnationField = try field(lines[3], "queueIncarnation")
        let incarnation = incarnationField == "-"
            ? nil : try SchedulerQueueIncarnation(token: incarnationField)
        let acquisitionField = try field(lines[4], "queueAcquisition")
        var acquisition: SchedulerQueueAcquisition?
        if acquisitionField != "-" {
            guard let parsed = SchedulerQueueAcquisition(rawValue: acquisitionField) else {
                throw QueueInstallationError.invalidRecord
            }
            acquisition = parsed
        }
        guard let phase = QueueInstallationRecordedPhase(rawValue: try field(lines[5], "phase")) else {
            throw QueueInstallationError.invalidRecord
        }
        let pendingField = try field(lines[6], "pending")
        let pending = pendingField == "-" ? nil : try decode(artifact: pendingField)

        var index = 7
        var files: [PlannedFileArtifact] = []
        while index < lines.count, lines[index].hasPrefix("file=") {
            files.append(try decodeFile(field(lines[index], "file")))
            index += 1
        }
        var created: [QueueInstallationArtifactID] = []
        while index < lines.count, lines[index].hasPrefix("created=") {
            created.append(try decode(artifact: field(lines[index], "created")))
            index += 1
        }
        // Any remaining line is an unknown key, a reordered section or trailing
        // junk. A record that is not exactly canonical is not believed at all.
        guard index == lines.count else { throw QueueInstallationError.invalidRecord }
        let record = try Self(
            transactionID: transactionID, queue: queue,
            queueIncarnation: incarnation, queueAcquisition: acquisition,
            phase: phase, pendingArtifact: pending,
            files: files, createdArtifacts: created
        )
        // One canonical spelling per record. Anything that decodes but would
        // re-encode differently is a second byte representation of the same
        // claim, which would defeat comparing records by their bytes.
        guard record.canonicalText == text else { throw QueueInstallationError.invalidRecord }
        return record
    }

    private static func decodeFile(_ value: String) throws -> PlannedFileArtifact {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 6 else { throw QueueInstallationError.invalidRecord }
        guard let kind = QueueInstallationArtifactKind(rawValue: String(parts[0])) else {
            throw QueueInstallationError.invalidRecord
        }
        let path = try AbsolutePath(String(parts[1]))
        guard let uid = canonicalDecimal(parts[2]), let gid = canonicalDecimal(parts[3]) else {
            throw QueueInstallationError.invalidRecord
        }
        let ownership = try POSIXOwnership(uid: uid, gid: gid)
        let mode = try POSIXMode.decodeOctal(String(parts[4]))
        let digest = parts[5] == "-" ? nil : String(parts[5])
        return try PlannedFileArtifact(
            kind: kind, path: path, ownership: ownership, mode: mode, contentSHA256: digest
        )
    }
}

// MARK: - Recovery ordering

/// Recovery is queue-first by construction. A partial failure must never leave a
/// live queue pointing at a removed filter, so the queue step, when present, is
/// the first step; the protected root, when present, is the last. Both rules are
/// enforced by the initializer, so a wrongly ordered recovery plan is not a
/// value this type can hold.
///
/// Ordering is all this type can enforce. *Completeness* is a question about a
/// particular record, so a recovery additionally requires that a supplied plan
/// is exactly the one its own record derives — an empty or partial plan recovers
/// nothing and must never be mistaken for a rollback.
public struct QueueInstallationRecoveryPlan: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case removeQueue(PlannedSchedulerQueue)
        case removeFile(PlannedFileArtifact)

        public var artifactID: QueueInstallationArtifactID {
            switch self {
            case .removeQueue: .schedulerQueue
            case let .removeFile(artifact): .file(artifact.path)
            }
        }
    }

    public let steps: [Step]

    public init(steps: [Step]) throws {
        guard steps.count <= QueueInstallationOwnershipRecord.maximumCreatedArtifacts else {
            throw QueueInstallationError.tooManyArtifacts
        }
        var seen = Set<QueueInstallationArtifactID>()
        for step in steps {
            guard seen.insert(step.artifactID).inserted else { throw QueueInstallationError.duplicateArtifactPath }
        }
        if let queueIndex = steps.firstIndex(where: {
            if case .removeQueue = $0 { return true }
            return false
        }) {
            guard queueIndex == 0 else { throw QueueInstallationError.recoveryOrderingViolation }
        }
        if let rootIndex = steps.firstIndex(where: {
            if case let .removeFile(artifact) = $0 { return artifact.kind == .protectedRoot }
            return false
        }) {
            guard rootIndex == steps.count - 1 else { throw QueueInstallationError.recoveryOrderingViolation }
        }
        self.steps = steps
    }

    /// Reverses the record's creation order — created artifacts *and* the
    /// pending one — which puts the queue first and the protected root last,
    /// then re-checks that ordering through `init(steps:)`.
    public init(record: QueueInstallationOwnershipRecord) throws {
        var steps: [Step] = []
        for id in record.ownedArtifactsInCreationOrder.reversed() {
            switch id {
            case .schedulerQueue:
                steps.append(.removeQueue(record.queue))
            case .file:
                guard let artifact = record.artifact(for: id) else {
                    throw QueueInstallationError.notOwnedByTransaction
                }
                steps.append(.removeFile(artifact))
            }
        }
        try self.init(steps: steps)
    }
}
