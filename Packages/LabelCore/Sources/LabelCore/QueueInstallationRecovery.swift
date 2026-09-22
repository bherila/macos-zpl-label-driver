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
/// several operations run. That is one open gap with four sites, two of them in
/// this file (`removeFileStep` and `removeQueueStep`); it is described once,
/// under *Unheld claims* at the top of `QueueInstallationTransaction.swift`,
/// and argued nowhere else.
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
    /// A recovery that has none can prove nothing about the journal, and the
    /// compare-and-swap that precedes every destructive effect refuses: a nil
    /// expectation asserts the journal does not exist, while it plainly does.
    ///
    /// **That is the only case the compare-and-swap covers**, and an earlier
    /// version of this comment claimed more. It says nothing whatever when
    /// these bytes are real and durable but were never read together with
    /// `record`: asserting bytes that genuinely are on disk succeeds, and
    /// succeeding replaces them with `record`. The defence against that pairing
    /// is not this field but the initializers below — it is not a pairing a
    /// caller can choose.
    public private(set) var lastDurableText: String?
    private let journal: PlannedFileArtifact

    /// The one private initializer. Everything else routes through it, so there
    /// is exactly one place a record, an authority and a set of journal bytes
    /// can be brought together.
    private init(
        record: QueueInstallationOwnershipRecord,
        authority: QueueInstallationRecoveryAuthority,
        lastDurableText: String?
    ) {
        self.record = record
        self.authority = authority
        self.lastDurableText = lastDurableText
        journal = record.journalArtifact
    }

    /// Resumes over a record this process already holds, with `automatic`
    /// authority and no way to ask for any other.
    ///
    /// It used to be public, to take any authority including `recordValidated`,
    /// and to take any `lastDurableText`. Those three together were a hole, not
    /// a rough edge. A caller could read a journal's *real current bytes*, hand
    /// them in beside a record it constructed — one naming the same journal
    /// path and whatever queue, filter and description it liked — and the first
    /// compare-and-swap would succeed, because the bytes it asserts really are
    /// the durable ones. That write replaces them with the supplied record, and
    /// recovery then proceeds to delete exactly what that record names.
    ///
    /// So `load` is now the only way to a record-validated recovery: it is the
    /// only path that takes the record *out of* the journal bytes it validated
    /// and read through one descriptor, which is what binds the two. What is
    /// left here is the transaction's own rollback, which holds both halves
    /// legitimately because it wrote them, and which `automatic` authority
    /// confines to artifacts it created — never to a queue that is present.
    init(
        resumingOwn record: QueueInstallationOwnershipRecord,
        lastDurableText: String?
    ) {
        self.init(record: record, authority: .automatic, lastDurableText: lastDurableText)
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
            return Self(record: record, authority: authority, lastDurableText: text)
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
                if artifact.kind == .ownershipRecord, stillOwnsProtectedRoot {
                    // Deferred, not skipped: the journal is removed together
                    // with the root, by the step that follows. See
                    // `removeProtectedRootStep`.
                    continue
                }
                if let residual = removeFileStep(artifact, using: &sink) { return residual }
            }
        }
        record = try record.replacingPhase(.rolledBack)
        return .rolledBack(record)
    }

    // MARK: - Steps

    /// **Site 4 of the open gap.** Once the queue is confirmed absent and
    /// dropped from the record, this pass goes on to delete the printer
    /// description, the filter and the journal without ever looking at the
    /// scheduler namespace again. Another administrator who recreates a queue
    /// of that name during that interval is left with a live queue whose
    /// payloads are being removed underneath it.
    ///
    /// Why no condition in this file can express "the queue stayed absent while
    /// I tore its payloads down", why re-observing it before each removal would
    /// only move the window, what would actually close it, and why that is
    /// ADR 0005's decision rather than this file's: see *Unheld claims* at the
    /// top of `QueueInstallationTransaction.swift`, where the whole gap is
    /// described once.
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
            // And the description it was built from is not what it runs. A
            // queue carrying this record's description while configured to run
            // some other executable is not the object this transaction
            // created, and an unreadable binding is unknown.
            guard let expectedFilter = record.queueFilterBinding else {
                return enterResidual(.queueFilterBindingUnverified, using: &sink)
            }
            guard case let .known(filterBinding) = state.invokedFilter,
                  filterBinding == expectedFilter else {
                return enterResidual(.queueFilterBindingUnverified, using: &sink)
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
                    andDescriptionMatches: expectedDescription,
                    andFilterBindingMatches: expectedFilter
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
            case .filterBindingChanged:
                // The token, the target and the description all survived, but
                // the queue was reconfigured to run something else in the
                // window between the check above and this call.
                return enterResidual(.queueFilterBindingUnverified, using: &sink)
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

    /// True while the record still owns the protected root, which is what makes
    /// the journal's own removal something to defer rather than perform.
    private var stillOwnsProtectedRoot: Bool {
        record.owns(.file(record.intent.protectedRoot.path))
    }

    private enum JournalArtifactCheck {
        /// The journal is present and holds exactly this record.
        case matches
        /// The journal is confirmed gone. A pending step whose effect never ran
        /// lands here, which is why a pending artifact is probed rather than
        /// assumed absent.
        case confirmedAbsent
        case residual(QueueInstallationResidualReason)
    }

    /// Reads and validates the journal through **one** call on one descriptor.
    ///
    /// The journal is the one artifact whose bytes no planned digest can pin,
    /// because it is rewritten as the transaction runs. Metadata alone would
    /// let a replaced journal be deleted, so the bytes must be this record in
    /// full — not merely a canonical record reusing the same caller-supplied
    /// transaction identifier with a different queue, intent or inventory.
    private mutating func checkJournalArtifact<Sink: QueueInstallationEffectSink>(
        _ artifact: PlannedFileArtifact, using sink: inout Sink
    ) -> JournalArtifactCheck {
        let limit = QueueInstallationOwnershipRecord.maximumEncodedByteCount
        switch sink.readOwnershipRecord(at: artifact, maximumByteCount: limit) {
        case .queryFailed:
            return .residual(.fileStateUnknown)
        case .confirmedAbsent:
            return .confirmedAbsent
        case .exceededMaximumByteCount:
            return .residual(.fileStateUnknown)
        case let .present(state, text):
            if let failure = artifact.validationFailure(against: .present(state)) {
                return .residual(
                    failure == .observationFailed ? .fileStateUnknown : .unexpectedArtifactState
                )
            }
            guard text.utf8.count <= limit else { return .residual(.fileStateUnknown) }
            guard let durable = try? QueueInstallationOwnershipRecord.decode(text),
                  durable == record else {
                return .residual(.unexpectedArtifactState)
            }
            return .matches
        }
    }

    private mutating func removeFileStep<Sink: QueueInstallationEffectSink>(
        _ artifact: PlannedFileArtifact, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        // The last two artifacts of a complete teardown go together. `rmdir`
        // forces the journal out of the root before the root can go, and the
        // journal is the only thing a restart can load, so performing the two
        // as separate model steps left an interval where the root stood with
        // nothing to resume from — and every later installation refuses an
        // existing root. Both are therefore committed by one operation.
        if artifact.kind == .protectedRoot, stillOwnsProtectedRoot,
           record.owns(.file(journal.path)) {
            return removeProtectedRootWithJournalStep(artifact, using: &sink)
        }
        if artifact.kind == .ownershipRecord {
            // Unreachable by construction, and refused rather than implemented.
            // A record's created list is a prefix of `[root, journal, filter,
            // description, queue]` and this pass drops artifacts in the reverse
            // of that order, so owning the journal means owning the root and
            // the branch above took it. The journal is never removed on its
            // own, because doing so is precisely what left a root nothing could
            // resume from; a record that claims otherwise did not come from
            // this model and is retained for a human.
            return enterResidual(.unexpectedArtifactState, using: &sink)
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
                //
                // The converse does not follow. Passing this check means the
                // path holds what the plan describes, which after a restart is
                // the most that kind, ownership, mode, digest and signature can
                // say; it is not proof that this transaction created it. That
                // is site 2 of the open gap described under *Unheld claims* at
                // the top of `QueueInstallationTransaction.swift`.
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
                // Refused above; this arm exists only because the switch is
                // exhaustive over the kinds.
                return enterResidual(.unexpectedArtifactState, using: &sink)
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

    /// The last step of a complete teardown: the journal and the protected root
    /// that contains it, removed by one operation.
    ///
    /// The ordering this replaces was safe in every respect but one. The
    /// journal went first because `rmdir` refuses a directory that still holds
    /// it, and the root followed as a second step; an interruption between the
    /// two left the root standing with its only evidence already deleted.
    /// `QueueInstallationPreconditions.refusal` then refuses every future
    /// installation with `protectedRootAlreadyPresent`, and `load` has no
    /// journal to resume from, so a perfectly ordinary interrupted uninstall
    /// became a manual job. That interval is not the initial root-before-journal
    /// window `stage` documents: that one is at the other end and has a root
    /// that was never written to.
    ///
    /// What is left is stated on `removeProtectedRootWithJournal` rather than
    /// claimed away: a conformer still cannot unlink and `rmdir` atomically, so
    /// an interruption inside that call leaves the same empty root the
    /// reservation window already allows for. The difference is that this model
    /// no longer has a step boundary there.
    private mutating func removeProtectedRootWithJournalStep<Sink: QueueInstallationEffectSink>(
        _ root: PlannedFileArtifact, using sink: inout Sink
    ) -> QueueInstallationOutcome? {
        // Exactly these two, and in this order. The root is created first, so
        // anything else still owned means a payload or the queue is outstanding
        // and the teardown is not at its last step at all.
        guard record.ownedArtifactsInCreationOrder == [.file(root.path), .file(journal.path)] else {
            return enterResidual(.unexpectedArtifactState, using: &sink)
        }
        switch checkJournalArtifact(journal, using: &sink) {
        case .matches:
            break
        case .confirmedAbsent:
            // The journal is already gone — the residue of an interruption
            // inside a previous combined removal. There is nothing left to
            // commit it with, so it is dropped and the empty root is removed on
            // its own by the ordinary path.
            if let residual = dropping(.file(journal.path), using: &sink) { return residual }
            return removeFileStep(root, using: &sink)
        case let .residual(reason):
            return enterResidual(reason, using: &sink)
        }
        let observation = sink.observeFile(at: root.path)
        if observation.isConfirmedAbsent {
            // A root that is gone while its journal is not is a state this
            // model has no account of, and it is certainly not a clean-up to
            // report as one.
            return enterResidual(.unexpectedArtifactState, using: &sink)
        }
        if let failure = root.validationFailure(against: observation) {
            return enterResidual(
                failure == .observationFailed ? .fileStateUnknown : .unexpectedArtifactState,
                using: &sink
            )
        }
        if let residual = journalStillOurs(using: &sink) { return residual }
        // The compare-and-swap just above re-asserted the bytes, but it does not
        // bind the removal: a planned journal artifact deliberately carries no
        // content digest. So the removal carries the bytes it was authorized
        // against, exactly as the separate journal removal used to.
        guard let expected = lastDurableText else {
            return enterResidual(.journalConflict, using: &sink)
        }
        let removal: FileArtifactRemoval
        do {
            removal = try sink.removeProtectedRootWithJournal(
                root, journal: journal, ifJournalContentsMatch: expected
            )
        } catch {
            return enterResidual(.effectFailed, using: &sink)
        }
        switch removal {
        case .artifactChanged:
            return enterResidual(.unexpectedArtifactState, using: &sink)
        case .unknown:
            return enterResidual(.fileRemovalUnverified, using: &sink)
        case .removed:
            break
        }
        guard sink.observeFile(at: journal.path).isConfirmedAbsent,
              sink.observeFile(at: root.path).isConfirmedAbsent else {
            return enterResidual(.fileRemovalUnverified, using: &sink)
        }
        // The journal is dropped first so that, if anything below fails, the
        // record left in memory names what is really outstanding. Writing it
        // back is already impossible — the journal it would be written to is
        // gone — and `dropping` knows that.
        if let residual = dropping(.file(journal.path), using: &sink) { return residual }
        return dropping(.file(root.path), using: &sink)
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
