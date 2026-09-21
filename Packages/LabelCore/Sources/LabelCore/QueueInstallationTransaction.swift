import Foundation

/// The portable shape of a queue installation transaction.
///
/// **This is a model, not an installation path.** It performs no privileged
/// action, no filesystem mutation, no process spawn, no scheduler call and no
/// device or network I/O, and `LabelCore` ships no type conforming to
/// `QueueInstallationEffectSink`. It selects no mechanism: ADR 0005 proposes a
/// guided installer package over a persistent privileged helper, that decision
/// belongs to the maintainer, and ADR 0005 remains *proposed*. ADR 0003 still
/// holds adapter selection open and nothing here reopens it.
///
/// What the model does fix is the *shape* common to every option ADR 0005 leaves
/// open:
///
/// - Preconditions are captured before a plan can exist, and the plan is a
///   value: an explicit inventory of every artifact with its intended absolute
///   path, ownership and mode.
/// - Staging and validation are separate moments. The gap between them is a
///   TOCTOU window, so validation re-observes rather than trusting what staging
///   believed, and the token types make the wrong order unrepresentable.
/// - The durable ownership record is rewritten at every change of ownership,
///   before the transaction relies on what it just took, so a transaction that
///   dies at any point leaves a record that names what exists.
/// - Recovery is queue-first: the queue is removed before the filter, so a
///   partial failure never leaves a live queue pointing at a removed filter.
/// - Rollback is finite, idempotent and ownership-conservative. It removes
///   exactly what the record names, never a queue it cannot identify as its own,
///   and it refuses a plan that would recover only part of the transaction.
/// - An unverified or unobserved outcome is its own case. Unknown is never
///   false, zero, supported or completed.

// MARK: - Refusals and residual reasons

public enum QueueInstallationRefusal: Equatable, Sendable {
    /// A queue of this name already exists. Creating a queue is create-or-modify,
    /// not create-exclusive, so the transaction refuses outright rather than
    /// adopting or modifying someone else's queue.
    case queueAlreadyPresent
    /// The queue query failed. That is not absence, and it never becomes one.
    case queueStateUnknown
    case protectedRootAlreadyPresent
    case protectedRootStateUnknown
    /// The fixed staging parent is not a real root-owned directory that is
    /// neither group- nor world-writable.
    case stagingParentUnsuitable
    case stagingParentStateUnknown
}

/// Why a transaction stopped in a state a human must inspect. Every one of these
/// is a *failure to know*, and none of them is ever reported as success.
public enum QueueInstallationResidualReason: Equatable, Sendable {
    case queueStateUnknown
    case queueStateUnknownAfterCreation
    case queueAbsentAfterCreation
    case queueRemovalUnverified
    /// A queue of the right name is present, but it could not be shown to be the
    /// one this transaction created. A name is not an identity, so this stops the
    /// transaction instead of deleting someone else's queue.
    case queueIdentityUnverified
    case fileStateUnknown
    case fileRemovalUnverified
    case unexpectedArtifactState
    case effectFailed
    case recoveryPlanUnavailable
}

/// The terminal value of a transaction. Only `completed` means the transaction
/// did what it intended; `residual` is the explicit unknown.
public enum QueueInstallationOutcome: Equatable, Sendable {
    case completed(QueueInstallationOwnershipRecord)
    case rolledBack(QueueInstallationOwnershipRecord)
    case residual(QueueInstallationOwnershipRecord, QueueInstallationResidualReason)

    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    public var requiresManualRecovery: Bool {
        if case .residual = self { return true }
        return false
    }

    public var record: QueueInstallationOwnershipRecord {
        switch self {
        case let .completed(record), let .rolledBack(record), let .residual(record, _): record
        }
    }
}

// MARK: - Effect seam

/// The single injected seam through which a transaction would reach the outside
/// world. `LabelCore` deliberately provides no conforming type: the portable
/// model is inert, and any real implementation is a separately authorized,
/// out-of-scope concern that ADR 0005 has not decided.
///
/// Queries return a tri-state observation instead of throwing, so that a failed
/// query is a value the model must handle rather than an exception a caller
/// could collapse into "absent". A mutating operation that throws guarantees it
/// had no effect; an operation that may or may not have taken effect must not be
/// reported as a throw, because the model would then under-record what it owns.
///
/// `persistOwnershipRecord` **must** replace the record's bytes in one step, so
/// that a reader sees either the previous record or the new one and never a
/// half-written list. This model cannot enforce that from here; it is a
/// requirement on any conforming type, and an implementation that cannot meet it
/// must not conform.
public protocol QueueInstallationEffectSink {
    mutating func observeQueue(_ queue: PlannedSchedulerQueue) -> SchedulerQueueObservation
    mutating func observeFile(at path: AbsolutePath) -> FileArtifactObservation
    mutating func createFile(_ artifact: PlannedFileArtifact) throws
    mutating func createQueue(_ queue: PlannedSchedulerQueue, describedBy description: PlannedFileArtifact) throws
    mutating func persistOwnershipRecord(_ text: String, at artifact: PlannedFileArtifact) throws
    mutating func readOwnershipRecord(at artifact: PlannedFileArtifact) -> OwnershipRecordObservation
    mutating func removeQueue(_ queue: PlannedSchedulerQueue) throws
    mutating func removeFile(at path: AbsolutePath) throws
}

// MARK: - Intent

/// What a transaction would create, before anything has been observed. Every
/// artifact declares its absolute path, ownership and mode; every file lives
/// exactly one component below the protected root, so recovery stays finite and
/// never becomes a recursive delete.
public struct QueueInstallationIntent: Equatable, Sendable {
    public let queue: PlannedSchedulerQueue
    public let protectedRoot: PlannedFileArtifact
    public let ownershipRecord: PlannedFileArtifact
    public let filter: PlannedFileArtifact
    public let printerDescription: PlannedFileArtifact
    /// The fixed directory the protected root is created inside.
    public let stagingParent: AbsolutePath

    public init(
        queue: PlannedSchedulerQueue,
        protectedRoot: PlannedFileArtifact,
        ownershipRecord: PlannedFileArtifact,
        filter: PlannedFileArtifact,
        printerDescription: PlannedFileArtifact
    ) throws {
        guard protectedRoot.kind == .protectedRoot,
              ownershipRecord.kind == .ownershipRecord,
              filter.kind == .filterExecutable,
              printerDescription.kind == .printerDescription else {
            throw QueueInstallationError.artifactKindMismatch
        }
        guard let parent = protectedRoot.path.parent else { throw QueueInstallationError.invalidPath }
        for artifact in [ownershipRecord, filter, printerDescription] {
            guard artifact.path.isImmediateChild(of: protectedRoot.path) else {
                throw QueueInstallationError.artifactOutsideProtectedRoot
            }
        }
        var seen = Set<AbsolutePath>()
        for artifact in [protectedRoot, ownershipRecord, filter, printerDescription] {
            guard seen.insert(artifact.path).inserted else { throw QueueInstallationError.duplicateArtifactPath }
        }
        self.queue = queue
        self.protectedRoot = protectedRoot
        self.ownershipRecord = ownershipRecord
        self.filter = filter
        self.printerDescription = printerDescription
        stagingParent = parent
    }

    /// Creation order. The protected root reserves the namespace first and the
    /// durable ownership record is written before any payload, so a transaction
    /// that dies mid-staging has already named what it may own.
    public var creationOrderedFiles: [PlannedFileArtifact] {
        [protectedRoot, ownershipRecord, filter, printerDescription]
    }

    /// The artifacts placed with `createFile`. The ownership record is not one
    /// of them: it is the transaction's journal, written and rewritten through
    /// `persistOwnershipRecord`.
    public var directlyCreatedFiles: [PlannedFileArtifact] {
        [protectedRoot, filter, printerDescription]
    }
}

// MARK: - Preconditions

/// Everything observed before a plan may exist. Captured once, as a value.
public struct QueueInstallationPreconditions: Equatable, Sendable {
    public let queue: SchedulerQueueObservation
    public let stagingParent: FileArtifactObservation
    public let protectedRoot: FileArtifactObservation

    public init(
        queue: SchedulerQueueObservation,
        stagingParent: FileArtifactObservation,
        protectedRoot: FileArtifactObservation
    ) {
        self.queue = queue
        self.stagingParent = stagingParent
        self.protectedRoot = protectedRoot
    }

    /// Reads the three tri-state queries a plan depends on. This is the only
    /// step that runs before planning, and it creates nothing.
    public static func capture<Sink: QueueInstallationEffectSink>(
        for intent: QueueInstallationIntent,
        from sink: inout Sink
    ) -> Self {
        Self(
            queue: sink.observeQueue(intent.queue),
            stagingParent: sink.observeFile(at: intent.stagingParent),
            protectedRoot: sink.observeFile(at: intent.protectedRoot.path)
        )
    }

    /// nil when planning is admissible. A failed query refuses as *unknown*; it
    /// is never read as absence.
    public var refusal: QueueInstallationRefusal? {
        switch queue {
        case .present: return .queueAlreadyPresent
        case .queryFailed: return .queueStateUnknown
        case .confirmedAbsent: break
        }
        switch protectedRoot {
        case .present: return .protectedRootAlreadyPresent
        case .queryFailed: return .protectedRootStateUnknown
        case .confirmedAbsent: break
        }
        switch stagingParent {
        case .queryFailed:
            return .stagingParentStateUnknown
        case .confirmedAbsent:
            return .stagingParentUnsuitable
        case let .present(state):
            guard state.kind == .directory else { return .stagingParentUnsuitable }
            guard let uid = state.uid, let gid = state.gid, let bits = state.modeBits else {
                return .stagingParentStateUnknown
            }
            guard uid == 0, gid == 0 else { return .stagingParentUnsuitable }
            guard bits & 0o022 == 0 else { return .stagingParentUnsuitable }
            return nil
        }
    }
}

// MARK: - Plan

/// A plan is a value that cannot exist until preconditions admitted it. Holding
/// one changes nothing and authorizes nothing.
public struct QueueInstallationPlan: Equatable, Sendable {
    public let transactionID: QueueInstallationTransactionID
    public let intent: QueueInstallationIntent
    public let preconditions: QueueInstallationPreconditions

    public init(
        transactionID: QueueInstallationTransactionID,
        intent: QueueInstallationIntent,
        preconditions: QueueInstallationPreconditions
    ) throws {
        if let refusal = preconditions.refusal { throw QueueInstallationError.refused(refusal) }
        self.transactionID = transactionID
        self.intent = intent
        self.preconditions = preconditions
    }

    /// The complete inventory of artifacts this transaction would create, in
    /// creation order.
    public var inventory: [QueueInstallationArtifactID] {
        intent.creationOrderedFiles.map { .file($0.path) } + [.schedulerQueue]
    }
}

// MARK: - Ordering tokens

/// Proof that staging ran. Only `QueueInstallationTransaction.stage()` can make
/// one, so validation cannot be reached before staging. It carries the intent it
/// staged, because a transaction identifier alone is caller-supplied and two
/// transactions could share one.
public struct QueueInstallationStagedArtifacts: Equatable, Sendable {
    public let transactionID: QueueInstallationTransactionID
    public let intent: QueueInstallationIntent

    public var artifacts: [PlannedFileArtifact] { intent.creationOrderedFiles }

    fileprivate init(transactionID: QueueInstallationTransactionID, intent: QueueInstallationIntent) {
        self.transactionID = transactionID
        self.intent = intent
    }
}

/// Proof that validation ran *after* staging, against re-read observations.
/// Only `QueueInstallationTransaction.validateStagedArtifacts(_:using:)` can make
/// one, and it consumes a `QueueInstallationStagedArtifacts`, so the two steps
/// cannot be represented in the other order.
public struct QueueInstallationValidatedArtifacts: Equatable, Sendable {
    public let transactionID: QueueInstallationTransactionID
    public let intent: QueueInstallationIntent

    public var artifacts: [PlannedFileArtifact] { intent.creationOrderedFiles }

    fileprivate init(transactionID: QueueInstallationTransactionID, intent: QueueInstallationIntent) {
        self.transactionID = transactionID
        self.intent = intent
    }
}

public enum QueueInstallationPhase: Equatable, Sendable {
    case planned
    case staged
    case validated
    case queueCreated
    case completed
    case rolledBack
    case residual(QueueInstallationResidualReason)
}

// MARK: - Transaction

/// Drives a plan through staging, validate-after-staging, queue creation and
/// either completion or a queue-first rollback.
///
/// The transaction holds no capability of its own. Every step that would reach
/// the outside world takes the seam as an `inout` parameter, exactly as
/// `BoundedDelivery` takes its byte sink, so possessing a transaction grants
/// nothing.
public struct QueueInstallationTransaction {
    public let plan: QueueInstallationPlan
    public private(set) var phase: QueueInstallationPhase
    public private(set) var record: QueueInstallationOwnershipRecord

    public init(plan: QueueInstallationPlan) throws {
        self.plan = plan
        phase = .planned
        record = try QueueInstallationOwnershipRecord(
            transactionID: plan.transactionID,
            queue: plan.intent.queue,
            phase: .inProgress,
            files: plan.intent.creationOrderedFiles,
            createdArtifacts: []
        )
    }

    // MARK: Journalling

    /// Rewrites the durable record. Called after every change of ownership and
    /// before the transaction relies on what it just took, so the record on disk
    /// never lags behind what exists.
    private mutating func writeRecord<Sink: QueueInstallationEffectSink>(using sink: inout Sink) throws {
        do {
            try sink.persistOwnershipRecord(record.canonicalText, at: plan.intent.ownershipRecord)
        } catch {
            throw QueueInstallationError.effectFailed
        }
    }

    /// Rewrites the record only while the record itself is still one of this
    /// transaction's artifacts. Once recovery has removed it, writing again
    /// would recreate the very file that was just cleaned up.
    private mutating func writeRecordIfStillOwned<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws {
        guard record.owns(.file(plan.intent.ownershipRecord.path)) else { return }
        try writeRecord(using: &sink)
    }

    // MARK: Steps

    /// Creates the protected root, writes the durable record, and then places
    /// each remaining artifact, rewriting the record as each one is taken.
    ///
    /// The one irreducible window is between creating the root and the record's
    /// first write: an interruption there can orphan an empty, fixed-name,
    /// root-owned directory and nothing else. Everything created after that
    /// point is named in the record before the transaction moves on.
    public mutating func stage<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws -> QueueInstallationStagedArtifacts {
        guard phase == .planned else { throw QueueInstallationError.invalidPhase }
        for artifact in plan.intent.directlyCreatedFiles {
            do {
                try sink.createFile(artifact)
            } catch {
                throw QueueInstallationError.effectFailed
            }
            record = try record.appendingCreatedArtifact(.file(artifact.path))
            try writeRecord(using: &sink)
            if artifact.kind == .protectedRoot {
                // The first write created the record file itself, so the record
                // now takes ownership of it and says so.
                record = try record.appendingCreatedArtifact(.file(plan.intent.ownershipRecord.path))
                try writeRecord(using: &sink)
            }
        }
        phase = .staged
        return QueueInstallationStagedArtifacts(
            transactionID: plan.transactionID, intent: plan.intent
        )
    }

    /// Re-observes every staged artifact and compares it against the plan.
    /// Staging and validation are separate moments; the gap between them is a
    /// TOCTOU window, so nothing staging believed is carried forward as fact —
    /// including the durable record, which is read back and decoded.
    public mutating func validateStagedArtifacts<Sink: QueueInstallationEffectSink>(
        _ staged: QueueInstallationStagedArtifacts,
        using sink: inout Sink
    ) throws -> QueueInstallationValidatedArtifacts {
        guard phase == .staged else { throw QueueInstallationError.invalidPhase }
        // A transaction identifier is caller-supplied, so the token must also
        // carry the intent it staged; otherwise one transaction could validate
        // another's paths and then create its own queue having checked nothing.
        guard staged.transactionID == plan.transactionID, staged.intent == plan.intent else {
            throw QueueInstallationError.transactionMismatch
        }
        for artifact in plan.intent.creationOrderedFiles {
            let observation = sink.observeFile(at: artifact.path)
            if let failure = artifact.validationFailure(against: observation) {
                throw QueueInstallationError.stagedArtifactInvalid(artifact.kind, failure)
            }
        }
        switch sink.readOwnershipRecord(at: plan.intent.ownershipRecord) {
        case .queryFailed:
            throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .observationFailed)
        case .confirmedAbsent:
            throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .absent)
        case let .present(text):
            guard let durable = try? QueueInstallationOwnershipRecord.decode(text), durable == record else {
                throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .contentMismatch)
            }
        }
        phase = .validated
        return QueueInstallationValidatedArtifacts(
            transactionID: plan.transactionID, intent: plan.intent
        )
    }

    /// Creating a queue is create-or-modify, not create-exclusive, so absence is
    /// re-proved immediately beforehand. A failed query refuses; it is never
    /// read as absence. The queue is recorded as owned before anything relies on
    /// it, and the identity observed for it is bound into the record so that a
    /// later removal can require an exact match.
    public mutating func createQueue<Sink: QueueInstallationEffectSink>(
        authorizedBy validated: QueueInstallationValidatedArtifacts,
        using sink: inout Sink
    ) throws {
        guard phase == .validated else { throw QueueInstallationError.invalidPhase }
        guard validated.transactionID == plan.transactionID, validated.intent == plan.intent else {
            throw QueueInstallationError.transactionMismatch
        }
        switch sink.observeQueue(plan.intent.queue) {
        case .present: throw QueueInstallationError.refused(.queueAlreadyPresent)
        case .queryFailed: throw QueueInstallationError.refused(.queueStateUnknown)
        case .confirmedAbsent: break
        }
        do {
            try sink.createQueue(plan.intent.queue, describedBy: plan.intent.printerDescription)
        } catch {
            throw QueueInstallationError.effectFailed
        }
        record = try record.appendingCreatedArtifact(.schedulerQueue)
        try writeRecord(using: &sink)
        if case let .present(identity) = sink.observeQueue(plan.intent.queue), identity != nil {
            record = try record.bindingQueueIdentity(identity)
            try writeRecord(using: &sink)
        }
        phase = .queueCreated
    }

    /// Completion requires an affirmative observation *of this transaction's own
    /// queue*. An unknown, absent or unidentifiable queue is residual, never
    /// success.
    public mutating func complete<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws -> QueueInstallationOutcome {
        guard phase == .queueCreated else { throw QueueInstallationError.invalidPhase }
        switch sink.observeQueue(plan.intent.queue) {
        case let .present(observed):
            guard let observed, let recorded = record.queueIdentity, observed == recorded else {
                return enterResidual(.queueIdentityUnverified, using: &sink)
            }
            record = try record.replacingPhase(.completed)
            do {
                try writeRecordIfStillOwned(using: &sink)
            } catch {
                return enterResidual(.effectFailed, using: &sink)
            }
            phase = .completed
            return .completed(record)
        case .queryFailed:
            return enterResidual(.queueStateUnknownAfterCreation, using: &sink)
        case .confirmedAbsent:
            return enterResidual(.queueAbsentAfterCreation, using: &sink)
        }
    }

    /// The queue-first recovery this transaction owns, derived from its record.
    public func recoveryPlan() throws -> QueueInstallationRecoveryPlan {
        try QueueInstallationRecoveryPlan(record: record)
    }

    /// One finite pass of queue-first recovery over exactly what this
    /// transaction created. Calling it again is safe: artifacts already
    /// confirmed absent are dropped from the record instead of removed twice.
    public mutating func rollBack<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) -> QueueInstallationOutcome {
        guard let recovery = try? recoveryPlan() else {
            return enterResidual(.recoveryPlanUnavailable, using: &sink)
        }
        guard let outcome = try? rollBack(following: recovery, using: &sink) else {
            return enterResidual(.recoveryPlanUnavailable, using: &sink)
        }
        return outcome
    }

    /// Ownership is conserved in both directions, and both checks run before any
    /// effect. A plan naming an artifact this transaction did not create removes
    /// nothing; and a plan that is not exactly the one this record derives —
    /// an empty plan, or one that drops the queue and keeps the filter — removes
    /// nothing either, because recovering part of a transaction is not a
    /// rollback and must never be reported as one.
    public mutating func rollBack<Sink: QueueInstallationEffectSink>(
        following recovery: QueueInstallationRecoveryPlan,
        using sink: inout Sink
    ) throws -> QueueInstallationOutcome {
        for step in recovery.steps {
            guard record.owns(step.artifactID) else { throw QueueInstallationError.notOwnedByTransaction }
            if case let .removeFile(artifact) = step {
                guard record.files.contains(artifact) else { throw QueueInstallationError.notOwnedByTransaction }
            }
        }
        guard recovery == (try QueueInstallationRecoveryPlan(record: record)) else {
            throw QueueInstallationError.incompleteRecoveryPlan
        }
        for step in recovery.steps {
            switch step {
            case let .removeQueue(queue):
                if let residual = removeQueueStep(queue, using: &sink) { return residual }
            case let .removeFile(artifact):
                if let residual = removeFileStep(artifact, using: &sink) { return residual }
            }
        }
        record = try record.replacingPhase(.rolledBack)
        phase = .rolledBack
        return .rolledBack(record)
    }

    private mutating func removeQueueStep<Sink: QueueInstallationEffectSink>(
        _ queue: PlannedSchedulerQueue, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        switch sink.observeQueue(queue) {
        case .queryFailed:
            return enterResidual(.queueStateUnknown, using: &sink)
        case .confirmedAbsent:
            return dropping(.schedulerQueue, using: &sink)
        case let .present(observed):
            // A name is not an identity. If this transaction's queue was already
            // removed and another administrator created one with the same name,
            // removing it would destroy theirs, so an identity that is missing or
            // different stops the rollback instead.
            guard let observed, let recorded = record.queueIdentity, observed == recorded else {
                return enterResidual(.queueIdentityUnverified, using: &sink)
            }
            do {
                try sink.removeQueue(queue)
            } catch {
                return enterResidual(.effectFailed, using: &sink)
            }
            // Removal is only believed once absence is re-observed. Nothing the
            // queue depends on may be removed before that.
            switch sink.observeQueue(queue) {
            case .confirmedAbsent:
                return dropping(.schedulerQueue, using: &sink)
            case .present:
                return enterResidual(.queueRemovalUnverified, using: &sink)
            case .queryFailed:
                return enterResidual(.queueStateUnknown, using: &sink)
            }
        }
    }

    private mutating func removeFileStep<Sink: QueueInstallationEffectSink>(
        _ artifact: PlannedFileArtifact, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        let observation = sink.observeFile(at: artifact.path)
        if observation.isConfirmedAbsent {
            return dropping(.file(artifact.path), using: &sink)
        }
        if let failure = artifact.validationFailure(against: observation) {
            // Something other than what this transaction created now occupies
            // the path, or the query failed. Either way it is retained for a
            // human, not deleted on a guess.
            return enterResidual(
                failure == .observationFailed ? .fileStateUnknown : .unexpectedArtifactState, using: &sink
            )
        }
        if artifact.kind == .ownershipRecord {
            // The journal is the one artifact whose bytes no planned digest can
            // pin, because it is rewritten as the transaction runs. Metadata
            // alone would let a replaced journal be deleted, so read it back and
            // require that it is still this transaction's.
            switch sink.readOwnershipRecord(at: artifact) {
            case .queryFailed:
                return enterResidual(.fileStateUnknown, using: &sink)
            case .confirmedAbsent:
                return enterResidual(.unexpectedArtifactState, using: &sink)
            case let .present(text):
                guard let durable = try? QueueInstallationOwnershipRecord.decode(text),
                      durable.transactionID == record.transactionID else {
                    return enterResidual(.unexpectedArtifactState, using: &sink)
                }
            }
        }
        do {
            try sink.removeFile(at: artifact.path)
        } catch {
            return enterResidual(.effectFailed, using: &sink)
        }
        guard sink.observeFile(at: artifact.path).isConfirmedAbsent else {
            return enterResidual(.fileRemovalUnverified, using: &sink)
        }
        return dropping(.file(artifact.path), using: &sink)
    }

    /// Drops a confirmed-absent artifact from the record and journals the
    /// shorter list, so an interruption mid-recovery still leaves a record that
    /// names exactly what is left.
    private mutating func dropping<Sink: QueueInstallationEffectSink>(
        _ id: QueueInstallationArtifactID, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        record = record.removingCreatedArtifact(id)
        do {
            try writeRecordIfStillOwned(using: &sink)
        } catch {
            return enterResidual(.effectFailed, using: &sink)
        }
        return nil
    }

    private mutating func enterResidual<Sink: QueueInstallationEffectSink>(
        _ reason: QueueInstallationResidualReason, using sink: inout Sink
    ) -> QueueInstallationOutcome {
        phase = .residual(reason)
        record = record.markingResidual()
        // A best effort: the transaction is already in a state a human must
        // inspect, and failing to journal that does not make it less so.
        try? writeRecordIfStillOwned(using: &sink)
        return .residual(record, reason)
    }
}
