import Foundation

/// Executes one finite, queue-first recovery pass over exactly what a durable
/// ownership record names.
///
/// This is the only implementation of recovery in the model, and it is reached
/// two ways: by a live transaction rolling itself back, and by `load`, which
/// hydrates it from the journal's bytes after the process that wrote them is
/// gone. That second path is the whole point of journalling — a record nothing
/// can load back is write-only — and it cannot go through
/// `QueueInstallationPlan`, because a plan's preconditions refuse an existing
/// protected root. Recovery therefore needs no plan: the record is sufficient.
///
/// Nothing here is privileged and nothing here is an installation path. Every
/// effect goes through the injected seam, and `LabelCore` ships no conforming
/// type.
public struct QueueInstallationRecovery {
    public let authority: QueueInstallationRecoveryAuthority
    public private(set) var record: QueueInstallationOwnershipRecord
    /// The exact bytes this recovery last saw durably. Every journal write is
    /// conditional on them, so a journal replaced behind our back is detected
    /// instead of overwritten.
    public private(set) var lastDurableText: String?
    private let journal: PlannedFileArtifact

    public init(
        resuming record: QueueInstallationOwnershipRecord,
        authority: QueueInstallationRecoveryAuthority,
        lastDurableText: String? = nil
    ) throws {
        guard let journal = record.journalArtifact else { throw QueueInstallationError.recordHasNoJournal }
        self.record = record
        self.authority = authority
        self.lastDurableText = lastDurableText
        self.journal = journal
    }

    /// Hydrates recovery state from the journal on the other side of the seam.
    /// The bytes are decoded strictly and must describe a record that lives in
    /// the very artifact they were read from.
    public static func load<Sink: QueueInstallationEffectSink>(
        journalAt journal: PlannedFileArtifact,
        authority: QueueInstallationRecoveryAuthority,
        using sink: inout Sink
    ) throws -> Self {
        guard journal.kind == .ownershipRecord else { throw QueueInstallationError.artifactKindMismatch }
        switch sink.readOwnershipRecord(at: journal) {
        case .queryFailed:
            // Unreadable is not absent and is certainly not "nothing to do".
            throw QueueInstallationError.effectFailed
        case .confirmedAbsent:
            throw QueueInstallationError.invalidRecord
        case let .present(text):
            let record = try QueueInstallationOwnershipRecord.decode(text)
            guard record.journalArtifact == journal else { throw QueueInstallationError.recordHasNoJournal }
            return try Self(resuming: record, authority: authority, lastDurableText: text)
        }
    }

    /// The queue-first plan this record derives, covering created artifacts and
    /// the pending one.
    public func recoveryPlan() throws -> QueueInstallationRecoveryPlan {
        try QueueInstallationRecoveryPlan(record: record)
    }

    /// One finite pass. Calling it again is safe: artifacts already confirmed
    /// absent were dropped from the record instead of removed twice.
    public mutating func recover<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) -> QueueInstallationOutcome {
        guard let plan = try? recoveryPlan() else {
            return enterResidual(.recoveryPlanUnavailable, using: &sink)
        }
        guard let outcome = try? recover(following: plan, using: &sink) else {
            return enterResidual(.recoveryPlanUnavailable, using: &sink)
        }
        return outcome
    }

    /// Ownership is conserved in both directions, and both checks run before any
    /// effect. A plan naming an artifact this record does not own removes
    /// nothing; and a plan that is not exactly the one this record derives —
    /// an empty plan, or one that drops the queue and keeps the filter — removes
    /// nothing either, because recovering part of a transaction is not a
    /// rollback and must never be reported as one.
    public mutating func recover<Sink: QueueInstallationEffectSink>(
        following plan: QueueInstallationRecoveryPlan,
        using sink: inout Sink
    ) throws -> QueueInstallationOutcome {
        for step in plan.steps {
            guard record.owns(step.artifactID) else { throw QueueInstallationError.notOwnedByTransaction }
            if case let .removeFile(artifact) = step {
                guard record.files.contains(artifact) else { throw QueueInstallationError.notOwnedByTransaction }
            }
        }
        guard plan == (try QueueInstallationRecoveryPlan(record: record)) else {
            throw QueueInstallationError.incompleteRecoveryPlan
        }
        for step in plan.steps {
            switch step {
            case let .removeQueue(queue):
                if let residual = removeQueueStep(queue, using: &sink) { return residual }
            case let .removeFile(artifact):
                if let residual = removeFileStep(artifact, using: &sink) { return residual }
            }
        }
        record = try record.replacingPhase(.rolledBack)
        return .rolledBack(record)
    }

    // MARK: - Steps

    private mutating func removeQueueStep<Sink: QueueInstallationEffectSink>(
        _ queue: PlannedSchedulerQueue, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        switch sink.observeQueue(queue) {
        case .queryFailed:
            return enterResidual(.queueStateUnknown, using: &sink)
        case .confirmedAbsent:
            return dropping(.schedulerQueue, using: &sink)
        case let .present(observed):
            // Automatic recovery never removes a *present* queue, whatever it
            // looks like. Creating a queue is create-or-modify, not an
            // exclusive acquisition, so this transaction cannot prove it won
            // the name rather than modifying someone else's queue.
            // `docs/validation/M1-TRANSACTION-RECOVERY.md` reaches the same
            // conclusion for the M1 experiment and retains the artifacts for
            // explicit, record-validated recovery. This does the same.
            guard authority == .recordValidated else {
                return enterResidual(.queueOwnershipAmbiguous, using: &sink)
            }
            // A name is not an identity and a reproducible configuration digest
            // is not either: another administrator recreating the same name with
            // the same target and description would match it. Only the
            // unrepeatable incarnation token this transaction wrote will do.
            guard let observed, let recorded = record.queueIncarnation, observed == recorded else {
                return enterResidual(.queueIncarnationUnverified, using: &sink)
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
            // A pending step whose effect never ran lands here, which is why a
            // pending artifact is probed rather than assumed absent.
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
            // require that it is this record in full — not merely a canonical
            // record reusing the same caller-supplied transaction identifier
            // with a different queue, intent or inventory.
            switch sink.readOwnershipRecord(at: artifact) {
            case .queryFailed:
                return enterResidual(.fileStateUnknown, using: &sink)
            case .confirmedAbsent:
                return enterResidual(.unexpectedArtifactState, using: &sink)
            case let .present(text):
                guard let durable = try? QueueInstallationOwnershipRecord.decode(text),
                      durable == record else {
                    return enterResidual(.unexpectedArtifactState, using: &sink)
                }
            }
        }
        do {
            if artifact.kind == .protectedRoot {
                // The root is a directory, and the only artifact removed with
                // the empty-directory operation. That operation's contract
                // requires failure when the directory is not empty, so an
                // unowned child that appeared underneath stops recovery instead
                // of being swept away with it. This model cannot enforce that
                // contract; a conformer that deletes recursively must not
                // conform. The ordering check above is the part the model can
                // enforce: the root is removed only once nothing else is owned.
                guard record.ownedArtifactsInCreationOrder == [.file(artifact.path)] else {
                    return enterResidual(.unexpectedArtifactState, using: &sink)
                }
                try sink.removeEmptyDirectory(at: artifact.path)
            } else {
                try sink.removeFile(at: artifact.path)
            }
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
        switch writeJournalIfStillOwned(using: &sink) {
        case .written, .notOwned:
            return nil
        case .rejected:
            // The journal is not the one we last wrote, so something replaced it
            // and an unconditional rewrite would have destroyed that evidence.
            return enterResidual(.journalConflict, using: &sink)
        }
    }

    private enum JournalWrite { case written, notOwned, rejected }

    /// Rewrites the journal only while it is still one of this record's
    /// artifacts — once recovery has removed it, writing again would recreate
    /// the very file that was just cleaned up — and only if the durable bytes
    /// are still the ones we last wrote.
    private mutating func writeJournalIfStillOwned<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) -> JournalWrite {
        guard record.owns(.file(journal.path)) else { return .notOwned }
        let text = record.canonicalText
        do {
            try sink.persistOwnershipRecord(text, replacing: lastDurableText, at: journal)
        } catch {
            return .rejected
        }
        lastDurableText = text
        return .written
    }

    private mutating func enterResidual<Sink: QueueInstallationEffectSink>(
        _ reason: QueueInstallationResidualReason, using sink: inout Sink
    ) -> QueueInstallationOutcome {
        record = record.markingResidual()
        // A best effort, and never an unconditional one: the transaction is
        // already in a state a human must inspect, and failing to journal that
        // does not make it less so.
        _ = writeJournalIfStillOwned(using: &sink)
        return .residual(record, reason)
    }
}
