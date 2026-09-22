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
///   name is recorded. Journal writes are conditional on the bytes last written
///   and must be proved durable before the step they precede may run.
/// - The queue's destination is a closed typed value carried by the intent and
///   the durable record, passed to the create operation and required to read
///   back exactly; so is the identity of the printer description it is built
///   from. What a queue delivers to and what it runs are therefore properties
///   of the plan, not of whatever ambient state a conformer consulted.
/// - Where staging may happen is a policy the caller declares and this model
///   checks, and the system-critical trees are refused whatever that policy
///   says. Naming the real location stays ADR 0005's decision.
/// - Recovery is queue-first, finite, idempotent and ownership-conservative, and
///   it can be loaded back from the journal alone — see
///   `QueueInstallationRecovery`. Its destructive effects are conditional on the
///   state they were authorized against, not on a separate earlier observation.
/// - Acquiring a queue *name* is not something a create-or-modify operation can
///   prove. A transaction whose seam cannot prove exclusive creation is not
///   completed; it is residual with the ambiguity named.
/// - An unverified or unobserved outcome is its own case. Unknown is never
///   false, zero, supported or completed.
///
/// # Unheld claims: one open gap, four places it shows
///
/// **This is the single description of that gap.** Four sites in this model
/// point here rather than arguing it again; nothing pins it, because a test
/// that fixed it in place would be worse than saying it plainly.
///
/// Every primitive this model has binds **one operation** to a state that
/// operation carries: the journal's compare-and-swap, the parent identity
/// carried into the root reservation, the incarnation, destination, description
/// and filter binding carried into queue creation and removal, the artifact
/// carried into each file removal. Not one of them can keep a state true *while
/// several operations run*. So wherever the model needs "this stayed mine for
/// the length of the pass", it has nothing to say it with, and the four sites
/// below are the same missing thing seen from four angles:
///
/// 1. **Staging is not a reservation that lasts.** `createProtectedRoot` binds
///    the reservation to the directory object preconditions validated, and that
///    binding ends when it returns. `persistOwnershipRecord` and `createFile`
///    then receive absolute paths and nothing else, so nothing carries "still
///    inside the root I reserved" into the calls that fill it.
/// 2. **Record-validated removal cannot prove authorship.** After a restart,
///    all a recovery can compare is kind, ownership, mode, digest and
///    signature. Those say the object matches the plan. They do not say *this
///    transaction created it*, and for a path a foreign file can occupy, the
///    plan is exactly what that file would match.
/// 3. **Completion observes before it is durable.** `complete` re-observes the
///    queue and re-validates every staged artifact, and only then writes the
///    journal entry that makes `.completed` durable. The observation is true
///    when it is made and is not held until the write lands.
/// 4. **Teardown walks away from the namespace.** Once the queue is confirmed
///    absent and dropped, the pass removes the description, the filter and the
///    journal without looking at the scheduler namespace again. An
///    administrator who recreates that name in the interval is left with a live
///    queue whose payloads are being removed underneath it.
///
/// **Another sequential re-observation is not a fix.** Re-checking the queue
/// before each payload removal, or re-observing the root before each child
/// effect, narrows the window and closes nothing: the second observation has
/// exactly the same lifetime as the first, so the interval simply moves. Doing
/// it and calling the gap closed would be worse than the gap, because it would
/// read as covered.
///
/// **What would actually close it** is a *held* claim over the queue name and
/// the protected root, spanning the pass — acquired before the first effect,
/// released after the last, and enforced against other processes rather than
/// within this one. `AGENTS.md` asks for the same thing from the other
/// direction: "All product queues and maintenance actions share one physical
/// device coordination domain", and "A Swift actor is not a cross-process
/// device lock".
///
/// **Whether such a claim can exist is a property of the installation
/// mechanism**, not of this model: a guided installer package, a privileged
/// helper and a one-shot privileged tool do not offer the same primitives, and
/// nothing portable can conjure one. ADR 0005 is still *proposed* and has
/// chosen no mechanism. This is therefore a decision for that ADR and for the
/// maintainer, and it is recorded as an open gap rather than papered over
/// inside a review round.

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
    /// neither group- nor world-writable, or its effective access control grants
    /// write access to some principal other than its owner.
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
    /// A queue of the right name and incarnation is present, but it does not
    /// deliver where this transaction asked it to. Something modified it, so it
    /// is retained for a human rather than removed or called complete.
    case queueDestinationUnverified
    /// A queue of the right name and incarnation is present, but it is not
    /// built from the printer description this transaction asked for — or the
    /// seam could not read which one it is built from. Either way it is not the
    /// queue that was planned, and it is retained rather than removed.
    case queueDescriptionUnverified
    /// A queue of the right name, incarnation and description is present, but
    /// it is not configured to run the executable this transaction's
    /// description declares — or the seam could not read which one it runs.
    /// Which description a queue was built from does not settle what it runs,
    /// so this is its own answer and its own refusal.
    case queueFilterBindingUnverified
    /// The queue is present and this transaction cannot prove it acquired the
    /// name rather than modifying a queue that appeared first. Automatic
    /// recovery never removes a present queue for this reason.
    case queueOwnershipAmbiguous
    /// The journal no longer holds the bytes this transaction last wrote, so the
    /// write was refused rather than destroying whatever replaced them.
    case journalConflict
    /// The seam accepted a journal write without proving it reached stable
    /// storage. The step it was supposed to precede therefore did not run.
    case journalNotDurable
    /// A staged artifact no longer matches the plan at the final boundary, so
    /// the transaction is not complete even though its queue is present.
    case stagedArtifactChangedBeforeCompletion
    case fileStateUnknown
    case fileRemovalUnverified
    case unexpectedArtifactState
    case effectFailed
    case recoveryPlanUnavailable
    /// The protected root's reservation reported an outcome that does not
    /// settle whether a root was created, or which directory it was created
    /// under, and no journal exists yet to record either. Nothing is removed,
    /// and no rollback afterwards is reported as clean: the case is for the
    /// manual check in `docs/validation/M1-TRANSACTION-RECOVERY.md`.
    case protectedRootReservationUnverified
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
/// **Several of these carry requirements this model cannot enforce by itself.**
/// They are stated here because stating them is the model's job; meeting them is
/// the conformer's, and an implementation that cannot meet one must not conform.
/// Where a requirement can be turned into a value the model checks, it has been:
/// a contract nothing can observe is a contract nothing keeps.
///
/// - `createProtectedRoot` must fail if anything already exists at the path —
///   `mkdir` semantics, not create-or-replace. It is the reservation the
///   transaction cannot journal in advance, because the journal has nowhere to
///   live until the root exists. It is also **conditional on the parent**: it
///   creates the root inside the directory object `identity` names and nowhere
///   else, and it must decline with `parentIdentityChanged` rather than create
///   anything when that object is no longer at `parent`. A conformer does this
///   by holding the validated parent open and creating relative to that
///   descriptor — `mkdirat` on a descriptor, not `mkdir` on a reassembled
///   string — and reports back the identity of the descriptor it used, so the
///   model can check the answer instead of assuming the argument was honoured.
///   Without that binding the preconditions prove something about one directory
///   and the reservation happens in whatever directory the path resolves to at
///   the later moment, which is exactly how a root lands somewhere `AGENTS.md`
///   forbids writing to.
/// - `createFile` is **create-if-absent** and must open without following
///   symbolic links: a path that is already occupied refuses the step and
///   nothing at that path is written, truncated, replaced or followed. It is
///   not a lesser operation than the root's reservation. If it were allowed to
///   replace, a conformer could overwrite a file already sitting at the filter
///   or description path, and the validation that runs afterwards would see
///   exactly the bytes the plan asked for and be unable to tell that anything
///   had been there. The refusal is a returned `FileArtifactCreation` rather
///   than a throw, so the model handles it as a value; `alreadyPresent`
///   guarantees no modification, and `unknown` guarantees nothing at all.
/// - `persistOwnershipRecord` must replace the journal's bytes in one step, and
///   only if its current contents are exactly `previous` **compared as bytes**
///   (`nil` meaning it must not exist at all). Without that condition an
///   unconditional rewrite would destroy a journal something else had replaced.
///   It must additionally flush the new contents *and* the containing
///   directory entry to stable storage before returning, and say so by
///   returning `JournalDurability.synchronizedToStorage`. An ordinary temp-file
///   rename meets the atomicity requirement while still letting a power loss
///   restore the older journal — which would lose the recorded name of an
///   artifact that by then exists — so the model refuses to run the step a
///   non-durable write was supposed to precede. Note honestly that advisory
///   locking cannot bind a writer that declines to cooperate.
/// - `readOwnershipRecord` must read at most `maximumByteCount` bytes and must
///   report `exceededMaximumByteCount` rather than materializing more, so a
///   corrupt or redirected journal cannot cause an unbounded read and
///   allocation inside a privileged process before the decoder's own cap is
///   reached. It **opens the artifact once**, without following symbolic links,
///   and both stats and reads *through that one descriptor*, returning the
///   state it stat'd alongside the bytes it read. Validating the journal and
///   reading it are therefore one operation and not two: a separate
///   `observeFile` followed by a read leaves a window in which the file that
///   passed validation is replaced before the bytes are taken, and those bytes
///   go on to authorize a record-validated recovery that deletes things. The
///   model validates the returned state against the planned artifact before it
///   looks at the bytes, so a conformer that returns a state belonging to some
///   other file — or no real state at all — is caught here rather than trusted.
/// - `removeEmptyDirectory` must fail when the directory is not empty —
///   `rmdir` semantics. A recursive delete would sweep away an unowned child
///   that appeared beneath the protected root.
/// - `createQueue` must write `incarnation` into the queue's own configuration
///   so a later read can return it, must point the queue at exactly
///   `destination` and nowhere else — it takes the destination as an argument
///   precisely so that it cannot be sourced from ambient state — must build the
///   queue from exactly the description in `describedBy`, and must report
///   `exclusiveCreation` only if it can prove it created the name rather than
///   modifying a queue that appeared first. An `lpadmin`-style create-or-modify
///   operation cannot prove that and must report `ambiguousCreateOrModify`.
/// - `observeQueue` must report the destination **and the printer description**
///   it could read back out of a present queue's configuration, and the
///   matching `unknown` case when it could not. The model requires an exact
///   match on both before a queue counts as created or complete. The
///   description is read back for the same reason the destination is: it is an
///   argument to the create operation, and an argument nothing reads back is an
///   argument a conformer can ignore or misapply — leaving a queue that carries
///   this transaction's token, delivers where the plan said, and runs a filter
///   nobody planned.
/// - The removals are **conditional**, not "observe, then delete". Each carries
///   the state it expects and must be performed only while that state still
///   holds, as one operation: `removeQueue` deletes only a queue still carrying
///   `incarnation` *and* still delivering to `destination` *and* still built
///   from `description` *and* still running `filter` — all four, because an
///   administrator who re-points a queue, rebuilds it or reconfigures what it
///   runs without disturbing its token has a queue this transaction may not
///   delete; `removeProtectedRootWithJournal` removes the journal and the root
///   together, and only while the journal's bytes are still exactly the ones it
///   was authorized against — the one condition a planned digest cannot express
///   for a file the transaction rewrites as it runs; and
///   `removeFile`/`removeEmptyDirectory` delete only a
///   path still holding exactly the artifact described, opened without
///   following symbolic links. Re-checking and then deleting unconditionally
///   leaves a window in which another administrator recreates the name, and the
///   deletion lands on their object instead.
/// - `observeFile` must report whether an executable artifact carries a valid
///   code signature over the bytes it holds, in `ObservedCodeSignature`. The
///   planned digest already fixes those bytes, so this is not a substitution
///   window; it is the difference between bytes that are the planned ones and
///   bytes that are the planned ones *and* signed, which is what `AGENTS.md`'s
///   local ad-hoc signing default requires of anything installed as a filter.
/// - `observeFile` must report effective access control, including inherited
///   entries, in `ObservedAccessControl`. POSIX mode bits alone do not say
///   whether another principal can write.
public protocol QueueInstallationEffectSink {
    mutating func observeQueue(_ queue: PlannedSchedulerQueue) -> SchedulerQueueObservation
    mutating func observeFile(at path: AbsolutePath) -> FileArtifactObservation
    mutating func createProtectedRoot(
        _ artifact: PlannedFileArtifact,
        inside parent: AbsolutePath,
        ifParentIdentityMatches identity: DirectoryIdentity
    ) throws -> ProtectedRootReservation
    mutating func createFile(_ artifact: PlannedFileArtifact) throws -> FileArtifactCreation
    mutating func persistOwnershipRecord(
        _ text: String, replacing previous: String?, at artifact: PlannedFileArtifact
    ) throws -> JournalDurability
    mutating func readOwnershipRecord(
        at artifact: PlannedFileArtifact, maximumByteCount: Int
    ) -> OwnershipRecordObservation
    mutating func createQueue(
        _ queue: PlannedSchedulerQueue,
        describedBy description: PlannedFileArtifact,
        deliveringTo destination: QueueDestination,
        incarnation: SchedulerQueueIncarnation
    ) throws -> SchedulerQueueAcquisition
    mutating func removeQueue(
        _ queue: PlannedSchedulerQueue,
        ifIncarnationMatches incarnation: SchedulerQueueIncarnation,
        andDestinationMatches destination: QueueDestination,
        andDescriptionMatches description: SchedulerQueueDescriptionIdentity,
        andFilterBindingMatches filter: PrinterDescriptionFilterBinding
    ) throws -> SchedulerQueueRemoval
    mutating func removeFile(_ artifact: PlannedFileArtifact) throws -> FileArtifactRemoval
    mutating func removeEmptyDirectory(_ artifact: PlannedFileArtifact) throws -> FileArtifactRemoval
    /// Removes the journal **and** the protected root that contains it, as one
    /// operation, and only while the journal still holds exactly `contents`.
    ///
    /// This exists because the two cannot be ordered safely as separate model
    /// steps. The journal lives one component inside the root, so `rmdir`
    /// forces the journal to go first; but the journal is the only thing a
    /// restart can load, so a model that removed it and then took a second step
    /// to remove the root left an interval in which the root still stood and
    /// nothing could resume. Every later installation refuses that root
    /// (`protectedRootAlreadyPresent`), so an interrupted uninstall — an
    /// ordinary event, not a hostile one — needed a human.
    ///
    /// The conformer's contract is `rmdir` semantics extended by exactly one
    /// permitted child: refuse unless the root's only entry is `journal` and
    /// `journal` holds `contents` byte for byte, then unlink it and remove the
    /// root. A conformer that removes anything else, or that removes
    /// recursively, must not conform.
    ///
    /// **The remaining window, stated rather than claimed away.** No filesystem
    /// offers unlink-and-rmdir as one atomic act, so an interruption *inside*
    /// this call can still leave the root present and empty with no journal.
    /// What that leaves is an empty, fixed-name, root-owned directory and
    /// nothing else — byte for byte the residue the root reservation window at
    /// the other end of `stage` already allows for, and covered by the same
    /// manual check in `docs/validation/M1-TRANSACTION-RECOVERY.md`. What is
    /// gone is the model-level window: there is no longer a point at which this
    /// model has committed to destroying its own evidence and still needs it,
    /// and no interval between two model steps for a restart to land in.
    /// Removing the residue entirely needs a claim held across the pass, which
    /// is the gap `removeQueueStep` documents.
    mutating func removeProtectedRootWithJournal(
        _ root: PlannedFileArtifact,
        journal: PlannedFileArtifact,
        ifJournalContentsMatch contents: String
    ) throws -> FileArtifactRemoval
}

// MARK: - Intent

/// What a transaction would create, before anything has been observed. Every
/// artifact declares its absolute path, ownership and mode; every file lives
/// exactly one component below the protected root, so recovery stays finite and
/// never becomes a recursive delete.
public struct QueueInstallationIntent: Equatable, Sendable {
    public let queue: PlannedSchedulerQueue
    /// Where the queue would deliver. Declared here, carried into the durable
    /// record, passed to the create operation as an argument and required to
    /// read back exactly, so that the same authorized plan cannot produce a
    /// queue aimed at an inert sink on one run and at a physical printer on the
    /// next because the conformer consulted ambient state.
    public let destination: QueueDestination
    public let protectedRoot: PlannedFileArtifact
    public let ownershipRecord: PlannedFileArtifact
    public let filter: PlannedFileArtifact
    public let printerDescription: PlannedFileArtifact
    /// The fixed directory the protected root is created inside.
    public let stagingParent: AbsolutePath
    /// Where staging is permitted to happen at all, as the caller declared it.
    ///
    /// **Which directory an installation really stages in is ADR 0005's
    /// decision, and ADR 0005 is still *proposed*.** Nothing here names one, and
    /// there is no default: the caller declares the allowlist and this
    /// initializer checks the plan against it. All this changes is that the
    /// location is a stated, checked policy rather than "any absolute path that
    /// has a parent", which is what this type used to accept — a plan rooted
    /// under `/System` was constructible, and `AGENTS.md` forbids writing
    /// there. `QueueInstallationStagingPolicy` refuses the system-critical
    /// trees outright, so no allowlist can re-admit one.
    public let stagingPolicy: QueueInstallationStagingPolicy

    /// - Parameter descriptionInvokesFilter: which executable the supplied
    ///   printer description declares it runs, stated by whoever produced that
    ///   description. It is a proof obligation rather than a stored field: the
    ///   initializer refuses unless it is exactly the filter this intent plans,
    ///   after which it is `filter` and there is nothing left to keep. See
    ///   `PrinterDescriptionFilterBinding`.
    public init(
        queue: PlannedSchedulerQueue,
        destination: QueueDestination,
        protectedRoot: PlannedFileArtifact,
        ownershipRecord: PlannedFileArtifact,
        filter: PlannedFileArtifact,
        printerDescription: PlannedFileArtifact,
        descriptionInvokesFilter: PrinterDescriptionFilterBinding,
        stagingPolicy: QueueInstallationStagingPolicy
    ) throws {
        guard protectedRoot.kind == .protectedRoot,
              ownershipRecord.kind == .ownershipRecord,
              filter.kind == .filterExecutable,
              printerDescription.kind == .printerDescription else {
            throw QueueInstallationError.artifactKindMismatch
        }
        // The description and the filter are not two independent artifacts that
        // happen to be staged together: one names the other, and until this
        // check existed nothing in the model or anywhere else asked which
        // executable the description named. A description with a correct digest
        // and a filter entry pointing at something else staged cleanly, read
        // back cleanly and completed, while the planned signed filter was never
        // run. The model cannot read the description's bytes to find out — and
        // must not — so the declaration is typed and checked here, before a
        // plan, a staging step or a queue can exist.
        guard descriptionInvokesFilter == (try PrinterDescriptionFilterBinding(invoking: filter)) else {
            throw QueueInstallationError.descriptionFilterBindingMismatch
        }
        guard let parent = protectedRoot.path.parent else { throw QueueInstallationError.invalidPath }
        // Exactly one of the declared locations, not "somewhere beneath one":
        // a region is not a staging location. The policy has already refused
        // every system-critical tree, so nothing admitted here can be one.
        guard stagingPolicy.admits(parent) else {
            throw QueueInstallationError.stagingLocationNotPermitted
        }
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
        self.destination = destination
        self.protectedRoot = protectedRoot
        self.ownershipRecord = ownershipRecord
        self.filter = filter
        self.printerDescription = printerDescription
        self.stagingPolicy = stagingPolicy
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
            // Mode bits are not the whole access story. An ACL can grant another
            // principal `add_file` or `delete_child` here while `stat` still
            // reports root:wheel 0755, which would let that principal race the
            // root reservation or replace the transaction directory; an
            // inheritable entry would carry the same grant onto the root this
            // transaction is about to create inside it. Not having looked is
            // unknown, and unknown is not "no grants".
            switch state.accessControl {
            case .noWriteGrantsBeyondOwner: break
            case .grantsWriteToOtherPrincipals: return .stagingParentUnsuitable
            case .unknown: return .stagingParentStateUnknown
            }
            // Everything above describes *a* directory sitting at that path. It
            // does not say which object that directory is, and the reservation
            // that follows has to happen inside the very object these checks
            // passed — not inside whatever the path resolves to a moment later.
            // An observation that did not identify the directory has not
            // identified it, and unknown is not a match.
            //
            // This check is last so that a parent which is unsuitable or
            // unreadable still refuses for the reason it really has.
            guard case .known = state.directoryIdentity else { return .stagingParentStateUnknown }
            return nil
        }
    }

    /// The identity of the directory object the staging parent was observed to
    /// be. Non-nil exactly when `refusal` is nil, because an unidentified parent
    /// is itself a refusal — so a plan always carries one, and staging can
    /// require the reservation to be made inside it.
    public var stagingParentIdentity: DirectoryIdentity? {
        guard case let .present(state) = stagingParent,
              case let .known(identity) = state.directoryIdentity else { return nil }
        return identity
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
    ///
    /// These are a fact about *storage*, and `record` is a fact about what this
    /// invocation may own. The two usually agree, but not always, and the gap
    /// only ever runs one way: `record` may name less than these bytes when
    /// the seam has proved a step had no effect and the retraction could not
    /// yet be made durable. The next conditional write reconciles them, and
    /// refuses if storage moved in between.
    public private(set) var lastDurableText: String?
    /// Set when the root reservation may have acted without this transaction
    /// being able to record what it did. Both rollback entry points honour it
    /// before building an executor, because an empty inventory derives an
    /// empty recovery plan and an empty plan would otherwise run to
    /// `rolledBack`.
    private var rootReservationUnresolved = false

    public init(plan: QueueInstallationPlan) throws {
        self.plan = plan
        phase = .planned
        record = try QueueInstallationOwnershipRecord(
            transactionID: plan.transactionID,
            intent: plan.intent,
            phase: .inProgress,
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
        let durability: JournalDurability
        do {
            durability = try sink.persistOwnershipRecord(
                text, replacing: creating ? nil : lastDurableText, at: plan.intent.ownershipRecord
            )
        } catch {
            throw QueueInstallationError.effectFailed
        }
        // A write that has not reached stable storage is not a write the next
        // step may rely on: a power loss could restore the previous journal and
        // lose the name of an artifact the step is about to create. It is also
        // not a write we can claim as ours afterwards, so `lastDurableText` is
        // left alone and the durable state stays honestly unknown.
        guard durability == .synchronizedToStorage else {
            throw QueueInstallationError.journalWriteNotDurable
        }
        lastDurableText = text
    }

    /// Withdraws the pending mark for a creation the seam has guaranteed had no
    /// effect, and journals the withdrawal.
    ///
    /// Three facts are kept apart here: what might exist at the path, what the
    /// journal last durably recorded, and what this invocation is entitled to
    /// delete. The seam's guarantee settles the third — this invocation created
    /// nothing there — and a failed journal write does not unsettle it. So the
    /// retraction stays in `record` even when the write fails, and the failure
    /// is what is reported, because it is what actually happened.
    ///
    /// An earlier version restored the pending mark on that failure, so that
    /// memory matched what storage might hold. That gave the knowledge back
    /// away: once the transient failure cleared, an automatic rollback probed
    /// the pending path, found a file of the planned shape — which a foreign
    /// file at a planned path is by construction — and deleted it.
    ///
    /// Leaving `lastDurableText` at the bytes that still name the step is not a
    /// claim that the retraction landed. It is what makes the next write
    /// conditional on storage still holding the pending mark: recovery's
    /// compare-and-swap before its first destructive effect writes the
    /// retraction over exactly those bytes, and refuses with a journal
    /// conflict if a non-durable write left something else there. After a
    /// restart the durable journal may still name the step, and a recovery
    /// loaded from it has only the plan to compare against; that is site 2 of
    /// the open gap under *Unheld claims*, and this does not close it.
    private mutating func retractPendingCreation<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws {
        record = record.retractingPendingArtifact()
        try writeJournal(using: &sink)
    }

    /// Records that the root reservation may have acted without leaving
    /// anything this transaction can name. See `rootReservationUnresolved`.
    private mutating func enterUnresolvedRootReservation() {
        rootReservationUnresolved = true
        record = record.markingResidual()
        phase = .residual(.protectedRootReservationUnverified)
    }

    /// Re-observes every staged artifact and the journal, and requires each to
    /// still match the plan exactly.
    private mutating func revalidateStagedArtifacts<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws {
        for artifact in plan.intent.creationOrderedFiles where artifact.kind != .ownershipRecord {
            let observation = sink.observeFile(at: artifact.path)
            if let failure = artifact.validationFailure(against: observation) {
                throw QueueInstallationError.stagedArtifactInvalid(artifact.kind, failure)
            }
        }
        // The journal is validated by the same call that reads it, through the
        // same descriptor, so the bytes compared below are the bytes of the
        // file that passed validation.
        let limit = QueueInstallationOwnershipRecord.maximumEncodedByteCount
        let journal = plan.intent.ownershipRecord
        switch sink.readOwnershipRecord(at: journal, maximumByteCount: limit) {
        case .queryFailed:
            throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .observationFailed)
        case .confirmedAbsent:
            throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .absent)
        case .exceededMaximumByteCount:
            throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .exceededSizeLimit)
        case let .present(state, text):
            if let failure = journal.validationFailure(against: .present(state)) {
                throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, failure)
            }
            // A conformer that returned more than the cap it was given has not
            // honoured the bounded read, and its contents are refused rather
            // than decoded: believing them here is what would make the cap
            // decorative.
            guard text.utf8.count <= limit else {
                throw QueueInstallationError.stagedArtifactInvalid(.ownershipRecord, .exceededSizeLimit)
            }
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
    ///
    /// The reservation is bound to the directory object the preconditions
    /// validated, not to the path that named it, so a parent replaced in between
    /// declines the reservation instead of redirecting it — but only for the
    /// duration of that one call. The child effects below take absolute paths
    /// and carry no such binding, which is site 1 of the open gap described
    /// under *Unheld claims* at the top of this file. The two refusals that
    /// can still follow a *non-conforming* seam leave the same single empty
    /// directory that window already allows for, and the model does not remove
    /// it: it has just been told it cannot say what that directory is under.
    public mutating func stage<Sink: QueueInstallationEffectSink>(
        using sink: inout Sink
    ) throws -> QueueInstallationStagedArtifacts {
        guard phase == .planned else { throw QueueInstallationError.invalidPhase }
        // The reservation is bound to the directory object preconditions
        // validated, not to the string that named it. `stagingParentIdentity` is
        // non-nil for every plan, because an unidentified parent refuses at
        // planning time.
        guard let expectedParent = plan.preconditions.stagingParentIdentity else {
            throw QueueInstallationError.protectedRootParentUnconfirmed
        }
        let reservation: ProtectedRootReservation
        do {
            reservation = try sink.createProtectedRoot(
                plan.intent.protectedRoot,
                inside: plan.intent.stagingParent,
                ifParentIdentityMatches: expectedParent
            )
        } catch {
            throw QueueInstallationError.effectFailed
        }
        switch reservation {
        case .parentIdentityChanged:
            // The condition was carried into the operation, so this is a
            // refusal and not a report: nothing was created, and there is
            // nothing to clean up.
            throw QueueInstallationError.stagingParentReplacedBeforeReservation
        case .unknown:
            // `unknown` expressly allows that the reservation acted, so a root
            // may be standing that no journal names. It is left alone, and it
            // is also never described as cleaned up.
            enterUnresolvedRootReservation()
            throw QueueInstallationError.protectedRootParentUnconfirmed
        case let .reserved(actualParent):
            // The argument is not taken on trust. A conformer that ignored it
            // and reserved inside whatever the path resolved to reports that
            // directory here, and is caught by the model rather than by nobody.
            //
            // A refusal at this point leaves the one thing the irreducible
            // window below already allows for: a single empty, fixed-name,
            // root-owned directory, with no journal, because the journal has
            // nowhere to live until the root exists. The model does not remove
            // it, precisely because it has just been told it does not know which
            // directory it is under, and deleting on that basis is the mistake
            // this whole check exists to prevent. It is a case for the manual
            // check in `docs/validation/M1-TRANSACTION-RECOVERY.md`, and it is
            // strictly better than staging a filter and pointing a queue at it.
            //
            // Nor does a later `rollBack` report that root as cleaned up: this
            // transaction's inventory is empty, and an empty inventory derives
            // an empty recovery plan that would otherwise run to `rolledBack`.
            guard actualParent == expectedParent else {
                enterUnresolvedRootReservation()
                throw QueueInstallationError.protectedRootParentUnconfirmed
            }
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
            let creation: FileArtifactCreation
            do {
                creation = try sink.createFile(artifact)
            } catch {
                // The seam's contract gives a throw the guarantee
                // `alreadyPresent` carries — no effect — so the pending mark is
                // retracted for the same reason given below.
                try retractPendingCreation(using: &sink)
                throw QueueInstallationError.effectFailed
            }
            switch creation {
            case .created:
                break
            case .alreadyPresent:
                // Something else is at a path this transaction planned to
                // create. It was not replaced, and this transaction will not
                // adopt it: validating it afterwards would find the planned
                // bytes and say nothing about where they came from.
                //
                // The pending mark is therefore *retracted*, and retracted
                // durably before the refusal is raised. `alreadyPresent`
                // guarantees the seam modified nothing, so this transaction
                // created nothing at that path and owns nothing there — while a
                // pending entry says the opposite. A later automatic `rollBack`
                // probes pending artifacts and removes whatever matches the
                // plan, and a foreign file at a planned path matches the plan by
                // construction: same mode, same digest, same signature. Leaving
                // the mark would have this transaction delete a file it never
                // created, which is the one thing ownership conservation is for.
                //
                // `unknown` below is the case this reasoning does *not* cover.
                // It guarantees nothing, so its path really is one recovery must
                // probe rather than assume, and its mark stays.
                try retractPendingCreation(using: &sink)
                throw QueueInstallationError.stagedArtifactAlreadyPresent(artifact.kind)
            case .unknown:
                throw QueueInstallationError.stagedArtifactCreationUnverified(artifact.kind)
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
        // The token is journalled *with* the pending queue step, before the
        // effect that writes it into a queue. A crash between that effect and
        // its confirmation used to leave a live queue no conditional removal
        // could match — the record named a pending queue and nothing that could
        // pick it out — so the queue and every payload beneath it were residual
        // for good. The intended token is not a claim that the queue exists,
        // and `queueAcquisition` stays nil until the readback below.
        record = try record.markingPending(
            .schedulerQueue, intendedQueueIncarnation: plan.queueIncarnation
        )
        try writeJournal(using: &sink)
        let acquisition: SchedulerQueueAcquisition
        do {
            acquisition = try sink.createQueue(
                plan.intent.queue,
                describedBy: plan.intent.printerDescription,
                deliveringTo: plan.intent.destination,
                incarnation: plan.queueIncarnation
            )
        } catch {
            throw QueueInstallationError.effectFailed
        }
        // The queue stays *pending* until its own configuration hands back the
        // token we wrote. Until then its existence is recorded but unproven as
        // ours, which is exactly what recovery needs to know.
        guard case let .present(observed) = sink.observeQueue(plan.intent.queue),
              let incarnation = observed.incarnation, incarnation == plan.queueIncarnation else {
            throw QueueInstallationError.queueIncarnationUnconfirmed
        }
        // And the token alone does not say where the queue delivers. A create
        // operation that took its target from ambient state would produce a
        // queue carrying our token and pointing somewhere we never asked for,
        // and a token-only readback could not tell the difference. An unreadable
        // destination is unknown, and unknown is not a match.
        guard case let .known(destination) = observed.destination,
              destination == plan.intent.destination else {
            throw QueueInstallationError.queueDestinationUnconfirmed
        }
        // And neither token nor destination says which description the queue
        // was built from. A conformer that ignored `describedBy` would produce
        // a queue carrying our token, delivering where we asked, and running a
        // filter we never planned; an unreadable description is unknown, and
        // unknown is not a match.
        guard let expectedDescription = try? SchedulerQueueDescriptionIdentity(
            describedBy: plan.intent.printerDescription
        ), case let .known(description) = observed.printerDescription,
              description == expectedDescription else {
            throw QueueInstallationError.queueDescriptionUnconfirmed
        }
        // And the description the queue was built from does not say what the
        // queue runs. A scheduler configuration can name a filter of its own,
        // so the executable is read back as its own fact and required to be the
        // one the description declared — which the intent has already required
        // to be this transaction's planned, staged, signed filter. Unreadable
        // is unknown, and unknown is not a match.
        guard let expectedFilter = try? PrinterDescriptionFilterBinding(invoking: plan.intent.filter),
              case let .known(filterBinding) = observed.invokedFilter,
              filterBinding == expectedFilter else {
            throw QueueInstallationError.queueFilterBindingUnconfirmed
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
            guard let incarnation = observed.incarnation, incarnation == plan.queueIncarnation,
                  record.queueIncarnation == plan.queueIncarnation else {
                return enterResidual(.queueIncarnationUnverified, using: &sink)
            }
            guard case let .known(destination) = observed.destination,
                  destination == plan.intent.destination else {
                return enterResidual(.queueDestinationUnverified, using: &sink)
            }
            guard let expectedDescription = try? SchedulerQueueDescriptionIdentity(
                describedBy: plan.intent.printerDescription
            ), case let .known(description) = observed.printerDescription,
                  description == expectedDescription else {
                return enterResidual(.queueDescriptionUnverified, using: &sink)
            }
            guard let expectedFilter = try? PrinterDescriptionFilterBinding(
                invoking: plan.intent.filter
            ), case let .known(filterBinding) = observed.invokedFilter,
                  filterBinding == expectedFilter else {
                return enterResidual(.queueFilterBindingUnverified, using: &sink)
            }
            guard record.queueAcquisition == .exclusiveCreation else {
                return enterResidual(.queueOwnershipAmbiguous, using: &sink)
            }
            // The queue is live from the moment `createQueue` returned, and what
            // it points at can be removed or replaced in the window before this
            // call. Checking the queue's own token says nothing about the state
            // of the files it runs, so the staged artifacts are re-observed here
            // too: a transaction must not report success over a live queue
            // pointing at a payload that is no longer the one that was
            // validated.
            //
            // These observations are still made before the journal write below
            // that makes `.completed` durable, and nothing holds them until it
            // lands. That is site 3 of the open gap described under *Unheld
            // claims* at the top of this file.
            do {
                try revalidateStagedArtifacts(using: &sink)
            } catch {
                return enterResidual(.stagedArtifactChangedBeforeCompletion, using: &sink)
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
        if let unresolved = unresolvedRootReservationOutcome() { return unresolved }
        var recovery = recoveryExecutor()
        let outcome = recovery.recover(using: &sink)
        adopt(recovery, outcome: outcome)
        return outcome
    }

    public mutating func rollBack<Sink: QueueInstallationEffectSink>(
        following plan: QueueInstallationRecoveryPlan,
        using sink: inout Sink
    ) throws -> QueueInstallationOutcome {
        if let unresolved = unresolvedRootReservationOutcome() { return unresolved }
        var recovery = recoveryExecutor()
        let outcome = try recovery.recover(following: plan, using: &sink)
        adopt(recovery, outcome: outcome)
        return outcome
    }

    /// A root reservation whose outcome is unknown is never rolled back and
    /// never reported as rolled back, however often it is asked. Nothing is
    /// sent to the seam: there is no journal to update, and the one object
    /// that may exist is the one this transaction cannot identify.
    private func unresolvedRootReservationOutcome() -> QueueInstallationOutcome? {
        guard rootReservationUnresolved else { return nil }
        return .residual(record, .protectedRootReservationUnverified)
    }

    private func recoveryExecutor() -> QueueInstallationRecovery {
        QueueInstallationRecovery(resumingOwn: record, lastDurableText: lastDurableText)
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
