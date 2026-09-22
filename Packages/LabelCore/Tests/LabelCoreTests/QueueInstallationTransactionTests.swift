import XCTest
@testable import LabelCore

/// An inert, in-memory stand-in for the effect seam. It never touches a
/// filesystem, a scheduler, a process or a device: it is a dictionary, a map and
/// a log. Nothing in this file may be promoted to a real implementation.
///
/// It honours the four contracts the protocol states and the model cannot
/// enforce — exclusive root reservation, compare-and-swap journal replacement,
/// `rmdir`-style empty-directory removal, and writing the incarnation token into
/// the queue — so that the model's behaviour against a *conforming* seam is what
/// the tests measure. Each contract also has a switch to violate it, so the
/// model's response to a non-conforming or hostile world is covered too.
private struct InertInstallationSink: QueueInstallationEffectSink {
    enum Event: Equatable {
        case observeQueue(String)
        case observeFile(String)
        case createProtectedRoot(String)
        case createFile(String)
        case createQueue(String)
        case persistRecord(String)
        case readRecord(String)
        case removeQueue(String)
        case removeFile(String)
        case removeEmptyDirectory(String)
    }

    enum Failure: Error { case refused, notExclusive, notEmpty, staleJournal }

    var files: [String: ObservedFileState] = [:]
    /// Queues this stand-in holds, each with the incarnation token readable out
    /// of its configuration (nil when none is readable).
    var queues: [String: SchedulerQueueIncarnation?] = [:]
    var persistedRecord: String?
    /// What a read of the journal returns instead of what was written. This is
    /// the window between the transaction's last write and its next read.
    var journalOverrideOnRead: String?
    var queueQueryFails = false
    var recordQueryFails = false
    var fileQueryFailures: Set<String> = []
    var createFileFailures: Set<String> = []
    var createRootFails = false
    var createQueueFails = false
    var persistRecordFails = false
    var removeQueueFails = false
    var removeFileFailures: Set<String> = []
    var removeEmptyDirectoryFails = false
    /// What `createQueue` reports it could prove. A seam built on `lpadmin`
    /// would always report `ambiguousCreateOrModify`.
    var acquisition: SchedulerQueueAcquisition = .exclusiveCreation
    /// Creates the queue without writing the incarnation token into it.
    var incarnationWriteFails = false
    /// Stages these bytes/metadata instead of the planned ones. This is the
    /// TOCTOU window between staging and validating, made reproducible.
    var tamperOnCreate: [String: ObservedFileState] = [:]
    /// Paths whose removal call succeeds without the path actually going away.
    var removalsWithoutEffect: Set<String> = []
    var queueRemovalWithoutEffect = false
    private(set) var log: [Event] = []

    var removalEvents: [Event] {
        log.filter {
            switch $0 {
            case .removeQueue, .removeFile, .removeEmptyDirectory: true
            default: false
            }
        }
    }

    mutating func observeQueue(_ queue: PlannedSchedulerQueue) -> SchedulerQueueObservation {
        log.append(.observeQueue(queue.name))
        if queueQueryFails { return .queryFailed }
        guard let incarnation = queues[queue.name] else { return .confirmedAbsent }
        return .present(incarnation)
    }

    mutating func observeFile(at path: AbsolutePath) -> FileArtifactObservation {
        log.append(.observeFile(path.value))
        if fileQueryFailures.contains(path.value) { return .queryFailed }
        guard let state = files[path.value] else { return .confirmedAbsent }
        return .present(state)
    }

    mutating func createProtectedRoot(_ artifact: PlannedFileArtifact) throws {
        log.append(.createProtectedRoot(artifact.path.value))
        if createRootFails { throw Failure.refused }
        // Contract: mkdir semantics. Anything already there is a refusal.
        guard files[artifact.path.value] == nil else { throw Failure.notExclusive }
        files[artifact.path.value] = try state(of: artifact)
    }

    mutating func createFile(_ artifact: PlannedFileArtifact) throws {
        log.append(.createFile(artifact.path.value))
        if createFileFailures.contains(artifact.path.value) { throw Failure.refused }
        guard files[artifact.path.value] == nil else { throw Failure.notExclusive }
        if let tampered = tamperOnCreate[artifact.path.value] {
            files[artifact.path.value] = tampered
        } else {
            files[artifact.path.value] = try state(of: artifact)
        }
    }

    private func state(of artifact: PlannedFileArtifact) throws -> ObservedFileState {
        try ObservedFileState(
            kind: artifact.expectedFileKind,
            uid: artifact.ownership.uid,
            gid: artifact.ownership.gid,
            modeBits: artifact.mode.rawValue,
            contentSHA256: artifact.contentSHA256
        )
    }

    mutating func persistOwnershipRecord(
        _ text: String, replacing previous: String?, at artifact: PlannedFileArtifact
    ) throws {
        log.append(.persistRecord(artifact.path.value))
        if persistRecordFails { throw Failure.refused }
        // Contract: replace in one step, and only if the current contents are
        // exactly `previous` (nil meaning it must not exist).
        guard persistedRecord == previous else { throw Failure.staleJournal }
        persistedRecord = text
        files[artifact.path.value] = try ObservedFileState(
            kind: .regularFile,
            uid: artifact.ownership.uid,
            gid: artifact.ownership.gid,
            modeBits: artifact.mode.rawValue
        )
    }

    mutating func readOwnershipRecord(at artifact: PlannedFileArtifact) -> OwnershipRecordObservation {
        log.append(.readRecord(artifact.path.value))
        if recordQueryFails { return .queryFailed }
        if let journalOverrideOnRead { return .present(journalOverrideOnRead) }
        guard let persistedRecord else { return .confirmedAbsent }
        return .present(persistedRecord)
    }

    mutating func createQueue(
        _ queue: PlannedSchedulerQueue,
        describedBy description: PlannedFileArtifact,
        incarnation: SchedulerQueueIncarnation
    ) throws -> SchedulerQueueAcquisition {
        log.append(.createQueue(queue.name))
        if createQueueFails { throw Failure.refused }
        // Contract: write the token into the queue's own configuration.
        queues[queue.name] = incarnationWriteFails ? nil : incarnation
        return acquisition
    }

    mutating func removeQueue(_ queue: PlannedSchedulerQueue) throws {
        log.append(.removeQueue(queue.name))
        if removeQueueFails { throw Failure.refused }
        if queueRemovalWithoutEffect { return }
        queues.removeValue(forKey: queue.name)
    }

    mutating func removeFile(at path: AbsolutePath) throws {
        log.append(.removeFile(path.value))
        if removeFileFailures.contains(path.value) { throw Failure.refused }
        if removalsWithoutEffect.contains(path.value) { return }
        files.removeValue(forKey: path.value)
        if path.value == Fixture.recordPath { persistedRecord = nil }
    }

    mutating func removeEmptyDirectory(at path: AbsolutePath) throws {
        log.append(.removeEmptyDirectory(path.value))
        if removeEmptyDirectoryFails { throw Failure.refused }
        // Contract: rmdir semantics. A non-empty directory is a refusal, never a
        // recursive delete.
        guard !files.keys.contains(where: { $0.hasPrefix(path.value + "/") }) else { throw Failure.notEmpty }
        files.removeValue(forKey: path.value)
    }
}

private enum Fixture {
    static let stagingParent = "/Library/Printers"
    static let rootPath = "/Library/Printers/LabelDriverModel"
    static let recordPath = "/Library/Printers/LabelDriverModel/OWNERSHIP"
    static let filterPath = "/Library/Printers/LabelDriverModel/labelcapture-filter"
    static let descriptionPath = "/Library/Printers/LabelDriverModel/capture.ppd"
    static let queueName = "LabelDriver-Model"
    static let transactionHex = "0123456789abcdef0123456789abcdef"

    static func digest(_ seed: String) -> String {
        String(repeating: seed, count: 64 / seed.utf8.count)
    }

    static func incarnation(_ seed: String = "1") throws -> SchedulerQueueIncarnation {
        try SchedulerQueueIncarnation(token: digest(seed))
    }

    static func intent(rootPath: String = rootPath, queueName: String = queueName) throws -> QueueInstallationIntent {
        try QueueInstallationIntent(
            queue: PlannedSchedulerQueue(name: queueName),
            protectedRoot: PlannedFileArtifact(
                kind: .protectedRoot, path: AbsolutePath(rootPath),
                mode: POSIXMode(0o755), contentSHA256: nil
            ),
            ownershipRecord: PlannedFileArtifact(
                kind: .ownershipRecord, path: AbsolutePath(rootPath + "/OWNERSHIP"),
                mode: POSIXMode(0o644), contentSHA256: nil
            ),
            filter: PlannedFileArtifact(
                kind: .filterExecutable, path: AbsolutePath(rootPath + "/labelcapture-filter"),
                mode: POSIXMode(0o755), contentSHA256: digest("b")
            ),
            printerDescription: PlannedFileArtifact(
                kind: .printerDescription, path: AbsolutePath(rootPath + "/capture.ppd"),
                mode: POSIXMode(0o644), contentSHA256: digest("c")
            )
        )
    }

    static func suitableParent() throws -> ObservedFileState {
        try ObservedFileState(kind: .directory, uid: 0, gid: 0, modeBits: 0o755)
    }

    static func cleanSink() throws -> InertInstallationSink {
        var sink = InertInstallationSink()
        sink.files[stagingParent] = try suitableParent()
        return sink
    }

    static func plan(
        with sink: inout InertInstallationSink,
        intent overriding: QueueInstallationIntent? = nil,
        transactionHex hex: String = transactionHex,
        incarnationSeed: String = "1"
    ) throws -> QueueInstallationPlan {
        let intent = try overriding ?? intent()
        let preconditions = QueueInstallationPreconditions.capture(for: intent, from: &sink)
        return try QueueInstallationPlan(
            transactionID: QueueInstallationTransactionID(hex: hex),
            queueIncarnation: incarnation(incarnationSeed),
            intent: intent,
            preconditions: preconditions
        )
    }

    /// Plans, stages, validates, creates the queue and completes.
    static func installed(
        _ sink: inout InertInstallationSink
    ) throws -> (QueueInstallationTransaction, QueueInstallationOutcome) {
        let plan = try plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        let outcome = try transaction.complete(using: &sink)
        return (transaction, outcome)
    }

    /// The separately authorized recovery a human drives from the record.
    static func recordValidated(
        _ transaction: QueueInstallationTransaction
    ) throws -> QueueInstallationRecovery {
        try QueueInstallationRecovery(
            resuming: transaction.record, authority: .recordValidated,
            lastDurableText: transaction.lastDurableText
        )
    }

    static let everyArtifact: [QueueInstallationArtifactID] = {
        [
            .file(try! AbsolutePath(rootPath)),
            .file(try! AbsolutePath(recordPath)),
            .file(try! AbsolutePath(filterPath)),
            .file(try! AbsolutePath(descriptionPath)),
            .schedulerQueue,
        ]
    }()
}

final class QueueInstallationTransactionTests: XCTestCase {

    // MARK: - Bounded primitives

    func testAbsolutePathRejectsRelativeAndAmbiguousValues() throws {
        XCTAssertNoThrow(try AbsolutePath("/Library/Printers/LabelDriverModel"))
        for rejected in [
            "", "/", "relative/path", "/trailing/", "/a//b", "/a/../b", "/a/./b",
            "/has=equals", "/has:colon", "/has|pipe", "/has\u{7f}delete",
        ] {
            XCTAssertThrowsError(try AbsolutePath(rejected), rejected) {
                XCTAssertEqual($0 as? QueueInstallationError, .invalidPath)
            }
        }
        XCTAssertThrowsError(try AbsolutePath("/" + String(repeating: "x", count: 1024)))
    }

    func testAbsolutePathParentAndImmediateChildAreExact() throws {
        let root = try AbsolutePath(Fixture.rootPath)
        XCTAssertEqual(root.parent, try AbsolutePath(Fixture.stagingParent))
        XCTAssertTrue(try AbsolutePath(Fixture.filterPath).isImmediateChild(of: root))
        XCTAssertFalse(try AbsolutePath(Fixture.rootPath + "/nested/deep").isImmediateChild(of: root))
        XCTAssertNil(try AbsolutePath("/single").parent)
    }

    func testModeRejectsWritableAndSpecialBitsAndRoundTripsAsOctal() throws {
        XCTAssertEqual(try POSIXMode(0o755).octalText, "0755")
        XCTAssertEqual(try POSIXMode(0o644).octalText, "0644")
        XCTAssertEqual(try POSIXMode.decodeOctal("0755"), try POSIXMode(0o755))
        for rejected in [0o777, 0o775, 0o666, 0o4755, 0o2755, 0o1755, -1, 0o10000] {
            XCTAssertThrowsError(try POSIXMode(rejected), String(rejected)) {
                XCTAssertEqual($0 as? QueueInstallationError, .invalidMode)
            }
        }
        for rejected in ["755", "07555", "0758", "0o75", ""] {
            XCTAssertThrowsError(try POSIXMode.decodeOctal(rejected), rejected)
        }
    }

    func testQueueNameIsAnIdentifierNotAPathOrCommandFragment() throws {
        XCTAssertNoThrow(try PlannedSchedulerQueue(name: Fixture.queueName))
        for rejected in [
            "", "/Library/Printers", "queue name", "queue;rm", "-leading", "_leading",
            "queue#1", "queue/child", "quote\"d", String(repeating: "q", count: 128),
        ] {
            XCTAssertThrowsError(try PlannedSchedulerQueue(name: rejected), rejected) {
                XCTAssertEqual($0 as? QueueInstallationError, .invalidQueueName)
            }
        }
    }

    func testPlannedArtifactBindsKindToModeOwnershipAndDigest() throws {
        let path = try AbsolutePath(Fixture.filterPath)
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .filterExecutable, path: path, mode: POSIXMode(0o755), contentSHA256: nil
        )) { XCTAssertEqual($0 as? QueueInstallationError, .invalidDigest) }
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .protectedRoot, path: path, mode: POSIXMode(0o755), contentSHA256: Fixture.digest("a")
        )) { XCTAssertEqual($0 as? QueueInstallationError, .artifactKindMismatch) }
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .ownershipRecord, path: path, mode: POSIXMode(0o644), contentSHA256: Fixture.digest("a")
        )) { XCTAssertEqual($0 as? QueueInstallationError, .artifactKindMismatch) }
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .filterExecutable, path: path, mode: POSIXMode(0o644), contentSHA256: Fixture.digest("b")
        )) { XCTAssertEqual($0 as? QueueInstallationError, .artifactKindMismatch) }
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .filterExecutable, path: path, ownership: POSIXOwnership(uid: 501, gid: 20),
            mode: POSIXMode(0o755), contentSHA256: Fixture.digest("b")
        )) { XCTAssertEqual($0 as? QueueInstallationError, .invalidOwnership) }
    }

    func testIntentRequiresEveryArtifactImmediatelyInsideTheProtectedRoot() throws {
        let outside = try PlannedFileArtifact(
            kind: .filterExecutable, path: AbsolutePath("/usr/local/bin/labelcapture-filter"),
            mode: POSIXMode(0o755), contentSHA256: Fixture.digest("b")
        )
        let intent = try Fixture.intent()
        XCTAssertThrowsError(try QueueInstallationIntent(
            queue: intent.queue, protectedRoot: intent.protectedRoot,
            ownershipRecord: intent.ownershipRecord, filter: outside,
            printerDescription: intent.printerDescription
        )) { XCTAssertEqual($0 as? QueueInstallationError, .artifactOutsideProtectedRoot) }
        XCTAssertEqual(intent.stagingParent.value, Fixture.stagingParent)
        XCTAssertEqual(
            intent.creationOrderedFiles.map(\.kind),
            [.protectedRoot, .ownershipRecord, .filterExecutable, .printerDescription]
        )
        // The root has its own exclusive reservation and the journal is written,
        // so neither goes through the generic create.
        XCTAssertEqual(
            intent.stagedPayloadFiles.map(\.kind), [.filterExecutable, .printerDescription]
        )
    }

    func testIncarnationRequiresSixtyFourLowercaseHexDigits() throws {
        XCTAssertNoThrow(try SchedulerQueueIncarnation(token: Fixture.digest("a")))
        for rejected in ["", Fixture.digest("A"), Fixture.transactionHex, Fixture.digest("a") + "0"] {
            XCTAssertThrowsError(try SchedulerQueueIncarnation(token: rejected), rejected) {
                XCTAssertEqual($0 as? QueueInstallationError, .invalidIncarnation)
            }
        }
    }

    // MARK: - Preconditions gate planning

    func testPlanRefusesAPreExistingQueueRatherThanAdoptingIt() throws {
        var sink = try Fixture.cleanSink()
        sink.queues[Fixture.queueName] = try Fixture.incarnation("e")
        XCTAssertThrowsError(try Fixture.plan(with: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.queueAlreadyPresent))
        }
        XCTAssertTrue(sink.log.allSatisfy {
            switch $0 {
            case .observeQueue, .observeFile: true
            default: false
            }
        })
    }

    /// Finding Q: observations of one intent's staging parent and root must not
    /// license a plan for a different intent.
    func testPlanRefusesPreconditionsCapturedForAnotherIntent() throws {
        var sink = try Fixture.cleanSink()
        let inspected = try Fixture.intent()
        let preconditions = QueueInstallationPreconditions.capture(for: inspected, from: &sink)
        let other = try Fixture.intent(rootPath: "/Library/Printers/OtherModel")
        XCTAssertThrowsError(try QueueInstallationPlan(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queueIncarnation: Fixture.incarnation(),
            intent: other,
            preconditions: preconditions
        )) { XCTAssertEqual($0 as? QueueInstallationError, .preconditionsIntentMismatch) }
        XCTAssertEqual(preconditions.intent, inspected)
        // The admissible pairing still works.
        XCTAssertNoThrow(try QueueInstallationPlan(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queueIncarnation: Fixture.incarnation(),
            intent: inspected,
            preconditions: preconditions
        ))
    }

    func testAFailedQueryIsNeverReadAsAbsence() throws {
        XCTAssertFalse(SchedulerQueueObservation.queryFailed.isConfirmedAbsent)
        XCTAssertFalse(SchedulerQueueObservation.queryFailed.isConfirmedPresent)
        XCTAssertFalse(FileArtifactObservation.queryFailed.isConfirmedAbsent)
        XCTAssertTrue(SchedulerQueueObservation.present(nil).isConfirmedPresent)
        XCTAssertNil(SchedulerQueueObservation.present(nil).incarnation)

        var sink = try Fixture.cleanSink()
        sink.queueQueryFails = true
        XCTAssertThrowsError(try Fixture.plan(with: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.queueStateUnknown))
        }

        var unreadableRoot = try Fixture.cleanSink()
        unreadableRoot.fileQueryFailures.insert(Fixture.rootPath)
        XCTAssertThrowsError(try Fixture.plan(with: &unreadableRoot)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.protectedRootStateUnknown))
        }
    }

    func testPlanRefusesAnExistingRootOrAnUnsuitableStagingParent() throws {
        var occupied = try Fixture.cleanSink()
        occupied.files[Fixture.rootPath] = try ObservedFileState(kind: .directory, uid: 0, gid: 0, modeBits: 0o755)
        XCTAssertThrowsError(try Fixture.plan(with: &occupied)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.protectedRootAlreadyPresent))
        }

        let unsuitable: [(String, ObservedFileState)] = [
            ("world-writable", try ObservedFileState(kind: .directory, uid: 0, gid: 0, modeBits: 0o777)),
            ("not-root-owned", try ObservedFileState(kind: .directory, uid: 501, gid: 0, modeBits: 0o755)),
            ("symlink", try ObservedFileState(kind: .symbolicLink, uid: 0, gid: 0, modeBits: 0o755)),
            ("regular-file", try ObservedFileState(kind: .regularFile, uid: 0, gid: 0, modeBits: 0o644)),
        ]
        for (label, state) in unsuitable {
            var sink = try Fixture.cleanSink()
            sink.files[Fixture.stagingParent] = state
            XCTAssertThrowsError(try Fixture.plan(with: &sink), label) {
                XCTAssertEqual($0 as? QueueInstallationError, .refused(.stagingParentUnsuitable))
            }
        }

        var partial = try Fixture.cleanSink()
        partial.files[Fixture.stagingParent] = try ObservedFileState(kind: .directory, uid: 0, gid: 0)
        XCTAssertThrowsError(try Fixture.plan(with: &partial)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.stagingParentStateUnknown))
        }
    }

    func testTheRootReservationIsTheTransactionsExclusiveStep() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        // The root appeared between planning and staging. A conforming seam
        // reserves exclusively, so staging fails rather than adopting it.
        sink.files[Fixture.rootPath] = try ObservedFileState(kind: .directory, uid: 0, gid: 0, modeBits: 0o755)
        XCTAssertThrowsError(try transaction.stage(using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .effectFailed)
        }
        XCTAssertNil(sink.persistedRecord)
    }

    // MARK: - The ordered transaction

    func testCompleteInstallationRecordsEveryArtifactInCreationOrder() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, outcome) = try Fixture.installed(&sink)
        XCTAssertTrue(outcome.isCompleted)
        XCTAssertFalse(outcome.requiresManualRecovery)
        XCTAssertEqual(transaction.phase, .completed)
        XCTAssertEqual(transaction.record.phase, .completed)
        XCTAssertEqual(transaction.record.createdArtifacts, Fixture.everyArtifact)
        XCTAssertEqual(transaction.record.createdArtifacts, transaction.plan.inventory)
        XCTAssertNil(transaction.record.pendingArtifact)
        XCTAssertEqual(transaction.record.queueIncarnation, try Fixture.incarnation())
        XCTAssertEqual(transaction.record.queueAcquisition, .exclusiveCreation)
        let created = sink.log.compactMap { event -> String? in
            switch event {
            case let .createProtectedRoot(path), let .createFile(path): path
            case let .createQueue(name): "queue:" + name
            default: nil
            }
        }
        XCTAssertEqual(created.last, "queue:" + Fixture.queueName)
        XCTAssertTrue(created.firstIndex(of: Fixture.filterPath)! < created.count - 1)
    }

    /// Finding J: the note of a step must precede its effect, or an interruption
    /// between them hides an artifact from recovery entirely.
    func testEveryStepIsJournalledAsPendingBeforeItsEffect() throws {
        var sink = try Fixture.cleanSink()
        sink.createFileFailures.insert(Fixture.filterPath)
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        XCTAssertThrowsError(try transaction.stage(using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .effectFailed)
        }
        // The durable record names the filter even though its creation failed,
        // because its existence is unknown, not known-absent.
        let durable = try QueueInstallationOwnershipRecord.decode(try XCTUnwrap(sink.persistedRecord))
        XCTAssertEqual(durable.pendingArtifact, .file(try AbsolutePath(Fixture.filterPath)))
        XCTAssertTrue(durable.owns(.file(try AbsolutePath(Fixture.filterPath))))
        XCTAssertEqual(durable, transaction.record)
        // And recovery covers it, most-recent-first.
        let recovery = try transaction.recoveryPlan()
        XCTAssertEqual(recovery.steps.first, .removeFile(plan.intent.filter))
    }

    /// Finding J: the same rule for the queue, which is the step whose omission
    /// would leave a live queue pointing at a filter recovery then deleted.
    func testAnUnconfirmedQueueStaysPendingAndRecoveryCoversItQueueFirst() throws {
        var sink = try Fixture.cleanSink()
        sink.incarnationWriteFails = true
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .queueIncarnationUnconfirmed)
        }
        let durable = try QueueInstallationOwnershipRecord.decode(try XCTUnwrap(sink.persistedRecord))
        XCTAssertEqual(durable.pendingArtifact, .schedulerQueue)
        XCTAssertNil(durable.queueIncarnation)
        XCTAssertEqual(try transaction.recoveryPlan().steps.first, .removeQueue(plan.intent.queue))
    }

    /// Finding J: a pending artifact that *does* exist must be probed and
    /// removed, never assumed absent.
    func testRecoveryProbesAPendingArtifactRatherThanAssumingItAbsent() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        _ = try transaction.stage(using: &sink)
        // Simulate a kill after the effect but before the confirming write: the
        // record says pending, the artifact exists.
        var record = try QueueInstallationOwnershipRecord(
            transactionID: plan.transactionID, queue: plan.intent.queue, phase: .inProgress,
            pendingArtifact: .schedulerQueue,
            files: plan.intent.creationOrderedFiles,
            createdArtifacts: Array(Fixture.everyArtifact.dropLast())
        )
        sink.queues[Fixture.queueName] = try Fixture.incarnation()
        sink.persistedRecord = record.canonicalText
        var recovery = try QueueInstallationRecovery(
            resuming: record, authority: .recordValidated, lastDurableText: record.canonicalText
        )
        XCTAssertEqual(try recovery.recoveryPlan().steps.first, .removeQueue(plan.intent.queue))
        let outcome = recovery.recover(using: &sink)
        // The pending queue carries no recorded incarnation, so it cannot be
        // proved ours and is retained rather than deleted.
        XCTAssertEqual(outcome, .residual(recovery.record, .queueIncarnationUnverified))
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
        record = recovery.record
        XCTAssertEqual(record.pendingArtifact, .schedulerQueue)
    }

    func testValidationAfterStagingCatchesATOCTOUSubstitution() throws {
        var sink = try Fixture.cleanSink()
        sink.tamperOnCreate[Fixture.filterPath] = try ObservedFileState(
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("f")
        )
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        XCTAssertEqual(transaction.phase, .staged)
        XCTAssertThrowsError(try transaction.validateStagedArtifacts(staged, using: &sink)) {
            XCTAssertEqual(
                $0 as? QueueInstallationError,
                .stagedArtifactInvalid(.filterExecutable, .contentMismatch)
            )
        }
        XCTAssertEqual(transaction.phase, .staged)
        XCTAssertTrue(sink.queues.isEmpty)
        XCTAssertFalse(transaction.record.owns(.schedulerQueue))
    }

    /// Finding L: a validation token proves validation happened, not that it
    /// still holds. A filter replaced afterwards must not get a live queue.
    func testQueueIsNotCreatedWhenAStagedFileChangedAfterValidation() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        // The window between validation and queue creation.
        sink.files[Fixture.filterPath] = try ObservedFileState(
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("9")
        )
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &sink)) {
            XCTAssertEqual(
                $0 as? QueueInstallationError,
                .stagedArtifactInvalid(.filterExecutable, .contentMismatch)
            )
        }
        XCTAssertTrue(sink.queues.isEmpty)
        XCTAssertFalse(sink.log.contains(.createQueue(Fixture.queueName)))
        XCTAssertFalse(transaction.record.owns(.schedulerQueue))
    }

    /// Finding L, journal arm: the journal is part of what must still hold.
    func testQueueIsNotCreatedWhenTheJournalDivergedAfterValidation() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        sink.journalOverrideOnRead = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "d", count: 32)),
            queue: plan.intent.queue, phase: .inProgress,
            files: plan.intent.creationOrderedFiles, createdArtifacts: []
        ).canonicalText
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &sink)) {
            XCTAssertEqual(
                $0 as? QueueInstallationError,
                .stagedArtifactInvalid(.ownershipRecord, .contentMismatch)
            )
        }
        XCTAssertTrue(sink.queues.isEmpty)
    }

    func testValidationRejectsOwnershipModeSymlinkAndUnknownObservations() throws {
        let substitutions: [(ObservedFileState?, ArtifactValidationFailure)] = [
            (try ObservedFileState(kind: .symbolicLink, uid: 0, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b")), .symbolicLink),
            (try ObservedFileState(kind: .directory, uid: 0, gid: 0, modeBits: 0o755), .wrongFileKind),
            (try ObservedFileState(kind: .regularFile, uid: 501, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b")), .ownershipMismatch),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0, modeBits: 0o700,
                                   contentSHA256: Fixture.digest("b")), .modeMismatch),
            (try ObservedFileState(kind: .regularFile, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b")), .ownershipUnknown),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0,
                                   contentSHA256: Fixture.digest("b")), .modeUnknown),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755), .contentUnknown),
            (nil, .absent),
        ]
        for (state, expected) in substitutions {
            var sink = try Fixture.cleanSink()
            let plan = try Fixture.plan(with: &sink)
            var transaction = try QueueInstallationTransaction(plan: plan)
            let staged = try transaction.stage(using: &sink)
            if let state {
                sink.files[Fixture.filterPath] = state
            } else {
                sink.files.removeValue(forKey: Fixture.filterPath)
            }
            XCTAssertThrowsError(
                try transaction.validateStagedArtifacts(staged, using: &sink), String(describing: expected)
            ) {
                XCTAssertEqual(
                    $0 as? QueueInstallationError, .stagedArtifactInvalid(.filterExecutable, expected)
                )
            }
        }

        var unreadable = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &unreadable)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &unreadable)
        unreadable.fileQueryFailures.insert(Fixture.filterPath)
        XCTAssertThrowsError(try transaction.validateStagedArtifacts(staged, using: &unreadable)) {
            XCTAssertEqual(
                $0 as? QueueInstallationError, .stagedArtifactInvalid(.filterExecutable, .observationFailed)
            )
        }
    }

    func testValidationReadsTheDurableRecordBackAndRejectsADivergentOne() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        sink.journalOverrideOnRead = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "c", count: 32)),
            queue: plan.intent.queue, phase: .inProgress,
            files: plan.intent.creationOrderedFiles, createdArtifacts: []
        ).canonicalText
        XCTAssertThrowsError(try transaction.validateStagedArtifacts(staged, using: &sink)) {
            XCTAssertEqual(
                $0 as? QueueInstallationError, .stagedArtifactInvalid(.ownershipRecord, .contentMismatch)
            )
        }

        var unreadable = try Fixture.cleanSink()
        let secondPlan = try Fixture.plan(with: &unreadable)
        var second = try QueueInstallationTransaction(plan: secondPlan)
        let secondStaged = try second.stage(using: &unreadable)
        unreadable.recordQueryFails = true
        XCTAssertThrowsError(try second.validateStagedArtifacts(secondStaged, using: &unreadable)) {
            XCTAssertEqual(
                $0 as? QueueInstallationError, .stagedArtifactInvalid(.ownershipRecord, .observationFailed)
            )
        }
    }

    func testStepsCannotRunOutOfOrder() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        XCTAssertThrowsError(try transaction.complete(using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
        let staged = try transaction.stage(using: &sink)
        XCTAssertThrowsError(try transaction.stage(using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        XCTAssertThrowsError(try transaction.validateStagedArtifacts(staged, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
    }

    func testATokenCannotCrossBetweenTransactionsSharingAnIdentifier() throws {
        var firstSink = try Fixture.cleanSink()
        let firstPlan = try Fixture.plan(with: &firstSink)
        var first = try QueueInstallationTransaction(plan: firstPlan)
        let firstStaged = try first.stage(using: &firstSink)
        let firstValidated = try first.validateStagedArtifacts(firstStaged, using: &firstSink)

        var otherSink = try Fixture.cleanSink()
        let otherIntent = try Fixture.intent(rootPath: "/Library/Printers/OtherModel")
        let otherPlan = try Fixture.plan(with: &otherSink, intent: otherIntent)
        XCTAssertEqual(otherPlan.transactionID, firstPlan.transactionID)
        XCTAssertNotEqual(otherPlan.intent, firstPlan.intent)

        var other = try QueueInstallationTransaction(plan: otherPlan)
        _ = try other.stage(using: &otherSink)
        XCTAssertThrowsError(try other.validateStagedArtifacts(firstStaged, using: &otherSink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .transactionMismatch)
        }

        var another = try QueueInstallationTransaction(plan: otherPlan)
        var anotherSink = try Fixture.cleanSink()
        let anotherStaged = try another.stage(using: &anotherSink)
        _ = try another.validateStagedArtifacts(anotherStaged, using: &anotherSink)
        XCTAssertThrowsError(try another.createQueue(authorizedBy: firstValidated, using: &anotherSink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .transactionMismatch)
        }
        XCTAssertTrue(anotherSink.queues.isEmpty)
    }

    func testQueueAbsenceIsReProvedImmediatelyBeforeCreation() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        sink.queues[Fixture.queueName] = try Fixture.incarnation("e")
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.queueAlreadyPresent))
        }
        XCTAssertFalse(transaction.record.owns(.schedulerQueue))
        XCTAssertFalse(sink.log.contains(.createQueue(Fixture.queueName)))
    }

    /// Finding M: create-or-modify success is not acquisition. The repository's
    /// own recovery document says a successful response and exact readback
    /// "cannot prove that no competing queue was modified", so a seam that can
    /// only offer that must never reach a completed installation.
    func testAnAmbiguousCreateOrModifyIsNeverCompleted() throws {
        var sink = try Fixture.cleanSink()
        sink.acquisition = .ambiguousCreateOrModify
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        XCTAssertEqual(transaction.record.queueAcquisition, .ambiguousCreateOrModify)

        let outcome = try transaction.complete(using: &sink)
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertTrue(outcome.requiresManualRecovery)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueOwnershipAmbiguous))
        // A record can no more claim completion than the transaction can.
        XCTAssertThrowsError(try transaction.record.replacingPhase(.completed)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
    }

    func testUnknownQueueStateAfterCreationIsResidualNotCompleted() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        sink.queueQueryFails = true
        let outcome = try transaction.complete(using: &sink)
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueStateUnknownAfterCreation))
        XCTAssertEqual(transaction.record.phase, .residual)
        XCTAssertEqual(transaction.record.createdArtifacts.count, 5)
    }

    func testAQueueThatVanishedAfterCreationIsResidualNotCompleted() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        sink.queues.removeValue(forKey: Fixture.queueName)
        let outcome = try transaction.complete(using: &sink)
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueAbsentAfterCreation))
    }

    func testCompletionRequiresTheIncarnationOfTheQueueItCreated() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        // The queue is present, but no longer carries our token.
        sink.queues[Fixture.queueName] = nil as SchedulerQueueIncarnation?
        let outcome = try transaction.complete(using: &sink)
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueIncarnationUnverified))
    }

    // MARK: - Recovery ordering and authority

    func testRecoveryPlanRefusesAnyFileBeforeTheQueue() throws {
        let intent = try Fixture.intent()
        let queueStep = QueueInstallationRecoveryPlan.Step.removeQueue(intent.queue)
        let filterStep = QueueInstallationRecoveryPlan.Step.removeFile(intent.filter)
        let rootStep = QueueInstallationRecoveryPlan.Step.removeFile(intent.protectedRoot)

        XCTAssertNoThrow(try QueueInstallationRecoveryPlan(steps: [queueStep, filterStep, rootStep]))
        XCTAssertThrowsError(try QueueInstallationRecoveryPlan(steps: [filterStep, queueStep, rootStep])) {
            XCTAssertEqual($0 as? QueueInstallationError, .recoveryOrderingViolation)
        }
        XCTAssertThrowsError(try QueueInstallationRecoveryPlan(steps: [queueStep, rootStep, filterStep])) {
            XCTAssertEqual($0 as? QueueInstallationError, .recoveryOrderingViolation)
        }
        XCTAssertThrowsError(try QueueInstallationRecoveryPlan(steps: [queueStep, filterStep, filterStep])) {
            XCTAssertEqual($0 as? QueueInstallationError, .duplicateArtifactPath)
        }
    }

    /// Finding M, recovery arm: automatic rollback never removes a *present*
    /// queue, matching what `docs/validation/M1-TRANSACTION-RECOVERY.md`
    /// already requires of the M1 experiment.
    func testAutomaticRollbackNeverRemovesAPresentQueue() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueOwnershipAmbiguous))
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.queues[Fixture.queueName])
        // Everything is retained for explicit, record-validated recovery.
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertEqual(transaction.record.createdArtifacts.count, 5)
    }

    func testRecordValidatedRecoveryRemovesTheQueueBeforeTheFilter() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(recovery.record))
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertEqual(
            sink.removalEvents,
            [
                .removeQueue(Fixture.queueName),
                .removeFile(Fixture.descriptionPath),
                .removeFile(Fixture.filterPath),
                .removeFile(Fixture.recordPath),
                .removeEmptyDirectory(Fixture.rootPath),
            ]
        )
        XCTAssertTrue(sink.queues.isEmpty)
        XCTAssertNil(sink.files[Fixture.rootPath])
        XCTAssertNotNil(sink.files[Fixture.stagingParent])
        XCTAssertTrue(recovery.record.createdArtifacts.isEmpty)
    }

    /// Finding N: the root is a directory and is removed with an operation whose
    /// contract forbids recursion, so an unowned child stops recovery.
    func testTheProtectedRootIsRemovedOnlyAsAnEmptyDirectory() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        // An unowned file appears beneath the root.
        sink.files[Fixture.rootPath + "/stranger"] = try ObservedFileState(
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o644
        )
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .effectFailed))
        XCTAssertEqual(sink.removalEvents.last, .removeEmptyDirectory(Fixture.rootPath))
        // The root and the stranger both survive; nothing was swept away.
        XCTAssertNotNil(sink.files[Fixture.rootPath])
        XCTAssertNotNil(sink.files[Fixture.rootPath + "/stranger"])
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.rootPath)))
    }

    func testRollbackRefusesAnEmptyRecoveryPlanInsteadOfClaimingSuccess() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        var recovery = try Fixture.recordValidated(transaction)
        let empty = try QueueInstallationRecoveryPlan(steps: [])
        XCTAssertThrowsError(try recovery.recover(following: empty, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .incompleteRecoveryPlan)
        }
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertEqual(recovery.record.createdArtifacts.count, 5)
        XCTAssertNotEqual(recovery.record.phase, .rolledBack)
        XCTAssertNotNil(sink.queues[Fixture.queueName])
    }

    func testRollbackRefusesAPlanThatOmitsTheQueue() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        var recovery = try Fixture.recordValidated(transaction)
        let canonical = try recovery.recoveryPlan()
        let withoutQueue = try QueueInstallationRecoveryPlan(steps: Array(canonical.steps.dropFirst()))
        XCTAssertThrowsError(try recovery.recover(following: withoutQueue, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .incompleteRecoveryPlan)
        }
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertNotNil(sink.queues[Fixture.queueName])
    }

    func testRollbackAfterPartialStagingTouchesNoQueueAndRemovesOnlyWhatExists() throws {
        var sink = try Fixture.cleanSink()
        sink.createFileFailures.insert(Fixture.filterPath)
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        XCTAssertThrowsError(try transaction.stage(using: &sink))
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(transaction.record))
        XCTAssertEqual(
            sink.removalEvents,
            [.removeFile(Fixture.recordPath), .removeEmptyDirectory(Fixture.rootPath)]
        )
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
        XCTAssertTrue(transaction.record.createdArtifacts.isEmpty)
        XCTAssertNil(transaction.record.pendingArtifact)
    }

    func testRollbackNeverRemovesAQueueTheTransactionDidNotCreate() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        _ = try transaction.stage(using: &sink)
        sink.queues[Fixture.queueName] = try Fixture.incarnation("e")
        let recovery = try transaction.recoveryPlan()
        XCTAssertFalse(recovery.steps.contains { if case .removeQueue = $0 { return true }; return false })
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(transaction.record))
        XCTAssertNotNil(sink.queues[Fixture.queueName])
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
    }

    /// Finding I: a *reproducible* identity is no identity. Another
    /// administrator recreating the same name with the same description would
    /// match a configuration digest; only the unrepeatable token will do.
    func testAQueueRecreatedWithIdenticalConfigurationIsNotAcceptedAsOurs() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        // Same name, same description bytes — a configuration digest would be
        // identical. The incarnation token is not.
        let recreated = try SchedulerQueueIncarnation(token: Fixture.digest("7"))
        XCTAssertNotEqual(transaction.record.queueIncarnation, recreated)
        sink.queues[Fixture.queueName] = recreated

        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueIncarnationUnverified))
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
        XCTAssertEqual(sink.queues[Fixture.queueName], recreated)
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.files[Fixture.filterPath])
    }

    func testAQueuePresentWithoutAnIncarnationIsNeverRemoved() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.queues[Fixture.queueName] = nil as SchedulerQueueIncarnation?
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueIncarnationUnverified))
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
    }

    func testRollbackRefusesAPlanNamingAnUnownedArtifactAndRemovesNothing() throws {
        var sink = try Fixture.cleanSink()
        sink.createFileFailures.insert(Fixture.filterPath)
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        XCTAssertThrowsError(try transaction.stage(using: &sink))
        let overreaching = try QueueInstallationRecoveryPlan(steps: [
            .removeFile(plan.intent.printerDescription),
            .removeFile(plan.intent.ownershipRecord),
            .removeFile(plan.intent.protectedRoot),
        ])
        XCTAssertThrowsError(try transaction.rollBack(following: overreaching, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .notOwnedByTransaction)
        }
        XCTAssertTrue(sink.removalEvents.isEmpty)
    }

    func testRecoveryIsIdempotent() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        var recovery = try Fixture.recordValidated(transaction)
        XCTAssertEqual(recovery.recover(using: &sink), .rolledBack(recovery.record))
        let afterFirstPass = sink.removalEvents
        XCTAssertEqual(recovery.recover(using: &sink), .rolledBack(recovery.record))
        XCTAssertEqual(sink.removalEvents, afterFirstPass)
        XCTAssertTrue(recovery.record.createdArtifacts.isEmpty)
    }

    func testRecoveryStopsBeforeTheFilterWhenTheQueueStateIsUnknown() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.queueQueryFails = true
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueStateUnknown))
        XCTAssertTrue(outcome.requiresManualRecovery)
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertEqual(recovery.record.createdArtifacts.count, 5)
    }

    func testAnUnverifiedQueueRemovalIsResidualAndKeepsTheFilter() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.queueRemovalWithoutEffect = true
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueRemovalUnverified))
        XCTAssertEqual(sink.removalEvents, [.removeQueue(Fixture.queueName)])
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertTrue(recovery.record.owns(.schedulerQueue))
    }

    func testRecoveryRetainsAnAlteredArtifactInsteadOfDeletingIt() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.files[Fixture.filterPath] = try ObservedFileState(
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("9")
        )
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .unexpectedArtifactState))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.filterPath)))
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertTrue(sink.queues.isEmpty)
    }

    func testAnUnreadableArtifactStopsRecoveryAsUnknown() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.fileQueryFailures.insert(Fixture.descriptionPath)
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .fileStateUnknown))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.descriptionPath)))
    }

    func testAnUnverifiedFileRemovalIsResidualNotRolledBack() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.removalsWithoutEffect.insert(Fixture.descriptionPath)
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .fileRemovalUnverified))
        XCTAssertTrue(recovery.record.owns(.file(try AbsolutePath(Fixture.descriptionPath))))
    }

    func testAFailedRemovalEffectIsResidualNotRolledBack() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.removeFileFailures.insert(Fixture.filterPath)
        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .effectFailed))
        XCTAssertFalse(outcome.isCompleted)
    }

    /// Finding O: identity alone was not enough. A canonical record reusing the
    /// caller-supplied transaction identifier with a different queue must not
    /// license deleting the journal.
    func testRecoveryRefusesAJournalThatDiffersFromTheRecord() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let sameIDDifferentQueue = try QueueInstallationOwnershipRecord(
            transactionID: transaction.record.transactionID,
            queue: PlannedSchedulerQueue(name: "SomeOtherQueue"),
            phase: .inProgress,
            files: transaction.record.files,
            createdArtifacts: []
        )
        XCTAssertEqual(sameIDDifferentQueue.transactionID, transaction.record.transactionID)
        sink.journalOverrideOnRead = sameIDDifferentQueue.canonicalText

        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .unexpectedArtifactState))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.recordPath)))
        XCTAssertNotNil(sink.files[Fixture.recordPath])
        XCTAssertFalse(sink.log.contains(.removeEmptyDirectory(Fixture.rootPath)))
    }

    /// Finding K: the journal rewrite must be conditional, or the first
    /// successful removal overwrites a foreign journal before anything reads it
    /// — which would make the journal check above unreachable in a real sink.
    func testJournalWritesAreConditionalOnTheBytesLastWritten() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let foreign = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "b", count: 32)),
            queue: transaction.record.queue, phase: .inProgress,
            files: transaction.record.files, createdArtifacts: []
        ).canonicalText
        // Something replaced the journal behind our back.
        sink.persistedRecord = foreign

        var recovery = try Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .journalConflict))
        // The foreign journal survives: the rewrite was refused, not applied.
        XCTAssertEqual(sink.persistedRecord, foreign)
        // Only the queue was removed, and nothing after the refused write.
        XCTAssertEqual(sink.removalEvents, [.removeQueue(Fixture.queueName)])
    }

    // MARK: - Recovery loaded back from the journal

    /// Finding H: a journal nothing can load back is write-only. This is the
    /// path a restart takes, and it cannot go through a plan, because a plan's
    /// preconditions refuse an existing protected root.
    func testRecoveryLoadsFromTheJournalAfterTheTransactionIsGone() throws {
        var sink = try Fixture.cleanSink()
        let (installed, _) = try Fixture.installed(&sink)
        let expected = installed.record

        // The process that wrote the journal is gone. A plan is not even
        // constructible now: the root exists.
        let intent = try Fixture.intent()
        let preconditions = QueueInstallationPreconditions.capture(for: intent, from: &sink)
        XCTAssertNotNil(preconditions.refusal)
        XCTAssertNotNil(sink.files[Fixture.rootPath])

        var recovery = try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &sink
        )
        XCTAssertEqual(recovery.record, expected)
        XCTAssertEqual(try recovery.recoveryPlan(), try QueueInstallationRecoveryPlan(record: expected))

        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(recovery.record))
        XCTAssertTrue(sink.queues.isEmpty)
        XCTAssertNil(sink.files[Fixture.rootPath])
        XCTAssertNil(sink.files[Fixture.recordPath])
        XCTAssertNotNil(sink.files[Fixture.stagingParent])
    }

    /// Finding H: a loaded recovery obeys its authority like any other.
    func testALoadedAutomaticRecoveryStillWillNotRemoveAPresentQueue() throws {
        var sink = try Fixture.cleanSink()
        _ = try Fixture.installed(&sink)
        let intent = try Fixture.intent()
        var recovery = try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .automatic, using: &sink
        )
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueOwnershipAmbiguous))
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.queues[Fixture.queueName])
    }

    func testRecoveryLoadRefusesAnUnreadableAbsentOrForeignJournal() throws {
        let intent = try Fixture.intent()

        var unreadable = try Fixture.cleanSink()
        _ = try Fixture.installed(&unreadable)
        unreadable.recordQueryFails = true
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &unreadable
        )) { XCTAssertEqual($0 as? QueueInstallationError, .effectFailed) }

        var empty = try Fixture.cleanSink()
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &empty
        )) { XCTAssertEqual($0 as? QueueInstallationError, .invalidRecord) }

        var corrupt = try Fixture.cleanSink()
        _ = try Fixture.installed(&corrupt)
        corrupt.journalOverrideOnRead = "schemaVersion=2\nnot a record\n"
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &corrupt
        )) { XCTAssertEqual($0 as? QueueInstallationError, .invalidRecord) }

        // A journal describing a record that does not live in this artifact is
        // not this artifact's journal.
        var misplaced = try Fixture.cleanSink()
        _ = try Fixture.installed(&misplaced)
        let elsewhere = try Fixture.intent(rootPath: "/Library/Printers/OtherModel")
        misplaced.journalOverrideOnRead = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: elsewhere.queue, phase: .inProgress,
            files: elsewhere.creationOrderedFiles, createdArtifacts: []
        ).canonicalText
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &misplaced
        )) { XCTAssertEqual($0 as? QueueInstallationError, .recordHasNoJournal) }
    }

    func testARecordWithoutAJournalCannotDriveRecovery() throws {
        let intent = try Fixture.intent()
        let journalless = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue, phase: .inProgress,
            files: [intent.protectedRoot], createdArtifacts: []
        )
        XCTAssertNil(journalless.journalArtifact)
        XCTAssertThrowsError(try QueueInstallationRecovery(
            resuming: journalless, authority: .recordValidated
        )) { XCTAssertEqual($0 as? QueueInstallationError, .recordHasNoJournal) }
    }

    // MARK: - Durable ownership record

    func testOwnershipRecordRoundTripsCanonically() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text), transaction.record)
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text).canonicalText, text)
        XCTAssertTrue(text.hasPrefix("schemaVersion=2\ntransactionID=\(Fixture.transactionHex)\n"))
        XCTAssertTrue(text.contains("queueIncarnation=\(Fixture.digest("1"))\n"))
        XCTAssertTrue(text.contains("queueAcquisition=exclusive-creation\n"))
        XCTAssertTrue(text.contains("pending=-\n"))
        XCTAssertTrue(text.contains("created=queue\n"))
        XCTAssertTrue(text.contains("protected-root|\(Fixture.rootPath)|0|0|0755|-\n"))
        XCTAssertTrue(text.contains("ownership-record|\(Fixture.recordPath)|0|0|0644|-\n"))
    }

    func testOwnershipRecordDecodingFailsClosed() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText

        let corrupted = [
            String(text.dropLast()),
            text + "unexpected=value\n",
            text.replacingOccurrences(of: "schemaVersion=2", with: "schemaVersion=3"),
            text.replacingOccurrences(of: "phase=completed", with: "phase=almost"),
            text.replacingOccurrences(of: "|0755|", with: "|0777|"),
            text.replacingOccurrences(of: "protected-root", with: "mystery-kind"),
            text.replacingOccurrences(of: Fixture.digest("b"), with: "short"),
            text.replacingOccurrences(of: "created=queue\n", with: "created=queue\ncreated=queue\n"),
            text.replacingOccurrences(of: "created=queue", with: "created=/Library/Printers/unplanned"),
            text.replacingOccurrences(of: "queueIncarnation=", with: "queueincarnation="),
            text.replacingOccurrences(of: "queueAcquisition=exclusive-creation", with: "queueAcquisition=maybe"),
            text.replacingOccurrences(of: "pending=-", with: "pending=/Library/Printers/unplanned"),
        ]
        for candidate in corrupted {
            XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(candidate), candidate)
        }
    }

    func testOwnershipRecordDecodingRejectsNonCanonicalIntegers() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText
        XCTAssertTrue(text.contains("|0|0|0755|"))

        for spelling in ["|+0|0|0755|", "|-0|0|0755|", "|00|0|0755|", "|0|+0|0755|", "|0| 0|0755|"] {
            let candidate = text.replacingOccurrences(of: "|0|0|0755|", with: spelling)
            XCTAssertNotEqual(candidate, text)
            XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(candidate), spelling) {
                XCTAssertEqual($0 as? QueueInstallationError, .invalidRecord)
            }
        }
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text).canonicalText, text)
    }

    func testARecordPhaseMustAgreeWithWhatItSaysItCreated() throws {
        let intent = try Fixture.intent()
        let incarnation = try Fixture.incarnation()
        let id = try QueueInstallationTransactionID(hex: Fixture.transactionHex)
        let allFiles = intent.creationOrderedFiles
        let everyFile = allFiles.map { QueueInstallationArtifactID.file($0.path) }

        func build(
            phase: QueueInstallationRecordedPhase,
            incarnation: SchedulerQueueIncarnation? = nil,
            acquisition: SchedulerQueueAcquisition? = nil,
            pending: QueueInstallationArtifactID? = nil,
            created: [QueueInstallationArtifactID]
        ) throws -> QueueInstallationOwnershipRecord {
            try QueueInstallationOwnershipRecord(
                transactionID: id, queue: intent.queue,
                queueIncarnation: incarnation, queueAcquisition: acquisition,
                phase: phase, pendingArtifact: pending,
                files: allFiles, createdArtifacts: created
            )
        }

        // Completed without the queue.
        XCTAssertThrowsError(try build(phase: .completed, created: everyFile)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        // Completed with the queue but no incarnation for it.
        XCTAssertThrowsError(try build(phase: .completed, created: everyFile + [.schedulerQueue])) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        // Completed on an acquisition that cannot prove it created the name.
        XCTAssertThrowsError(try build(
            phase: .completed, incarnation: incarnation, acquisition: .ambiguousCreateOrModify,
            created: everyFile + [.schedulerQueue]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
        // Completed while some planned artifact was never created.
        XCTAssertThrowsError(try build(
            phase: .completed, incarnation: incarnation, acquisition: .exclusiveCreation,
            created: Array(everyFile.dropLast()) + [.schedulerQueue]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
        // Completed with something still pending.
        XCTAssertThrowsError(try build(
            phase: .completed, incarnation: incarnation, acquisition: .exclusiveCreation,
            pending: .schedulerQueue, created: everyFile
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
        // Rolled back while still listing live artifacts, or with a pending step.
        XCTAssertThrowsError(try build(phase: .rolledBack, created: everyFile)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        XCTAssertThrowsError(try build(phase: .rolledBack, pending: .schedulerQueue, created: [])) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        // An incarnation for a queue that was never created, or one without its
        // acquisition.
        XCTAssertThrowsError(try build(
            phase: .inProgress, incarnation: incarnation, acquisition: .exclusiveCreation,
            created: everyFile
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
        XCTAssertThrowsError(try build(
            phase: .inProgress, incarnation: incarnation, created: everyFile + [.schedulerQueue]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }

        XCTAssertNoThrow(try build(
            phase: .completed, incarnation: incarnation, acquisition: .exclusiveCreation,
            created: everyFile + [.schedulerQueue]
        ))
        XCTAssertNoThrow(try build(phase: .rolledBack, created: []))
        XCTAssertNoThrow(try build(phase: .residual, created: everyFile))
    }

    /// Finding P: a count proves presence, not order, and recovery reverses the
    /// order it is given.
    func testACompletedRecordRequiresTheExactCreationOrder() throws {
        let intent = try Fixture.intent()
        let everyFile = intent.creationOrderedFiles.map { QueueInstallationArtifactID.file($0.path) }
        // The full inventory, with the filter and the description swapped.
        var permuted = everyFile
        permuted.swapAt(2, 3)
        XCTAssertEqual(Set(permuted), Set(everyFile))

        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue,
            queueIncarnation: Fixture.incarnation(), queueAcquisition: .exclusiveCreation,
            phase: .completed,
            files: intent.creationOrderedFiles,
            createdArtifacts: permuted + [.schedulerQueue]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }

        // The queue must also be last, not merely present.
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue,
            queueIncarnation: Fixture.incarnation(), queueAcquisition: .exclusiveCreation,
            phase: .completed,
            files: intent.creationOrderedFiles,
            createdArtifacts: [.schedulerQueue] + everyFile
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
    }

    func testARecordCannotClaimAnArtifactItDoesNotPlan() throws {
        let intent = try Fixture.intent()
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue, phase: .inProgress,
            files: [intent.protectedRoot],
            createdArtifacts: [.file(try AbsolutePath(Fixture.filterPath))]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .notOwnedByTransaction) }

        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue, phase: .inProgress,
            pendingArtifact: .file(try AbsolutePath(Fixture.filterPath)),
            files: [intent.protectedRoot], createdArtifacts: []
        )) { XCTAssertEqual($0 as? QueueInstallationError, .notOwnedByTransaction) }

        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue, phase: .inProgress,
            files: [intent.protectedRoot, intent.protectedRoot], createdArtifacts: []
        )) { XCTAssertEqual($0 as? QueueInstallationError, .duplicateArtifactPath) }
    }

    func testTransactionIDRejectsAnythingButThirtyTwoLowercaseHexDigits() throws {
        XCTAssertNoThrow(try QueueInstallationTransactionID(hex: Fixture.transactionHex))
        for rejected in [
            "", "0123456789ABCDEF0123456789ABCDEF", "0123456789abcdef", Fixture.transactionHex + "0",
            "0123456789abcdef0123456789abcdeg",
        ] {
            XCTAssertThrowsError(try QueueInstallationTransactionID(hex: rejected), rejected) {
                XCTAssertEqual($0 as? QueueInstallationError, .invalidTransactionID)
            }
        }
    }
}
