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
/// What it cannot do is hold a claim across an interval. Every guard below binds
/// one operation to a state it carries; none of them keeps a state true while
/// several operations run. `removeQueueStep` documents the one place where that
/// distinction currently costs something.
///
/// Every destructive step is guarded twice over. The journal is re-asserted
/// through its compare-and-swap *before* the effect runs, so a journal something
/// else replaced stops recovery while the artifacts it describes are still
/// there; and the effect itself is conditional, carrying the state it expects so
/// that a conformer performs it only while that state still holds. An
/// observation followed by an unconditional delete would leave a window between
/// the two in which the object being deleted is no longer the object that was
/// checked.
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
    ///
    /// A recovery constructed without them can prove nothing about the journal,
    /// and the compare-and-swap that precedes every destructive effect will
    /// therefore refuse. That is deliberate: not knowing what the journal holds
    /// is not permission to delete what it describes.
    public private(set) var lastDurableText: String?
    private let journal: PlannedFileArtifact

    public init(
        resuming record: QueueInstallationOwnershipRecord,
        authority: QueueInstallationRecoveryAuthority,
        lastDurableText: String? = nil
    ) {
        self.record = record
        self.authority = authority
        self.lastDurableText = lastDurableText
        journal = record.journalArtifact
    }

    /// Hydrates recovery state from the journal on the other side of the seam.
    ///
    /// The artifact is **validated by the very call that reads it**: the seam
    /// opens the journal once, stats and reads through that one descriptor, and
    /// hands back both, so kind, ownership, mode, symlink status and effective
    /// access control are checked against the planned journal artifact *for the
    /// file the bytes came out of*. A separate observation followed by a read
    /// would not do: between the two, a symbolic link or a wrong-owner file
    /// holding a copied canonical record can take the path, and those bytes
    /// would hydrate a record-validated recovery — which then deletes what they
    /// name. Validation that the bytes can outrun is validation of nothing.
    ///
    /// The bytes are then read under a byte cap, decoded strictly, and must
    /// describe a record that both lives in the very artifact they were read
    /// from *and* claims that artifact as one it created. A record that plans a
    /// journal it never created has an empty recovery plan, and reporting a
    /// successful rollback while leaving that journal — and the root containing
    /// it — on disk is exactly the false clean-up this refuses.
    public static func load<Sink: QueueInstallationEffectSink>(
        journalAt journal: PlannedFileArtifact,
        authority: QueueInstallationRecoveryAuthority,
        using sink: inout Sink
    ) throws -> Self {
        guard journal.kind == .ownershipRecord else { throw QueueInstallationError.artifactKindMismatch }
        let limit = QueueInstallationOwnershipRecord.maximumEncodedByteCount
        switch sink.readOwnershipRecord(at: journal, maximumByteCount: limit) {
        case .queryFailed:
            // Unreadable is not absent and is certainly not "nothing to do".
            throw QueueInstallationError.effectFailed
        case .confirmedAbsent:
            throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .absent)
        case .exceededMaximumByteCount:
            throw QueueInstallationError.ownershipRecordTooLarge
        case let .present(state, text):
            // The state and the bytes came through one descriptor, so refusing
            // here refuses the file that was actually read.
            if let failure = journal.validationFailure(against: .present(state)) {
                throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, failure)
            }
            guard text.utf8.count <= limit else { throw QueueInstallationError.ownershipRecordTooLarge }
            let record = try QueueInstallationOwnershipRecord.decode(text)
            guard record.journalArtifact == journal else { throw QueueInstallationError.recordHasNoJournal }
            guard record.owns(.file(journal.path)) else {
                throw QueueInstallationError.journalNotOwnedByRecord
            }
            return Self(resuming: record, authority: authority, lastDurableText: text)
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

    /// **Known gap, deliberately not closed here.** Once the queue is confirmed
    /// absent and dropped from the record, this pass goes on to delete the
    /// printer description, the filter and the journal without ever looking at
    /// the scheduler namespace again. Another administrator who recreates a
    /// queue of that name during that interval is left with a live queue whose
    /// payloads are being removed underneath it.
    ///
    /// Every condition in this file binds one *operation* to a state: the
    /// journal's compare-and-swap, the incarnation, destination and description
    /// carried into `removeQueue`, the artifact carried into each removal. None
    /// of them can express "the queue stayed absent while I tore its payloads
    /// down", because that claim has to hold across several operations and no
    /// single conditional primitive spans them. Re-observing the queue before
    /// each payload removal would narrow the window and close nothing, and
    /// reporting that as a fix is worse than the gap.
    ///
    /// Closing it honestly needs a *held* claim over the queue name and the
    /// protected root, spanning the pass — a coordination domain the seam offers
    /// and this model requires — which `AGENTS.md` also asks for in the other
    /// direction: "All product queues and maintenance actions share one physical
    /// device coordination domain", and "A Swift actor is not a cross-process
    /// device lock". Which mechanism can provide one is a property of the
    /// installation mechanism, and ADR 0005 is still *proposed* and has not
    /// chosen one. It is therefore a decision for that ADR and for the
    /// maintainer, not something to invent inside a review round.
    private mutating func removeQueueStep<Sink: QueueInstallationEffectSink>(
        _ queue: PlannedSchedulerQueue, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        switch sink.observeQueue(queue) {
        case .queryFailed:
            return enterResidual(.queueStateUnknown, using: &sink)
        case .confirmedAbsent:
            return dropping(.schedulerQueue, using: &sink)
        case let .present(state):
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
            // The recorded token is the confirmed one when the transaction got
            // that far, and the *intended* one when it died between writing the
            // queue and confirming it. Both identify the same object; neither
            // says the name was acquired, which is what the authority check
            // above is for.
            guard let observed = state.incarnation,
                  let recorded = record.identifyingQueueIncarnation,
                  observed == recorded else {
                return enterResidual(.queueIncarnationUnverified, using: &sink)
            }
            // The queue also has to still deliver where the record says it was
            // pointed. A destination that changed means something modified this
            // queue, and an unreadable one is unknown; neither is ours to delete
            // on the strength of the token alone.
            guard case let .known(destination) = state.destination,
                  destination == record.destination else {
                return enterResidual(.queueDestinationUnverified, using: &sink)
            }
            // And it has to still be built from the description the record
            // names. A queue rebuilt from a different one runs something else,
            // whatever its token says.
            guard let expectedDescription = record.queueDescriptionIdentity else {
                return enterResidual(.queueDescriptionUnverified, using: &sink)
            }
            guard case let .known(description) = state.printerDescription,
                  description == expectedDescription else {
                return enterResidual(.queueDescriptionUnverified, using: &sink)
            }
            if let residual = journalStillOurs(using: &sink) { return residual }
            // The observation above and the deletion below are two moments. If
            // the checked queue were deleted and the name recreated in between,
            // an unconditional removal by name would land on the replacement. So
            // the deletion carries the incarnation it expects and a conformer
            // performs it only while that incarnation still holds; when it no
            // longer does, nothing is deleted and this stops.
            let removal: SchedulerQueueRemoval
            do {
                removal = try sink.removeQueue(
                    queue,
                    ifIncarnationMatches: recorded,
                    andDestinationMatches: record.destination,
                    andDescriptionMatches: expectedDescription
                )
            } catch {
                return enterResidual(.effectFailed, using: &sink)
            }
            switch removal {
            case .incarnationChanged:
                return enterResidual(.queueIncarnationUnverified, using: &sink)
            case .destinationChanged:
                // The token survived but the queue was re-pointed in the window
                // between the check above and this call, so it is somebody's
                // modified queue and not the one that was authorized.
                return enterResidual(.queueDestinationUnverified, using: &sink)
            case .descriptionChanged:
                return enterResidual(.queueDescriptionUnverified, using: &sink)
            case .unknown:
                // Ambiguous, so it is never replayed: a second attempt could
                // delete a queue that appeared in the meantime.
                return enterResidual(.queueRemovalUnverified, using: &sink)
            case .removed:
                break
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
        if artifact.kind == .ownershipRecord {
            // The journal is the one artifact whose bytes no planned digest can
            // pin, because it is rewritten as the transaction runs. Metadata
            // alone would let a replaced journal be deleted, so it is validated
            // and read by one call through one descriptor, and must be this
            // record in full — not merely a canonical record reusing the same
            // caller-supplied transaction identifier with a different queue,
            // intent or inventory.
            let limit = QueueInstallationOwnershipRecord.maximumEncodedByteCount
            switch sink.readOwnershipRecord(at: artifact, maximumByteCount: limit) {
            case .queryFailed:
                return enterResidual(.fileStateUnknown, using: &sink)
            case .confirmedAbsent:
                // A pending step whose effect never ran lands here, which is why
                // a pending artifact is probed rather than assumed absent.
                return dropping(.file(artifact.path), using: &sink)
            case .exceededMaximumByteCount:
                return enterResidual(.fileStateUnknown, using: &sink)
            case let .present(state, text):
                if let failure = artifact.validationFailure(against: .present(state)) {
                    return enterResidual(
                        failure == .observationFailed ? .fileStateUnknown : .unexpectedArtifactState,
                        using: &sink
                    )
                }
                guard text.utf8.count <= limit else { return enterResidual(.fileStateUnknown, using: &sink) }
                guard let durable = try? QueueInstallationOwnershipRecord.decode(text),
                      durable == record else {
                    return enterResidual(.unexpectedArtifactState, using: &sink)
                }
            }
        } else {
            let observation = sink.observeFile(at: artifact.path)
            if observation.isConfirmedAbsent {
                // A pending step whose effect never ran lands here, which is why
                // a pending artifact is probed rather than assumed absent.
                return dropping(.file(artifact.path), using: &sink)
            }
            if let failure = artifact.validationFailure(against: observation) {
                // Something other than what this transaction created now
                // occupies the path, or the query failed. Either way it is
                // retained for a human, not deleted on a guess.
                return enterResidual(
                    failure == .observationFailed ? .fileStateUnknown : .unexpectedArtifactState,
                    using: &sink
                )
            }
        }
        if artifact.kind == .protectedRoot {
            // The root is a directory, and the only artifact removed with
            // the empty-directory operation. That operation's contract
            // requires failure when the directory is not empty, so an
            // unowned child that appeared underneath stops recovery instead
            // of being swept away with it. This model cannot enforce that
            // contract; a conformer that deletes recursively must not
            // conform. The ordering check here is the part the model can
            // enforce: the root is removed only once nothing else is owned.
            guard record.ownedArtifactsInCreationOrder == [.file(artifact.path)] else {
                return enterResidual(.unexpectedArtifactState, using: &sink)
            }
        }
        if let residual = journalStillOurs(using: &sink) { return residual }
        let removal: FileArtifactRemoval
        do {
            switch artifact.kind {
            case .protectedRoot:
                removal = try sink.removeEmptyDirectory(artifact)
            case .ownershipRecord:
                // The read above proved the bytes, and the compare-and-swap
                // just above re-asserted them, but neither binds the deletion:
                // a planned journal artifact deliberately carries no content
                // digest, so a conformer honouring every field in `removeFile`
                // would still delete a journal replaced in between. The
                // deletion therefore carries the bytes it was authorized
                // against — the ones this recovery last wrote durably, which is
                // what the compare-and-swap asserted a moment ago.
                guard let expected = lastDurableText else {
                    return enterResidual(.journalConflict, using: &sink)
                }
                removal = try sink.removeOwnershipRecord(artifact, ifContentsMatch: expected)
            case .filterExecutable, .printerDescription:
                removal = try sink.removeFile(artifact)
            }
        } catch {
            return enterResidual(.effectFailed, using: &sink)
        }
        switch removal {
        case .artifactChanged:
            // The path stopped holding what was validated a moment ago, so the
            // conditional removal declined rather than deleting whatever is
            // there now.
            return enterResidual(.unexpectedArtifactState, using: &sink)
        case .unknown:
            return enterResidual(.fileRemovalUnverified, using: &sink)
        case .removed:
            break
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
        case .notDurable:
            return enterResidual(.journalNotDurable, using: &sink)
        }
    }

    private enum JournalWrite { case written, notOwned, rejected, notDurable }

    /// Re-asserts, **before** a destructive effect, that the journal still holds
    /// exactly the bytes this recovery last saw, using the same compare-and-swap
    /// every journal write uses.
    ///
    /// Without this the first removal of a pass runs against a journal nothing
    /// has re-checked: if another transaction had already replaced the durable
    /// record — recreating the root and writing its own inventory — the conflict
    /// would only be noticed by the write that *follows* the removal, by which
    /// time that transaction's queue or file is gone. The model cannot hold a
    /// cross-process lock, so it uses the one conditional primitive it has, in
    /// the one order that is safe: check first, destroy second.
    ///
    /// Once recovery has removed the journal itself there is nothing left to
    /// compare against, and the remaining step — the empty protected root — is
    /// guarded instead by the requirement that nothing else is still owned and
    /// by the removal's own `rmdir` semantics.
    private mutating func journalStillOurs<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        switch writeJournalIfStillOwned(using: &sink) {
        case .written, .notOwned:
            return nil
        case .rejected:
            return enterResidual(.journalConflict, using: &sink)
        case .notDurable:
            return enterResidual(.journalNotDurable, using: &sink)
        }
    }

    /// Rewrites the journal only while it is still one of this record's
    /// artifacts — once recovery has removed it, writing again would recreate
    /// the very file that was just cleaned up — and only if the durable bytes
    /// are still the ones we last wrote.
    private mutating func writeJournalIfStillOwned<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) -> JournalWrite {
        guard record.owns(.file(journal.path)) else { return .notOwned }
        let text = record.canonicalText
        let durability: JournalDurability
        do {
            durability = try sink.persistOwnershipRecord(text, replacing: lastDurableText, at: journal)
        } catch {
            return .rejected
        }
        // A write the conformer cannot say reached stable storage leaves the
        // durable bytes unknown, so `lastDurableText` is not advanced to them.
        guard durability == .synchronizedToStorage else { return .notDurable }
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
