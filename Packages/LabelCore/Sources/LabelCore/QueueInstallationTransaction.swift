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
/// What the model fixes is the *shape* common to every option ADR 0005 leaves
/// open, and — just as much — the shape of what cannot be promised:
///
/// - Preconditions are captured before a plan can exist, are bound to the intent
///   they inspected, and the plan is a value.
/// - Staging and validation are separate moments, and so are validation and
///   queue creation: every staged artifact is re-observed immediately before the
///   queue that would point at it is created.
/// - Every step is journalled *before* its effect runs and confirmed after, so
///   an interruption leaves an artifact whose existence is unknown but whose
///   name is recorded. Journal writes are conditional on the bytes last written.
/// - Recovery is queue-first, finite, idempotent and ownership-conservative, and
///   it can be loaded back from the journal alone — see
///   `QueueInstallationRecovery`.
/// - Acquiring a queue *name* is not something a create-or-modify operation can
///   prove. A transaction whose seam cannot prove exclusive creation is not
///   completed; it is residual with the ambiguity named.
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

/// Why a transaction or recovery stopped in a state a human must inspect. Every
/// one of these is a *failure to know*, and none is ever reported as success.
public enum QueueInstallationResidualReason: Equatable, Sendable {
    case queueStateUnknown
    case queueStateUnknownAfterCreation
    case queueAbsentAfterCreation
    case queueRemovalUnverified
    /// A queue of the right name is present, but it does not carry the
    /// unrepeatable incarnation token this transaction wrote. A name is not an
    /// identity, so this stops recovery instead of deleting someone else's queue.
    case queueIncarnationUnverified
    /// The queue is present and this transaction cannot prove it acquired the
    /// name rather than modifying a queue that appeared first. Automatic
    /// recovery never removes a present queue for this reason.
    case queueOwnershipAmbiguous
    /// The journal no longer holds the bytes this transaction last wrote, so the
    /// write was refused rather than destroying whatever replaced them.
    case journalConflict
    case fileStateUnknown
    case fileRemovalUnverified
    case unexpectedArtifactState
    case effectFailed
    case recoveryPlanUnavailable
}

/// Who is driving a recovery, and therefore what it is allowed to destroy.
public enum QueueInstallationRecoveryAuthority: String, Equatable, Sendable, CaseIterable {
    /// A transaction cleaning up after itself, unattended. It never removes a
    /// queue that is present, because create-or-modify success cannot prove who
    /// acquired the name.
    case automatic
    /// A separately authorized recovery driven from the durable record. It may
    /// remove a present queue, but only one carrying this record's exact
    /// incarnation token.
    case recordValidated = "record-validated"
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
/// **Four of these carry requirements this model cannot enforce.** They are
/// stated here because stating them is the model's job; meeting them is the
/// conformer's, and an implementation that cannot meet one must not conform:
///
/// - `createProtectedRoot` must fail if anything already exists at the path —
///   `mkdir` semantics, not create-or-replace. This is the transaction's only
///   exclusive namespace reservation.
/// - `persistOwnershipRecord` must replace the journal's bytes in one step, and
///   only if its current contents are exactly `previous` (`nil` meaning it must
///   not exist at all). Without that condition an unconditional rewrite would
///   destroy a journal something else had replaced. Note honestly that advisory
///   locking cannot bind a writer that declines to cooperate.
/// - `removeEmptyDirectory` must fail when the directory is not empty —
///   `rmdir` semantics. A recursive delete would sweep away an unowned child
///   that appeared beneath the protected root.
/// - `createQueue` must write `incarnation` into the queue's own configuration
///   so a later read can return it, and must report `exclusiveCreation` only if
///   it can prove it created the name rather than modifying a queue that
///   appeared first. An `lpadmin`-style create-or-modify operation cannot prove
///   that and must report `ambiguousCreateOrModify`.
public protocol QueueInstallationEffectSink {
    mutating func observeQueue(_ queue: PlannedSchedulerQueue) -> SchedulerQueueObservation
    mutating func observeFile(at path: AbsolutePath) -> FileArtifactObservation
    mutating func createProtectedRoot(_ artifact: PlannedFileArtifact) throws
    mutating func createFile(_ artifact: PlannedFileArtifact) throws
    mutating func persistOwnershipRecord(
        _ text: String, replacing previous: String?, at artifact: PlannedFileArtifact
    ) throws
    mutating func readOwnershipRecord(at artifact: PlannedFileArtifact) -> OwnershipRecordObservation
    mutating func createQueue(
        _ queue: PlannedSchedulerQueue,
        describedBy description: PlannedFileArtifact,
        incarnation: SchedulerQueueIncarnation
    ) throws -> SchedulerQueueAcquisition
    mutating func removeQueue(_ queue: PlannedSchedulerQueue) throws
    mutating func removeFile(at path: AbsolutePath) throws
    mutating func removeEmptyDirectory(at path: AbsolutePath) throws
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
    /// journal is written before any payload, so a transaction that dies
    /// mid-staging has already named what it may own.
    public var creationOrderedFiles: [PlannedFileArtifact] {
        [protectedRoot, ownershipRecord, filter, printerDescription]
    }

    /// The payload artifacts placed with `createFile`. The root has its own
    /// exclusive reservation operation, and the journal is written and rewritten
    /// through `persistOwnershipRecord`.
    public var stagedPayloadFiles: [PlannedFileArtifact] {
        [filter, printerDescription]
    }
}

// MARK: - Preconditions

/// Everything observed before a plan may exist, together with the intent those
/// observations were made *for*.
///
/// The binding matters: preconditions inspect a specific staging parent and a
/// specific protected root, so letting a plan accept observations taken for some
/// other intent would defeat the protected-root assumption before staging
/// starts. Construction is therefore restricted to `capture`.
public struct QueueInstallationPreconditions: Equatable, Sendable {
    public let intent: QueueInstallationIntent
    public let queue: SchedulerQueueObservation
    public let stagingParent: FileArtifactObservation
    public let protectedRoot: FileArtifactObservation

    private init(
        intent: QueueInstallationIntent,
        queue: SchedulerQueueObservation,
        stagingParent: FileArtifactObservation,
        protectedRoot: FileArtifactObservation
    ) {
        self.intent = intent
        self.queue = queue
        self.stagingParent = stagingParent
        self.protectedRoot = protectedRoot
    }

    /// Reads the three tri-state queries a plan depends on. This is the only
    /// step that runs before planning, the only way to obtain this value, and
    /// it creates nothing.
    public static func capture<Sink: QueueInstallationEffectSink>(
        for intent: QueueInstallationIntent,
        from sink: inout Sink
    ) -> Self {
        Self(
            intent: intent,
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

/// A plan is a value that cannot exist until preconditions taken *for this
/// intent* admitted it. Holding one changes nothing and authorizes nothing.
public struct QueueInstallationPlan: Equatable, Sendable {
    public let transactionID: QueueInstallationTransactionID
    /// The unrepeatable token this transaction will write into its queue's
    /// configuration. Supplied by the caller; the model generates no randomness.
    public let queueIncarnation: SchedulerQueueIncarnation
    public let intent: QueueInstallationIntent
    public let preconditions: QueueInstallationPreconditions

    public init(
        transactionID: QueueInstallationTransactionID,
        queueIncarnation: SchedulerQueueIncarnation,
        intent: QueueInstallationIntent,
        preconditions: QueueInstallationPreconditions
    ) throws {
        guard preconditions.intent == intent else {
            throw QueueInstallationError.preconditionsIntentMismatch
        }
        if let refusal = preconditions.refusal { throw QueueInstallationError.refused(refusal) }
        self.transactionID = transactionID
        self.queueIncarnation = queueIncarnation
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

/// Proof that staging ran. Only `QueueInstallationTransaction.stage(using:)` can
/// make one, so validation cannot be reached before staging. It carries the
/// intent it staged, because a transaction identifier alone is caller-supplied
/// and two transactions could share one.
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
///
/// It is proof that validation happened, not that it still holds: the artifacts
/// are re-observed again immediately before the queue is created.
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
    /// The exact journal bytes this transaction last wrote. Every subsequent
    /// write is conditional on them.
    public private(set) var lastDurableText: String?

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

    /// Rewrites the journal, conditional on the bytes last written. Called with
    /// a step marked pending *before* its effect runs, and again once the effect
    /// is confirmed, so the record never lags behind what may exist.
    private mutating func writeJournal<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink, creating: Bool = false
    ) throws {
        let text = record.canonicalText
        do {
            try sink.persistOwnershipRecord(
                text, replacing: creating ? nil : lastDurableText, at: plan.intent.ownershipRecord
            )
        } catch {
            throw QueueInstallationError.effectFailed
        }
        lastDurableText = text
    }

    /// Re-observes every staged artifact and the journal, and requires each to
    /// still match the plan exactly.
    private mutating func revalidateStagedArtifacts<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws {
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
    }

    // MARK: Steps

    /// Reserves the protected root exclusively, writes the journal inside it,
    /// then places each payload artifact — journalling the step as pending
    /// before its effect and as created after it.
    ///
    /// The one irreducible window is the root reservation itself, because the
    /// journal has nowhere to live until the root exists. An interruption there
    /// can orphan one empty, fixed-name, root-owned directory and nothing else;
    /// `docs/validation/M1-TRANSACTION-RECOVERY.md` describes the manual check
    /// that window requires. Everything after it is named before its effect.
    public mutating func stage<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws -> QueueInstallationStagedArtifacts {
        guard phase == .planned else { throw QueueInstallationError.invalidPhase }
        do {
            try sink.createProtectedRoot(plan.intent.protectedRoot)
        } catch {
            throw QueueInstallationError.effectFailed
        }
        record = try record.markingPending(.file(plan.intent.protectedRoot.path))
        record = try record.confirmingPending()
        // The journal's own first write is its creation, so it is exclusive: a
        // journal already inside a root we just exclusively reserved would be a
        // contradiction, and is refused rather than overwritten.
        record = try record.markingPending(.file(plan.intent.ownershipRecord.path))
        record = try record.confirmingPending()
        try writeJournal(using: &sink, creating: true)

        for artifact in plan.intent.stagedPayloadFiles {
            record = try record.markingPending(.file(artifact.path))
            try writeJournal(using: &sink)
            do {
                try sink.createFile(artifact)
            } catch {
                throw QueueInstallationError.effectFailed
            }
            record = try record.confirmingPending()
            try writeJournal(using: &sink)
        }
        phase = .staged
        return QueueInstallationStagedArtifacts(
            transactionID: plan.transactionID, intent: plan.intent
        )
    }

    /// Re-observes every staged artifact and compares it against the plan.
    /// Staging and validation are separate moments; the gap between them is a
    /// TOCTOU window, so nothing staging believed is carried forward as fact —
    /// including the journal, which is read back and decoded.
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
        try revalidateStagedArtifacts(using: &sink)
        phase = .validated
        return QueueInstallationValidatedArtifacts(
            transactionID: plan.transactionID, intent: plan.intent
        )
    }

    /// Creates the queue, having first re-proved that every staged artifact is
    /// still exactly as validated — a validation token says validation *happened*,
    /// not that it still holds, and a queue must never be pointed at a filter
    /// that changed in between.
    ///
    /// Absence is re-proved immediately beforehand because creating a queue is
    /// create-or-modify; a failed query refuses and is never read as absence.
    /// The step is journalled as pending before the effect, and the incarnation
    /// token must read back out of the created queue's configuration before it
    /// is recorded as created.
    public mutating func createQueue<Sink: QueueInstallationEffectSink>(
        authorizedBy validated: QueueInstallationValidatedArtifacts,
        using sink: inout Sink
    ) throws {
        guard phase == .validated else { throw QueueInstallationError.invalidPhase }
        guard validated.transactionID == plan.transactionID, validated.intent == plan.intent else {
            throw QueueInstallationError.transactionMismatch
        }
        try revalidateStagedArtifacts(using: &sink)
        switch sink.observeQueue(plan.intent.queue) {
        case .present: throw QueueInstallationError.refused(.queueAlreadyPresent)
        case .queryFailed: throw QueueInstallationError.refused(.queueStateUnknown)
        case .confirmedAbsent: break
        }
        record = try record.markingPending(.schedulerQueue)
        try writeJournal(using: &sink)
        let acquisition: SchedulerQueueAcquisition
        do {
            acquisition = try sink.createQueue(
                plan.intent.queue,
                describedBy: plan.intent.printerDescription,
                incarnation: plan.queueIncarnation
            )
        } catch {
            throw QueueInstallationError.effectFailed
        }
        // The queue stays *pending* until its own configuration hands back the
        // token we wrote. Until then its existence is recorded but unproven as
        // ours, which is exactly what recovery needs to know.
        guard case let .present(observed) = sink.observeQueue(plan.intent.queue),
              let observed, observed == plan.queueIncarnation else {
            throw QueueInstallationError.queueIncarnationUnconfirmed
        }
        record = try record.confirmingPending(
            queueIncarnation: plan.queueIncarnation, queueAcquisition: acquisition
        )
        try writeJournal(using: &sink)
        phase = .queueCreated
    }

    /// Completion requires an affirmative observation of this transaction's own
    /// queue *and* proof that the name was acquired rather than possibly
    /// modified. An unknown, absent, unidentifiable or ambiguously acquired
    /// queue is residual, never success.
    ///
    /// A seam built on `lpadmin` reports `ambiguousCreateOrModify`, so it never
    /// reaches `completed` here. That is deliberate and is a finding for
    /// ADR 0005, not a defect to relax.
    public mutating func complete<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws -> QueueInstallationOutcome {
        guard phase == .queueCreated else { throw QueueInstallationError.invalidPhase }
        switch sink.observeQueue(plan.intent.queue) {
        case let .present(observed):
            guard let observed, observed == plan.queueIncarnation,
                  record.queueIncarnation == plan.queueIncarnation else {
                return enterResidual(.queueIncarnationUnverified, using: &sink)
            }
            guard record.queueAcquisition == .exclusiveCreation else {
                return enterResidual(.queueOwnershipAmbiguous, using: &sink)
            }
            do {
                record = try record.replacingPhase(.completed)
                try writeJournal(using: &sink)
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

    /// Rolls the transaction back through the shared recovery executor, with
    /// `automatic` authority: it will not remove a queue that is present.
    public mutating func rollBack<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) -> QueueInstallationOutcome {
        guard var recovery = try? recoveryExecutor() else {
            return enterResidual(.recoveryPlanUnavailable, using: &sink)
        }
        let outcome = recovery.recover(using: &sink)
        adopt(recovery, outcome: outcome)
        return outcome
    }

    public mutating func rollBack<Sink: QueueInstallationEffectSink>(
        following plan: QueueInstallationRecoveryPlan,
        using sink: inout Sink
    ) throws -> QueueInstallationOutcome {
        var recovery = try recoveryExecutor()
        let outcome = try recovery.recover(following: plan, using: &sink)
        adopt(recovery, outcome: outcome)
        return outcome
    }

    private func recoveryExecutor() throws -> QueueInstallationRecovery {
        try QueueInstallationRecovery(
            resuming: record, authority: .automatic, lastDurableText: lastDurableText
        )
    }

    private mutating func adopt(
        _ recovery: QueueInstallationRecovery, outcome: QueueInstallationOutcome
    ) {
        record = recovery.record
        lastDurableText = recovery.lastDurableText
        switch outcome {
        case .rolledBack: phase = .rolledBack
        case let .residual(_, reason): phase = .residual(reason)
        case .completed: break
        }
    }

    private mutating func enterResidual<Sink: QueueInstallationEffectSink>(
        _ reason: QueueInstallationResidualReason, using sink: inout Sink
    ) -> QueueInstallationOutcome {
        phase = .residual(reason)
        record = record.markingResidual()
        // A best effort, and a conditional one: the transaction is already in a
        // state a human must inspect, and failing to journal that does not make
        // it less so.
        try? writeJournal(using: &sink)
        return .residual(record, reason)
    }
}
