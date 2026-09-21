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
        case removeQueue(String)
        case removeFile(String)
    }

    enum Failure: Error { case refused }

    var files: [String: ObservedFileState] = [:]
    var queues: Set<String> = []
    var queueQueryFails = false
    var fileQueryFailures: Set<String> = []
    var createFileFailures: Set<String> = []
    var createQueueFails = false
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
        return queues.contains(queue.name) ? .present : .confirmedAbsent
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
        queues.insert(queue.name)
    }

    mutating func removeQueue(_ queue: PlannedSchedulerQueue) throws {
        log.append(.removeQueue(queue.name))
        if removeQueueFails { throw Failure.refused }
        if queueRemovalWithoutEffect { return }
        queues.remove(queue.name)
    }

    mutating func removeFile(at path: AbsolutePath) throws {
        log.append(.removeFile(path.value))
        if removeFileFailures.contains(path.value) { throw Failure.refused }
        if removalsWithoutEffect.contains(path.value) { return }
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

    static func intent() throws -> QueueInstallationIntent {
        try QueueInstallationIntent(
            queue: PlannedSchedulerQueue(name: queueName),
            protectedRoot: PlannedFileArtifact(
                kind: .protectedRoot, path: AbsolutePath(rootPath),
                mode: POSIXMode(0o755), contentSHA256: nil
            ),
            ownershipRecord: PlannedFileArtifact(
                kind: .ownershipRecord, path: AbsolutePath(recordPath),
                mode: POSIXMode(0o644), contentSHA256: digest("a")
            ),
            filter: PlannedFileArtifact(
                kind: .filterExecutable, path: AbsolutePath(filterPath),
                mode: POSIXMode(0o755), contentSHA256: digest("b")
            ),
            printerDescription: PlannedFileArtifact(
                kind: .printerDescription, path: AbsolutePath(descriptionPath),
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

    static func plan(with sink: inout InertInstallationSink) throws -> QueueInstallationPlan {
        let intent = try intent()
        let preconditions = QueueInstallationPreconditions.capture(for: intent, from: &sink)
        return try QueueInstallationPlan(
            transactionID: QueueInstallationTransactionID(hex: transactionHex),
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
        // A regular artifact must declare the digest validation will compare against.
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .filterExecutable, path: path, mode: POSIXMode(0o755), contentSHA256: nil
        )) { XCTAssertEqual($0 as? QueueInstallationError, .invalidDigest) }
        // A directory has no content to digest.
        XCTAssertThrowsError(try PlannedFileArtifact(
            kind: .protectedRoot, path: path, mode: POSIXMode(0o755), contentSHA256: Fixture.digest("a")
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
    }

    // MARK: - Preconditions gate planning

    func testPlanRefusesAPreExistingQueueRatherThanAdoptingIt() throws {
        var sink = try Fixture.cleanSink()
        sink.queues.insert(Fixture.queueName)
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
        let intent = try Fixture.intent()
        let preconditions = QueueInstallationPreconditions.capture(for: intent, from: &secondSink)
        let secondPlan = try QueueInstallationPlan(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "f", count: 32)),
            intent: intent,
            preconditions: preconditions
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

    func testQueueAbsenceIsReProvedImmediatelyBeforeCreation() throws {
        var sink = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        // Another administrator took the name between planning and creation.
        sink.queues.insert(Fixture.queueName)
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
        sink.queues.remove(Fixture.queueName)
        let outcome = try transaction.complete(using: &sink)
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertEqual(outcome, .residual(transaction.record, .queueAbsentAfterCreation))
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
        sink.queues.insert(Fixture.queueName)
        let recovery = try transaction.recoveryPlan()
        XCTAssertFalse(recovery.steps.contains { if case .removeQueue = $0 { return true }; return false })
        let outcome = transaction.rollBack(using: &sink)
        XCTAssertEqual(outcome, .rolledBack(transaction.record))
        XCTAssertTrue(sink.queues.contains(Fixture.queueName))
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
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
        XCTAssertTrue(text.contains("created=queue\n"))
        XCTAssertTrue(text.contains("|0755|"))
        // A directory records no content digest rather than a placeholder one.
        XCTAssertTrue(text.contains("protected-root|\(Fixture.rootPath)|0|0|0755|-\n"))
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
        ]
        for candidate in corrupted {
            XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(candidate), candidate)
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
