import XCTest
@testable import LabelCore

/// An inert, in-memory stand-in for the effect seam. It never touches a
/// filesystem, a scheduler, a process or a device: it is a dictionary, a set and
/// a log. Nothing in this file may be promoted to a real implementation.
private struct InertInstallationSink: QueueInstallationEffectSink {
    enum Event: Equatable {
        case observeQueue(String)
        case observeFile(String)
        case createFile(String)
        case createQueue(String)
        case persistRecord(String)
        case readRecord(String)
        case removeQueue(String)
        case removeFile(String)
    }

    enum Failure: Error { case refused }

    var files: [String: ObservedFileState] = [:]
    /// Queues this stand-in holds, each with the identity it would report.
    var queues: [String: SchedulerQueueIdentity] = [:]
    /// Queues present but whose identity the seam cannot establish.
    var queuesWithoutIdentity: Set<String> = []
    var persistedRecord: String?
    /// What a read of the journal returns instead of what was written. This is
    /// the window between the transaction's last write and its next read.
    var journalOverrideOnRead: String?
    var queueQueryFails = false
    var recordQueryFails = false
    var fileQueryFailures: Set<String> = []
    var createFileFailures: Set<String> = []
    var createQueueFails = false
    var persistRecordFails = false
    var removeQueueFails = false
    var removeFileFailures: Set<String> = []
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
            case .removeQueue, .removeFile: true
            default: false
            }
        }
    }

    mutating func observeQueue(_ queue: PlannedSchedulerQueue) -> SchedulerQueueObservation {
        log.append(.observeQueue(queue.name))
        if queueQueryFails { return .queryFailed }
        if queuesWithoutIdentity.contains(queue.name) { return .present(nil) }
        guard let identity = queues[queue.name] else { return .confirmedAbsent }
        return .present(identity)
    }

    mutating func observeFile(at path: AbsolutePath) -> FileArtifactObservation {
        log.append(.observeFile(path.value))
        if fileQueryFailures.contains(path.value) { return .queryFailed }
        guard let state = files[path.value] else { return .confirmedAbsent }
        return .present(state)
    }

    mutating func createFile(_ artifact: PlannedFileArtifact) throws {
        log.append(.createFile(artifact.path.value))
        if createFileFailures.contains(artifact.path.value) { throw Failure.refused }
        if let tampered = tamperOnCreate[artifact.path.value] {
            files[artifact.path.value] = tampered
            return
        }
        files[artifact.path.value] = try ObservedFileState(
            kind: artifact.expectedFileKind,
            uid: artifact.ownership.uid,
            gid: artifact.ownership.gid,
            modeBits: artifact.mode.rawValue,
            contentSHA256: artifact.contentSHA256
        )
    }

    mutating func createQueue(_ queue: PlannedSchedulerQueue, describedBy description: PlannedFileArtifact) throws {
        log.append(.createQueue(queue.name))
        if createQueueFails { throw Failure.refused }
        // A stand-in for what a real seam would derive from the queue's bound
        // configuration. It is an observation, never something the model derives.
        queues[queue.name] = try SchedulerQueueIdentity(sha256: description.contentSHA256 ?? Fixture.digest("c"))
    }

    mutating func persistOwnershipRecord(_ text: String, at artifact: PlannedFileArtifact) throws {
        log.append(.persistRecord(artifact.path.value))
        if persistRecordFails { throw Failure.refused }
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

    mutating func removeQueue(_ queue: PlannedSchedulerQueue) throws {
        log.append(.removeQueue(queue.name))
        if removeQueueFails { throw Failure.refused }
        if queueRemovalWithoutEffect { return }
        queues.removeValue(forKey: queue.name)
        queuesWithoutIdentity.remove(queue.name)
    }

    mutating func removeFile(at path: AbsolutePath) throws {
        log.append(.removeFile(path.value))
        if removeFileFailures.contains(path.value) { throw Failure.refused }
        if removalsWithoutEffect.contains(path.value) { return }
        files.removeValue(forKey: path.value)
        if path.value == Fixture.recordPath { persistedRecord = nil }
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

    static func intent(rootPath: String = rootPath) throws -> QueueInstallationIntent {
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

    /// A staging parent that admits planning: a real root-owned directory that
    /// is neither group- nor world-writable.
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
        transactionHex hex: String = transactionHex
    ) throws -> QueueInstallationPlan {
        let intent = try overriding ?? intent()
        let preconditions = QueueInstallationPreconditions.capture(for: intent, from: &sink)
        return try QueueInstallationPlan(
            transactionID: QueueInstallationTransactionID(hex: hex),
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
        // A deeper path is not an immediate child, so recovery never has to
        // recurse into a directory it did not create component by component.
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
        // A fixed-content artifact must declare the digest validation compares against.
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .filterExecutable, path: path, mode: POSIXMode(0o755), contentSHA256: nil
        )) { XCTAssertEqual($0 as? QueueInstallationError, .invalidDigest) }
        // A directory has no content to digest.
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .protectedRoot, path: path, mode: POSIXMode(0o755), contentSHA256: Fixture.digest("a")
        )) { XCTAssertEqual($0 as? QueueInstallationError, .artifactKindMismatch) }
        // Neither does the journal, whose bytes change as the transaction runs.
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .ownershipRecord, path: path, mode: POSIXMode(0o644), contentSHA256: Fixture.digest("a")
        )) { XCTAssertEqual($0 as? QueueInstallationError, .artifactKindMismatch) }
        // Mode is fixed per kind rather than caller-chosen.
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .filterExecutable, path: path, mode: POSIXMode(0o644), contentSHA256: Fixture.digest("b")
        )) { XCTAssertEqual($0 as? QueueInstallationError, .artifactKindMismatch) }
        // Staging is root-owned; nothing else may be planned.
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
        // The journal is not placed with createFile; it is written and rewritten.
        XCTAssertEqual(
            intent.directlyCreatedFiles.map(\.kind),
            [.protectedRoot, .filterExecutable, .printerDescription]
        )
    }

    // MARK: - Preconditions gate planning

    func testPlanRefusesAPreExistingQueueRatherThanAdoptingIt() throws {
        var sink = try Fixture.cleanSink()
        sink.queues[Fixture.queueName] = try SchedulerQueueIdentity(sha256: Fixture.digest("e"))
        XCTAssertThrowsError(try Fixture.plan(with: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.queueAlreadyPresent))
        }
        // Refusal happens before any plan exists, so nothing was created.
        XCTAssertTrue(sink.log.allSatisfy {
            switch $0 {
            case .observeQueue, .observeFile: true
            default: false
            }
        })
    }

    func testAFailedQueryIsNeverReadAsAbsence() throws {
        XCTAssertFalse(SchedulerQueueObservation.queryFailed.isConfirmedAbsent)
        XCTAssertFalse(SchedulerQueueObservation.queryFailed.isConfirmedPresent)
        XCTAssertFalse(FileArtifactObservation.queryFailed.isConfirmedAbsent)
        // A present queue with no establishable identity is present, not absent,
        // and carries no identity to act on.
        XCTAssertTrue(SchedulerQueueObservation.present(nil).isConfirmedPresent)
        XCTAssertNil(SchedulerQueueObservation.present(nil).identity)

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

        // A directory whose mode could not be read is unknown, not acceptable.
        var partial = try Fixture.cleanSink()
        partial.files[Fixture.stagingParent] = try ObservedFileState(kind: .directory, uid: 0, gid: 0)
        XCTAssertThrowsError(try Fixture.plan(with: &partial)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.stagingParentStateUnknown))
        }
    }

    // MARK: - The ordered transaction

    func testCompleteInstallationRecordsEveryArtifactInCreationOrder() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, outcome) = try Fixture.installed(&sink)
        XCTAssertTrue(outcome.isCompleted)
        XCTAssertFalse(outcome.requiresManualRecovery)
        XCTAssertEqual(transaction.phase, .completed)
        XCTAssertEqual(transaction.record.phase, .completed)
        XCTAssertEqual(
            transaction.record.createdArtifacts,
            [
                .file(try AbsolutePath(Fixture.rootPath)),
                .file(try AbsolutePath(Fixture.recordPath)),
                .file(try AbsolutePath(Fixture.filterPath)),
                .file(try AbsolutePath(Fixture.descriptionPath)),
                .schedulerQueue,
            ]
        )
        XCTAssertEqual(transaction.record.createdArtifacts, transaction.plan.inventory)
        XCTAssertNotNil(transaction.record.queueIdentity)
        // The filter exists before the queue that would name it.
        let created = sink.log.compactMap { event -> String? in
            switch event {
            case let .createFile(path): path
            case let .createQueue(name): "queue:" + name
            default: nil
            }
        }
        XCTAssertEqual(created.last, "queue:" + Fixture.queueName)
        XCTAssertTrue(created.firstIndex(of: Fixture.filterPath)! < created.count - 1)
    }

    /// Finding D: the durable record must name each artifact as it is taken, not
    /// only in a value that dies with the process.
    func testTheDurableRecordNamesEveryArtifactAsItIsTaken() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)

        let afterStaging = try XCTUnwrap(sink.persistedRecord)
        let stagedRecord = try QueueInstallationOwnershipRecord.decode(afterStaging)
        XCTAssertEqual(stagedRecord, transaction.record)
        XCTAssertEqual(stagedRecord.createdArtifacts, [
            .file(try AbsolutePath(Fixture.rootPath)),
            .file(try AbsolutePath(Fixture.recordPath)),
            .file(try AbsolutePath(Fixture.filterPath)),
            .file(try AbsolutePath(Fixture.descriptionPath)),
        ])

        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        let afterQueue = try QueueInstallationOwnershipRecord.decode(try XCTUnwrap(sink.persistedRecord))
        XCTAssertTrue(afterQueue.owns(.schedulerQueue))
        XCTAssertNotNil(afterQueue.queueIdentity)
        XCTAssertEqual(afterQueue, transaction.record)

        // A recovery driven from the durable bytes alone reaches the same plan.
        XCTAssertEqual(
            try QueueInstallationRecoveryPlan(record: afterQueue),
            try transaction.recoveryPlan()
        )
    }

    /// Finding D: the record is journalled as recovery shortens it, so an
    /// interruption mid-rollback still leaves bytes naming exactly what is left.
    func testTheDurableRecordShrinksAsRecoveryProceeds() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.removalsWithoutEffect.insert(Fixture.filterPath)
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .fileRemovalUnverified))
        let durable = try QueueInstallationOwnershipRecord.decode(try XCTUnwrap(sink.persistedRecord))
        XCTAssertFalse(durable.owns(.schedulerQueue))
        XCTAssertFalse(durable.owns(.file(try AbsolutePath(Fixture.descriptionPath))))
        XCTAssertTrue(durable.owns(.file(try AbsolutePath(Fixture.filterPath))))
        XCTAssertEqual(durable.phase, .residual)
    }

    func testValidationAfterStagingCatchesATOCTOUSubstitution() throws {
        var sink = try Fixture.cleanSink()
        // Staging succeeds; the bytes at the filter path are not the planned ones
        // by the time validation reads them back.
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
        // No queue was created, and the transaction never reached validation.
        XCTAssertEqual(transaction.phase, .staged)
        XCTAssertTrue(sink.queues.isEmpty)
        XCTAssertFalse(transaction.record.owns(.schedulerQueue))
    }

    /// Finding D: the journal is validated by reading it back, since its bytes
    /// cannot be pinned by a digest fixed before the transaction ran.
    func testValidationReadsTheDurableRecordBackAndRejectsADivergentOne() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        // The journal on disk no longer describes this transaction.
        sink.persistedRecord = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "c", count: 32)),
            queue: plan.intent.queue,
            phase: .inProgress,
            files: plan.intent.creationOrderedFiles,
            createdArtifacts: []
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

        // An unreadable path is its own failure, never a pass.
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

    func testStepsCannotRunOutOfOrder() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        // Completion before a queue exists is not a phase this type can be in.
        XCTAssertThrowsError(try transaction.complete(using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
        let staged = try transaction.stage(using: &sink)
        XCTAssertThrowsError(try transaction.stage(using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        // Validating twice is also out of order: a token authorizes one step.
        XCTAssertThrowsError(try transaction.validateStagedArtifacts(staged, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
    }

    func testATokenFromAnotherTransactionAuthorizesNothing() throws {
        var firstSink = try Fixture.cleanSink()
        let firstPlan = try Fixture.plan(with: &firstSink)
        var first = try QueueInstallationTransaction(plan: firstPlan)
        let firstStaged = try first.stage(using: &firstSink)
        let firstValidated = try first.validateStagedArtifacts(firstStaged, using: &firstSink)

        var secondSink = try Fixture.cleanSink()
        let secondPlan = try Fixture.plan(
            with: &secondSink, transactionHex: String(repeating: "f", count: 32)
        )
        var second = try QueueInstallationTransaction(plan: secondPlan)
        XCTAssertThrowsError(try second.validateStagedArtifacts(firstStaged, using: &secondSink)) {
            // Out of phase first; staging has not run for this transaction.
            XCTAssertEqual($0 as? QueueInstallationError, .invalidPhase)
        }
        _ = try second.stage(using: &secondSink)
        XCTAssertThrowsError(try second.validateStagedArtifacts(firstStaged, using: &secondSink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .transactionMismatch)
        }
        // A validation token from elsewhere cannot authorize this queue either.
        var third = try QueueInstallationTransaction(plan: secondPlan)
        var thirdSink = try Fixture.cleanSink()
        let thirdStaged = try third.stage(using: &thirdSink)
        _ = try third.validateStagedArtifacts(thirdStaged, using: &thirdSink)
        XCTAssertThrowsError(try third.createQueue(authorizedBy: firstValidated, using: &thirdSink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .transactionMismatch)
        }
        XCTAssertTrue(thirdSink.queues.isEmpty)
    }

    /// Finding E: a transaction identifier is caller-supplied, so two
    /// transactions can share one. A token must therefore also name the intent
    /// it covers, or the second transaction validates the first's paths and then
    /// creates its own queue having checked none of its own files.
    func testATokenCannotCrossBetweenTransactionsSharingAnIdentifier() throws {
        var firstSink = try Fixture.cleanSink()
        let firstPlan = try Fixture.plan(with: &firstSink)
        var first = try QueueInstallationTransaction(plan: firstPlan)
        let firstStaged = try first.stage(using: &firstSink)
        let firstValidated = try first.validateStagedArtifacts(firstStaged, using: &firstSink)

        // Same caller-supplied identifier, entirely different artifacts.
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
        // Another administrator took the name between planning and creation.
        sink.queues[Fixture.queueName] = try SchedulerQueueIdentity(sha256: Fixture.digest("e"))
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.queueAlreadyPresent))
        }
        XCTAssertFalse(transaction.record.owns(.schedulerQueue))
        XCTAssertFalse(sink.log.contains(.createQueue(Fixture.queueName)))
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
        XCTAssertTrue(outcome.requiresManualRecovery)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueStateUnknownAfterCreation))
        XCTAssertEqual(transaction.record.phase, .residual)
        // The record still names everything, so recovery remains finite.
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

    /// Finding B: completion is about this transaction's own queue. A queue of
    /// the right name whose identity cannot be established is not it.
    func testCompletionRequiresTheIdentityOfTheQueueItCreated() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        // The queue is present, but the seam can no longer say which queue it is.
        sink.queuesWithoutIdentity.insert(Fixture.queueName)
        let outcome = try transaction.complete(using: &sink)
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueIdentityUnverified))
    }

    // MARK: - Recovery ordering

    func testRecoveryPlanRefusesAnyFileBeforeTheQueue() throws {
        let intent = try Fixture.intent()
        let queueStep = QueueInstallationRecoveryPlan.Step.removeQueue(intent.queue)
        let filterStep = QueueInstallationRecoveryPlan.Step.removeFile(intent.filter)
        let rootStep = QueueInstallationRecoveryPlan.Step.removeFile(intent.protectedRoot)

        XCTAssertNoThrow(try QueueInstallationRecoveryPlan(steps: [queueStep, filterStep, rootStep]))
        XCTAssertThrowsError(try QueueInstallationRecoveryPlan(steps: [filterStep, queueStep, rootStep])) {
            XCTAssertEqual($0 as? QueueInstallationError, .recoveryOrderingViolation)
        }
        // The protected root is removed last, after everything inside it.
        XCTAssertThrowsError(try QueueInstallationRecoveryPlan(steps: [queueStep, rootStep, filterStep])) {
            XCTAssertEqual($0 as? QueueInstallationError, .recoveryOrderingViolation)
        }
        XCTAssertThrowsError(try QueueInstallationRecoveryPlan(steps: [queueStep, filterStep, filterStep])) {
            XCTAssertEqual($0 as? QueueInstallationError, .duplicateArtifactPath)
        }
    }

    func testRollbackRemovesTheQueueBeforeTheFilter() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(transaction.record))
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertEqual(
            sink.removalEvents,
            [
                .removeQueue(Fixture.queueName),
                .removeFile(Fixture.descriptionPath),
                .removeFile(Fixture.filterPath),
                .removeFile(Fixture.recordPath),
                .removeFile(Fixture.rootPath),
            ]
        )
        XCTAssertTrue(sink.queues.isEmpty)
        XCTAssertNil(sink.files[Fixture.rootPath])
        // The staging parent was never this transaction's to remove.
        XCTAssertNotNil(sink.files[Fixture.stagingParent])
        XCTAssertTrue(transaction.record.createdArtifacts.isEmpty)
    }

    /// Finding A: an empty recovery plan removes nothing, so it must never be
    /// accepted as a rollback of a transaction that still owns artifacts.
    func testRollbackRefusesAnEmptyRecoveryPlanInsteadOfClaimingSuccess() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        let empty = try QueueInstallationRecoveryPlan(steps: [])
        XCTAssertThrowsError(try transaction.rollBack(following: empty, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .incompleteRecoveryPlan)
        }
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertEqual(transaction.record.createdArtifacts.count, 5)
        XCTAssertNotEqual(transaction.phase, .rolledBack)
        XCTAssertNotEqual(transaction.record.phase, .rolledBack)
        XCTAssertTrue(sink.queues.keys.contains(Fixture.queueName))
    }

    /// Finding A: a plan that drops only the queue would remove the filter and
    /// leave a live queue pointing at nothing, then report success.
    func testRollbackRefusesAPlanThatOmitsTheQueue() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        let canonical = try transaction.recoveryPlan()
        let withoutQueue = try QueueInstallationRecoveryPlan(steps: Array(canonical.steps.dropFirst()))
        XCTAssertThrowsError(try transaction.rollBack(following: withoutQueue, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .incompleteRecoveryPlan)
        }
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertTrue(sink.queues.keys.contains(Fixture.queueName))
    }

    func testRollbackAfterPartialStagingTouchesNoQueueAndRemovesOnlyWhatExists() throws {
        var sink = try Fixture.cleanSink()
        sink.createFileFailures.insert(Fixture.filterPath)
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        XCTAssertThrowsError(try transaction.stage(using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .effectFailed)
        }
        XCTAssertEqual(transaction.record.createdArtifacts, [
            .file(try AbsolutePath(Fixture.rootPath)),
            .file(try AbsolutePath(Fixture.recordPath)),
        ])
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(transaction.record))
        XCTAssertEqual(
            sink.removalEvents,
            [.removeFile(Fixture.recordPath), .removeFile(Fixture.rootPath)]
        )
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
    }

    func testRollbackNeverRemovesAQueueTheTransactionDidNotCreate() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        _ = try transaction.stage(using: &sink)
        // Someone else creates a queue of the same name while this transaction
        // is mid-flight. It is not in the record, so recovery never names it.
        sink.queues[Fixture.queueName] = try SchedulerQueueIdentity(sha256: Fixture.digest("e"))
        let recovery = try transaction.recoveryPlan()
        XCTAssertFalse(recovery.steps.contains { if case .removeQueue = $0 { return true }; return false })
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(transaction.record))
        XCTAssertTrue(sink.queues.keys.contains(Fixture.queueName))
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
    }

    /// Finding B: a name is not an identity. If this transaction's queue was
    /// removed and another administrator created one with the same name,
    /// rollback must not destroy theirs.
    func testRollbackRefusesToRemoveAQueueItCannotIdentifyAsItsOwn() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        let foreign = try SchedulerQueueIdentity(sha256: Fixture.digest("e"))
        XCTAssertNotEqual(transaction.record.queueIdentity, foreign)
        sink.queues[Fixture.queueName] = foreign

        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueIdentityUnverified))
        XCTAssertTrue(outcome.requiresManualRecovery)
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
        XCTAssertEqual(sink.queues[Fixture.queueName], foreign)
        // Nothing the queue depends on was removed either.
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.files[Fixture.filterPath])
    }

    /// Finding B: an identity that cannot be established is unknown, and unknown
    /// must not become a deletion.
    func testAQueuePresentWithoutAnEstablishedIdentityIsNeverRemoved() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.queues.removeValue(forKey: Fixture.queueName)
        sink.queuesWithoutIdentity.insert(Fixture.queueName)

        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueIdentityUnverified))
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
        XCTAssertTrue(sink.queuesWithoutIdentity.contains(Fixture.queueName))
    }

    /// Finding G: the journal's bytes are the one thing no planned digest can
    /// pin, so metadata alone must not license deleting it.
    func testRollbackRefusesToRemoveAJournalThatIsNoLongerItsOwn() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        // Same path, same ownership and mode, but by the time rollback reads the
        // journal it is another transaction's.
        sink.journalOverrideOnRead = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "d", count: 32)),
            queue: transaction.plan.intent.queue,
            phase: .inProgress,
            files: transaction.plan.intent.creationOrderedFiles,
            createdArtifacts: []
        ).canonicalText
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .unexpectedArtifactState))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.recordPath)))
        XCTAssertNotNil(sink.files[Fixture.recordPath])
        // The queue and the artifacts ahead of it in the order were still removed.
        XCTAssertTrue(sink.log.contains(.removeFile(Fixture.filterPath)))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.rootPath)))
    }

    func testRollbackRefusesAPlanNamingAnUnownedArtifactAndRemovesNothing() throws {
        var sink = try Fixture.cleanSink()
        sink.createFileFailures.insert(Fixture.filterPath)
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        XCTAssertThrowsError(try transaction.stage(using: &sink))
        // A well-ordered recovery plan that names the filter, which this
        // transaction never managed to create.
        let overreaching = try QueueInstallationRecoveryPlan(steps: [
            .removeFile(plan.intent.filter),
            .removeFile(plan.intent.ownershipRecord),
            .removeFile(plan.intent.protectedRoot),
        ])
        XCTAssertThrowsError(try transaction.rollBack(following: overreaching, using: &sink)) {
            XCTAssertEqual($0 as? QueueInstallationError, .notOwnedByTransaction)
        }
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertEqual(transaction.record.createdArtifacts.count, 2)
    }

    func testRollbackIsIdempotent() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        XCTAssertEqual(transaction.rollBack(using: &sink), .rolledBack(transaction.record))
        let afterFirstPass = sink.removalEvents
        XCTAssertEqual(transaction.rollBack(using: &sink), .rolledBack(transaction.record))
        XCTAssertEqual(sink.removalEvents, afterFirstPass)
        XCTAssertTrue(transaction.record.createdArtifacts.isEmpty)
    }

    func testRollbackStopsBeforeTheFilterWhenTheQueueStateIsUnknown() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.queueQueryFails = true
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueStateUnknown))
        XCTAssertTrue(outcome.requiresManualRecovery)
        XCTAssertTrue(sink.removalEvents.isEmpty)
        // Every artifact and the whole record survive for a finite manual recovery.
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertEqual(transaction.record.createdArtifacts.count, 5)
    }

    func testAnUnverifiedQueueRemovalIsResidualAndKeepsTheFilter() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.queueRemovalWithoutEffect = true
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueRemovalUnverified))
        XCTAssertEqual(sink.removalEvents, [.removeQueue(Fixture.queueName)])
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertTrue(transaction.record.owns(.schedulerQueue))
    }

    func testRollbackRetainsAnAlteredArtifactInsteadOfDeletingIt() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.files[Fixture.filterPath] = try ObservedFileState(
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("9")
        )
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .unexpectedArtifactState))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.filterPath)))
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        // The queue in front of it is already gone, which is the point of the
        // queue-first ordering.
        XCTAssertTrue(sink.queues.isEmpty)
    }

    func testAnUnreadableArtifactStopsRollbackAsUnknown() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.fileQueryFailures.insert(Fixture.descriptionPath)
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .fileStateUnknown))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.descriptionPath)))
    }

    func testAnUnverifiedFileRemovalIsResidualNotRolledBack() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.removalsWithoutEffect.insert(Fixture.descriptionPath)
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .fileRemovalUnverified))
        XCTAssertTrue(transaction.record.owns(.file(try AbsolutePath(Fixture.descriptionPath))))
    }

    func testAFailedRemovalEffectIsResidualNotRolledBack() throws {
        var sink = try Fixture.cleanSink()
        var (transaction, _) = try Fixture.installed(&sink)
        sink.removeFileFailures.insert(Fixture.filterPath)
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .residual(transaction.record, .effectFailed))
        XCTAssertFalse(outcome.isCompleted)
    }

    // MARK: - Durable ownership record

    func testOwnershipRecordRoundTripsCanonically() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text), transaction.record)
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text).canonicalText, text)
        XCTAssertTrue(text.hasPrefix("schemaVersion=1\ntransactionID=\(Fixture.transactionHex)\n"))
        XCTAssertTrue(text.contains("queueIdentity=\(Fixture.digest("c"))\n"))
        XCTAssertTrue(text.contains("created=queue\n"))
        XCTAssertTrue(text.contains("|0755|"))
        // Neither the directory nor the journal records a content digest.
        XCTAssertTrue(text.contains("protected-root|\(Fixture.rootPath)|0|0|0755|-\n"))
        XCTAssertTrue(text.contains("ownership-record|\(Fixture.recordPath)|0|0|0644|-\n"))
    }

    func testOwnershipRecordDecodingFailsClosed() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText

        let corrupted = [
            String(text.dropLast()),                                    // no trailing newline
            text + "unexpected=value\n",                                // unknown trailing key
            text.replacingOccurrences(of: "schemaVersion=1", with: "schemaVersion=2"),
            text.replacingOccurrences(of: "phase=completed", with: "phase=almost"),
            text.replacingOccurrences(of: "|0755|", with: "|0777|"),    // group/world writable
            text.replacingOccurrences(of: "protected-root", with: "mystery-kind"),
            text.replacingOccurrences(of: Fixture.digest("b"), with: "short"),
            text.replacingOccurrences(of: "created=queue\n", with: "created=queue\ncreated=queue\n"),
            text.replacingOccurrences(of: "created=queue", with: "created=/Library/Printers/unplanned"),
            text.replacingOccurrences(of: "queueIdentity=", with: "queueidentity="),
        ]
        for candidate in corrupted {
            XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(candidate), candidate)
        }
    }

    /// Finding C: `Int(_: String)` accepts `+0`, `-0` and `00`, each of which
    /// re-encodes to `0`. That would give one record several byte spellings and
    /// defeat comparing records by their bytes.
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
        // And the general rule the canonical grammar exists to guarantee.
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text).canonicalText, text)
    }

    /// Finding F: a phase that contradicts the artifact list would misreport the
    /// transaction's state to recovery or to a reader.
    func testARecordPhaseMustAgreeWithWhatItSaysItCreated() throws {
        let intent = try Fixture.intent()
        let identity = try SchedulerQueueIdentity(sha256: Fixture.digest("c"))
        let id = try QueueInstallationTransactionID(hex: Fixture.transactionHex)
        let allFiles = intent.creationOrderedFiles
        let everyFile = allFiles.map { QueueInstallationArtifactID.file($0.path) }

        func build(
            phase: QueueInstallationRecordedPhase,
            identity: SchedulerQueueIdentity?,
            created: [QueueInstallationArtifactID]
        ) throws -> QueueInstallationOwnershipRecord {
            try QueueInstallationOwnershipRecord(
                transactionID: id, queue: intent.queue, queueIdentity: identity,
                phase: phase, files: allFiles, createdArtifacts: created
            )
        }

        // Completed without the queue.
        XCTAssertThrowsError(try build(phase: .completed, identity: nil, created: everyFile)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        // Completed with the queue but no identity for it.
        XCTAssertThrowsError(
            try build(phase: .completed, identity: nil, created: everyFile + [.schedulerQueue])
        ) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
        // Completed while some planned artifact was never created.
        XCTAssertThrowsError(try build(
            phase: .completed, identity: identity,
            created: Array(everyFile.dropLast()) + [.schedulerQueue]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
        // Rolled back while still listing live artifacts.
        XCTAssertThrowsError(try build(phase: .rolledBack, identity: nil, created: everyFile)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        // An identity for a queue that was never created.
        XCTAssertThrowsError(try build(phase: .inProgress, identity: identity, created: everyFile)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        XCTAssertNoThrow(
            try build(phase: .completed, identity: identity, created: everyFile + [.schedulerQueue])
        )
        XCTAssertNoThrow(try build(phase: .rolledBack, identity: nil, created: []))
        // Residual places no requirement: it exists to describe a state nobody
        // can vouch for.
        XCTAssertNoThrow(try build(phase: .residual, identity: nil, created: everyFile))
    }

    /// Finding F: the same rule must hold for a record that arrives as bytes.
    func testDecodingRejectsARecordWhosePhaseContradictsItsArtifacts() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText
        // Claim completion while dropping the queue from the created list.
        let withoutQueue = text.replacingOccurrences(of: "created=queue\n", with: "")
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(withoutQueue)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        // Claim a completed rollback while every artifact is still listed.
        let rolledBack = text.replacingOccurrences(of: "phase=completed", with: "phase=rolled-back")
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(rolledBack)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
    }

    func testARecordCannotClaimAnArtifactItDoesNotPlan() throws {
        let intent = try Fixture.intent()
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue,
            phase: .inProgress,
            files: [intent.protectedRoot],
            createdArtifacts: [.file(try AbsolutePath(Fixture.filterPath))]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .notOwnedByTransaction) }

        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            queue: intent.queue,
            phase: .inProgress,
            files: [intent.protectedRoot, intent.protectedRoot],
            createdArtifacts: []
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
