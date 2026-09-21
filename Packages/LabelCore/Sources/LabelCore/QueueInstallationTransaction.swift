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
/// - A durable ownership record names every artifact created, so recovery is
///   finite and a human can recover from evidence rather than guesswork.
/// - Recovery is queue-first: the queue is removed before the filter, so a
///   partial failure never leaves a live queue pointing at a removed filter.
/// - Rollback is finite, idempotent and ownership-conservative. It never removes
///   anything the transaction did not create, and it never deletes a
///   pre-existing queue.
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
/// could collapse into "absent".
public protocol QueueInstallationEffectSink {
    mutating func observeQueue(_ queue: PlannedSchedulerQueue) -> SchedulerQueueObservation
    mutating func observeFile(at path: AbsolutePath) -> FileArtifactObservation
    mutating func createFile(_ artifact: PlannedFileArtifact) throws
    mutating func createQueue(_ queue: PlannedSchedulerQueue, describedBy description: PlannedFileArtifact) throws
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
/// one, so validation cannot be reached before staging.
public struct QueueInstallationStagedArtifacts: Equatable, Sendable {
    public let transactionID: QueueInstallationTransactionID
    public let artifacts: [PlannedFileArtifact]

    fileprivate init(transactionID: QueueInstallationTransactionID, artifacts: [PlannedFileArtifact]) {
        self.transactionID = transactionID
        self.artifacts = artifacts
    }
}

/// Proof that validation ran *after* staging, against re-read observations.
/// Only `QueueInstallationTransaction.validateStagedArtifacts(_:)` can make one,
/// and it consumes a `QueueInstallationStagedArtifacts`, so the two steps cannot
/// be represented in the other order.
public struct QueueInstallationValidatedArtifacts: Equatable, Sendable {
    public let transactionID: QueueInstallationTransactionID
    public let artifacts: [PlannedFileArtifact]

    fileprivate init(transactionID: QueueInstallationTransactionID, artifacts: [PlannedFileArtifact]) {
        self.transactionID = transactionID
        self.artifacts = artifacts
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

    /// Creates every planned file artifact in creation order. On failure the
    /// record already names whatever was created, which is what makes the
    /// following rollback finite.
    public mutating func stage<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws -> QueueInstallationStagedArtifacts {
        guard phase == .planned else { throw QueueInstallationError.invalidPhase }
        for artifact in plan.intent.creationOrderedFiles {
            do {
                try sink.createFile(artifact)
            } catch {
                throw QueueInstallationError.effectFailed
            }
            record = try record.appendingCreatedArtifact(.file(artifact.path))
        }
        phase = .staged
        return QueueInstallationStagedArtifacts(
            transactionID: plan.transactionID,
            artifacts: plan.intent.creationOrderedFiles
        )
    }

    /// Re-observes every staged artifact and compares it against the plan.
    /// Staging and validation are separate moments; the gap between them is a
    /// TOCTOU window, so nothing staging believed is carried forward as fact.
    public mutating func validateStagedArtifacts<Sink: QueueInstallationEffectSink>(
        _ staged: QueueInstallationStagedArtifacts,
        using sink: inout Sink
    ) throws -> QueueInstallationValidatedArtifacts {
        guard phase == .staged else { throw QueueInstallationError.invalidPhase }
        guard staged.transactionID == plan.transactionID else {
            throw QueueInstallationError.transactionMismatch
        }
        for artifact in staged.artifacts {
            let observation = sink.observeFile(at: artifact.path)
            if let failure = artifact.validationFailure(against: observation) {
                throw QueueInstallationError.stagedArtifactInvalid(artifact.kind, failure)
            }
        }
        phase = .validated
        return QueueInstallationValidatedArtifacts(
            transactionID: plan.transactionID,
            artifacts: staged.artifacts
        )
    }

    /// Creating a queue is create-or-modify, not create-exclusive, so absence is
    /// re-proved immediately beforehand. A failed query refuses; it is never
    /// read as absence.
    public mutating func createQueue<Sink: QueueInstallationEffectSink>(
        authorizedBy validated: QueueInstallationValidatedArtifacts,
        using sink: inout Sink
    ) throws {
        guard phase == .validated else { throw QueueInstallationError.invalidPhase }
        guard validated.transactionID == plan.transactionID else {
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
        phase = .queueCreated
    }

    /// Completion requires an affirmative observation. An unknown or absent
    /// queue after creation is residual, never success.
    public mutating func complete<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws -> QueueInstallationOutcome {
        guard phase == .queueCreated else { throw QueueInstallationError.invalidPhase }
        switch sink.observeQueue(plan.intent.queue) {
        case .present:
            phase = .completed
            record = record.replacingPhase(.completed)
            return .completed(record)
        case .queryFailed:
            return enterResidual(.queueStateUnknownAfterCreation)
        case .confirmedAbsent:
            return enterResidual(.queueAbsentAfterCreation)
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
            return enterResidual(.recoveryPlanUnavailable)
        }
        guard let outcome = try? rollBack(following: recovery, using: &sink) else {
            return enterResidual(.recoveryPlanUnavailable)
        }
        return outcome
    }

    /// Ownership is conserved: the whole recovery plan is checked against the
    /// record before any effect runs, so a plan naming an artifact this
    /// transaction did not create removes nothing at all.
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
        for step in recovery.steps {
            switch step {
            case let .removeQueue(queue):
                if let residual = removeQueueStep(queue, using: &sink) { return residual }
            case let .removeFile(artifact):
                if let residual = removeFileStep(artifact, using: &sink) { return residual }
            }
        }
        phase = .rolledBack
        record = record.replacingPhase(.rolledBack)
        return .rolledBack(record)
    }

    private mutating func removeQueueStep<Sink: QueueInstallationEffectSink>(
        _ queue: PlannedSchedulerQueue, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        switch sink.observeQueue(queue) {
        case .queryFailed:
            return enterResidual(.queueStateUnknown)
        case .confirmedAbsent:
            record = record.removingCreatedArtifact(.schedulerQueue)
            return nil
        case .present:
            do {
                try sink.removeQueue(queue)
            } catch {
                return enterResidual(.effectFailed)
            }
            // Removal is only believed once absence is re-observed. Nothing the
            // queue depends on may be removed before that.
            switch sink.observeQueue(queue) {
            case .confirmedAbsent:
                record = record.removingCreatedArtifact(.schedulerQueue)
                return nil
            case .present:
                return enterResidual(.queueRemovalUnverified)
            case .queryFailed:
                return enterResidual(.queueStateUnknown)
            }
        }
    }

    private mutating func removeFileStep<Sink: QueueInstallationEffectSink>(
        _ artifact: PlannedFileArtifact, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        let observation = sink.observeFile(at: artifact.path)
        if observation.isConfirmedAbsent {
            record = record.removingCreatedArtifact(.file(artifact.path))
            return nil
        }
        if let failure = artifact.validationFailure(against: observation) {
            // Something other than what this transaction created now occupies
            // the path, or the query failed. Either way it is retained for a
            // human, not deleted on a guess.
            return enterResidual(failure == .observationFailed ? .fileStateUnknown : .unexpectedArtifactState)
        }
        do {
            try sink.removeFile(at: artifact.path)
        } catch {
            return enterResidual(.effectFailed)
        }
        guard sink.observeFile(at: artifact.path).isConfirmedAbsent else {
            return enterResidual(.fileRemovalUnverified)
        }
        record = record.removingCreatedArtifact(.file(artifact.path))
        return nil
    }

    private mutating func enterResidual(
        _ reason: QueueInstallationResidualReason
    ) -> QueueInstallationOutcome {
        phase = .residual(reason)
        record = record.replacingPhase(.residual)
        return .residual(record, reason)
    }
}
