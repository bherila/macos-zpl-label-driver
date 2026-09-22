import XCTest
@testable import LabelCore

/// An inert, in-memory stand-in for the effect seam. It never touches a
/// filesystem, a scheduler, a process or a device: it is a dictionary, a map and
/// a log. Nothing in this file may be promoted to a real implementation.
///
/// It honours the contracts the protocol states and the model cannot enforce —
/// exclusive root reservation, a **byte-exact** compare-and-swap journal
/// replacement that reports the durability it achieved, a bounded journal read,
/// `rmdir`-style empty-directory removal, writing the incarnation and the
/// requested destination into the queue, and conditional removals that are
/// performed only while the state they carry still holds — so that the model's
/// behaviour against a *conforming* seam is what the tests measure. Each
/// contract also has a switch to violate it, so the model's response to a
/// non-conforming or hostile world is covered too.
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
    /// Queues this stand-in holds, each with what is readable out of its
    /// configuration.
    var queues: [String: SchedulerQueueState] = [:]
    var persistedRecord: String?
    /// What a read of the journal returns instead of what was written. This is
    /// the window between the transaction's last write and its next read.
    var journalOverrideOnRead: String?
    /// A conforming refusal: the file is larger than the cap the read carries,
    /// so nothing is materialized.
    var journalExceedsReadLimit = false
    /// A *non*-conforming read: more bytes than the cap allowed are handed back
    /// anyway. The model must refuse them rather than decode them.
    var unboundedJournalOnRead: String?
    var queueQueryFails = false
    var recordQueryFails = false
    var fileQueryFailures: Set<String> = []
    var createFileFailures: Set<String> = []
    var createRootFails = false
    var createQueueFails = false
    var persistRecordFails = false
    /// What a successful journal write proves about reaching stable storage.
    var journalDurability: JournalDurability = .synchronizedToStorage
    var removeQueueFails = false
    var removeFileFailures: Set<String> = []
    var removeEmptyDirectoryFails = false
    /// What `createQueue` reports it could prove. A seam built on `lpadmin`
    /// would always report `ambiguousCreateOrModify`.
    var acquisition: SchedulerQueueAcquisition = .exclusiveCreation
    /// Creates the queue without writing the incarnation token into it.
    var incarnationWriteFails = false
    /// Points the created queue somewhere other than the destination it was
    /// given — what a conformer that took its target from ambient state would do.
    var createQueueDestination: QueueDestination?
    /// The created queue's destination cannot be read back out of it.
    var destinationReadFails = false
    /// Stages these bytes/metadata instead of the planned ones. This is the
    /// TOCTOU window between staging and validating, made reproducible.
    var tamperOnCreate: [String: ObservedFileState] = [:]
    /// Paths whose removal call succeeds without the path actually going away.
    var removalsWithoutEffect: Set<String> = []
    var queueRemovalWithoutEffect = false
    /// The conditional removals report an outcome they cannot determine.
    var queueRemovalOutcomeUnknown = false
    var fileRemovalOutcomeUnknown: Set<String> = []
    /// Another administrator recreates the queue name between the observation
    /// and the removal. A conditional deletion must decline; an unconditional
    /// one would delete this replacement.
    var queueRecreatedBeforeRemoval: SchedulerQueueState?
    /// The path stops holding the validated artifact between the observation and
    /// the removal.
    var fileChangedBeforeRemoval: [String: ObservedFileState] = [:]
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
        guard let state = queues[queue.name] else { return .confirmedAbsent }
        return .present(state)
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
            contentSHA256: artifact.contentSHA256,
            accessControl: .noWriteGrantsBeyondOwner
        )
    }

    mutating func persistOwnershipRecord(
        _ text: String, replacing previous: String?, at artifact: PlannedFileArtifact
    ) throws -> JournalDurability {
        log.append(.persistRecord(artifact.path.value))
        if persistRecordFails { throw Failure.refused }
        // Contract: replace in one step, and only if the current contents are
        // exactly `previous` — compared as **bytes**, because that is what a
        // file holds. Swift's `String` equality is Unicode canonical
        // equivalence, under which `K` and U+212A KELVIN SIGN are equal while
        // their UTF-8 differs, so comparing as strings would overwrite a journal
        // this transaction never wrote.
        guard persistedRecord.map({ Array($0.utf8) }) == previous.map({ Array($0.utf8) }) else {
            throw Failure.staleJournal
        }
        if journalDurability == .synchronizedToStorage {
            persistedRecord = text
            files[artifact.path.value] = try ObservedFileState(
                kind: .regularFile,
                uid: artifact.ownership.uid,
                gid: artifact.ownership.gid,
                modeBits: artifact.mode.rawValue,
                accessControl: .noWriteGrantsBeyondOwner
            )
        }
        return journalDurability
    }

    mutating func readOwnershipRecord(
        at artifact: PlannedFileArtifact, maximumByteCount: Int
    ) -> OwnershipRecordObservation {
        log.append(.readRecord(artifact.path.value))
        if recordQueryFails { return .queryFailed }
        // Contract: read no more than the cap, and say so instead of
        // materializing a larger file.
        if journalExceedsReadLimit { return .exceededMaximumByteCount }
        if let unboundedJournalOnRead { return .present(unboundedJournalOnRead) }
        if let journalOverrideOnRead { return .present(journalOverrideOnRead) }
        guard let persistedRecord else { return .confirmedAbsent }
        guard persistedRecord.utf8.count <= maximumByteCount else { return .exceededMaximumByteCount }
        return .present(persistedRecord)
    }

    mutating func createQueue(
        _ queue: PlannedSchedulerQueue,
        describedBy description: PlannedFileArtifact,
        deliveringTo destination: QueueDestination,
        incarnation: SchedulerQueueIncarnation
    ) throws -> SchedulerQueueAcquisition {
        log.append(.createQueue(queue.name))
        if createQueueFails { throw Failure.refused }
        // Contract: write the token into the queue's own configuration, and
        // point the queue at exactly the destination this call was given.
        queues[queue.name] = SchedulerQueueState(
            incarnation: incarnationWriteFails ? nil : incarnation,
            destination: destinationReadFails ? .unknown : .known(createQueueDestination ?? destination)
        )
        return acquisition
    }

    mutating func removeQueue(
        _ queue: PlannedSchedulerQueue, ifIncarnationMatches incarnation: SchedulerQueueIncarnation
    ) throws -> SchedulerQueueRemoval {
        log.append(.removeQueue(queue.name))
        if removeQueueFails { throw Failure.refused }
        if let queueRecreatedBeforeRemoval { queues[queue.name] = queueRecreatedBeforeRemoval }
        if queueRemovalOutcomeUnknown { return .unknown }
        // Contract: conditional. Delete only while the name still carries the
        // incarnation this call was given.
        guard queues[queue.name]?.incarnation == incarnation else { return .incarnationChanged }
        if queueRemovalWithoutEffect { return .removed }
        queues.removeValue(forKey: queue.name)
        return .removed
    }

    mutating func removeFile(_ artifact: PlannedFileArtifact) throws -> FileArtifactRemoval {
        let path = artifact.path.value
        log.append(.removeFile(path))
        if removeFileFailures.contains(path) { throw Failure.refused }
        if let changed = fileChangedBeforeRemoval[path] { files[path] = changed }
        if fileRemovalOutcomeUnknown.contains(path) { return .unknown }
        // Contract: conditional. Delete only while the path still holds exactly
        // the artifact described.
        guard let present = files[path], present == (try? state(of: artifact)) else {
            return .artifactChanged
        }
        if removalsWithoutEffect.contains(path) { return .removed }
        files.removeValue(forKey: path)
        if path == Fixture.recordPath { persistedRecord = nil }
        return .removed
    }

    mutating func removeEmptyDirectory(_ artifact: PlannedFileArtifact) throws -> FileArtifactRemoval {
        let path = artifact.path.value
        log.append(.removeEmptyDirectory(path))
        if removeEmptyDirectoryFails { throw Failure.refused }
        // Contract: rmdir semantics. A non-empty directory is a refusal, never a
        // recursive delete.
        guard !files.keys.contains(where: { $0.hasPrefix(path + "/") }) else { throw Failure.notEmpty }
        if let changed = fileChangedBeforeRemoval[path] { files[path] = changed }
        if fileRemovalOutcomeUnknown.contains(path) { return .unknown }
        guard let present = files[path], present == (try? state(of: artifact)) else {
            return .artifactChanged
        }
        if removalsWithoutEffect.contains(path) { return .removed }
        files.removeValue(forKey: path)
        return .removed
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

    /// The only destination these tests plan. It is the inert discard sink, and
    /// it is deliberately not a device: `AGENTS.md` requires that the inert sink
    /// is never connected to the GC420d, and nothing in this model may make a
    /// device destination the easy default.
    static let destination = QueueDestination.inertDiscardSink

    /// A *different* destination, used only to prove that a queue pointed
    /// somewhere other than the plan said is detected. Naming a device model
    /// here is not consent to print to one; nothing in this file reaches a bus.
    static func deviceDestination() throws -> QueueDestination {
        .usbDevice(try USBDeviceDestination(vendorID: 0x0a5f, productID: 0x00a3))
    }

    static func digest(_ seed: String) -> String {
        String(repeating: seed, count: 64 / seed.utf8.count)
    }

    static func incarnation(_ seed: String = "1") throws -> SchedulerQueueIncarnation {
        try SchedulerQueueIncarnation(token: digest(seed))
    }

    /// A present queue as the stand-in holds one: a token and a destination.
    static func queueState(
        _ seed: String = "1", destination: ObservedQueueDestination = .known(destination)
    ) throws -> SchedulerQueueState {
        SchedulerQueueState(incarnation: try incarnation(seed), destination: destination)
    }

    static func intent(
        rootPath: String = rootPath,
        queueName: String = queueName,
        destination: QueueDestination = destination
    ) throws -> QueueInstallationIntent {
        try QueueInstallationIntent(
            queue: PlannedSchedulerQueue(name: queueName),
            destination: destination,
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
        try ObservedFileState(
            kind: .directory, uid: 0, gid: 0, modeBits: 0o755,
            accessControl: .noWriteGrantsBeyondOwner
        )
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

    /// Plans, stages, validates and creates the queue, stopping short of
    /// completion so that the final boundary can be tested on its own.
    static func queueCreated(
        _ sink: inout InertInstallationSink
    ) throws -> QueueInstallationTransaction {
        let plan = try plan(with: &sink)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        return transaction
    }

    /// The separately authorized recovery a human drives from the record.
    static func recordValidated(
        _ transaction: QueueInstallationTransaction
    ) -> QueueInstallationRecovery {
        QueueInstallationRecovery(
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
            queue: intent.queue, destination: intent.destination,
            protectedRoot: intent.protectedRoot,
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
        sink.queues[Fixture.queueName] = try Fixture.queueState("e")
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
        let tokenless = SchedulerQueueObservation.present(
            SchedulerQueueState(incarnation: nil, destination: .unknown)
        )
        XCTAssertTrue(tokenless.isConfirmedPresent)
        XCTAssertNil(tokenless.incarnation)
        XCTAssertEqual(tokenless.destination, .unknown)
        XCTAssertEqual(SchedulerQueueObservation.queryFailed.destination, .unknown)

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
            ("world-writable", try ObservedFileState(
                kind: .directory, uid: 0, gid: 0, modeBits: 0o777,
                accessControl: .noWriteGrantsBeyondOwner
            )),
            ("not-root-owned", try ObservedFileState(
                kind: .directory, uid: 501, gid: 0, modeBits: 0o755,
                accessControl: .noWriteGrantsBeyondOwner
            )),
            ("symlink", try ObservedFileState(
                kind: .symbolicLink, uid: 0, gid: 0, modeBits: 0o755,
                accessControl: .noWriteGrantsBeyondOwner
            )),
            ("regular-file", try ObservedFileState(
                kind: .regularFile, uid: 0, gid: 0, modeBits: 0o644,
                accessControl: .noWriteGrantsBeyondOwner
            )),
        ]
        for (label, state) in unsuitable {
            var sink = try Fixture.cleanSink()
            sink.files[Fixture.stagingParent] = state
            XCTAssertThrowsError(try Fixture.plan(with: &sink), label) {
                XCTAssertEqual($0 as? QueueInstallationError, .refused(.stagingParentUnsuitable))
            }
        }

        var partial = try Fixture.cleanSink()
        partial.files[Fixture.stagingParent] = try ObservedFileState(
            kind: .directory, uid: 0, gid: 0, accessControl: .noWriteGrantsBeyondOwner
        )
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
            transactionID: plan.transactionID, intent: plan.intent, phase: .inProgress,
            pendingArtifact: .schedulerQueue,
            createdArtifacts: Array(Fixture.everyArtifact.dropLast())
        )
        sink.queues[Fixture.queueName] = try Fixture.queueState()
        sink.persistedRecord = record.canonicalText
        var recovery = QueueInstallationRecovery(
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
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("f"),
            accessControl: .noWriteGrantsBeyondOwner
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
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("9"),
            accessControl: .noWriteGrantsBeyondOwner
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
            intent: plan.intent, phase: .inProgress, createdArtifacts: []
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
        let clean = ObservedAccessControl.noWriteGrantsBeyondOwner
        let substitutions: [(ObservedFileState?, ArtifactValidationFailure)] = [
            (try ObservedFileState(kind: .symbolicLink, uid: 0, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b"), accessControl: clean), .symbolicLink),
            (try ObservedFileState(kind: .directory, uid: 0, gid: 0, modeBits: 0o755,
                                   accessControl: clean), .wrongFileKind),
            (try ObservedFileState(kind: .regularFile, uid: 501, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b"), accessControl: clean), .ownershipMismatch),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0, modeBits: 0o700,
                                   contentSHA256: Fixture.digest("b"), accessControl: clean), .modeMismatch),
            (try ObservedFileState(kind: .regularFile, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b"), accessControl: clean), .ownershipUnknown),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0,
                                   contentSHA256: Fixture.digest("b"), accessControl: clean), .modeUnknown),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b"),
                                   accessControl: .grantsWriteToOtherPrincipals),
             .accessControlGrantsOtherPrincipals),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755,
                                   contentSHA256: Fixture.digest("b"),
                                   accessControl: .unknown), .accessControlUnknown),
            (try ObservedFileState(kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755,
                                   accessControl: clean), .contentUnknown),
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
            intent: plan.intent, phase: .inProgress, createdArtifacts: []
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
        sink.queues[Fixture.queueName] = try Fixture.queueState("e")
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
        sink.queues[Fixture.queueName] = SchedulerQueueState(
            incarnation: nil, destination: .known(Fixture.destination)
        )
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
        var recovery = Fixture.recordValidated(transaction)
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
        var recovery = Fixture.recordValidated(transaction)
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
        var recovery = Fixture.recordValidated(transaction)
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
        var recovery = Fixture.recordValidated(transaction)
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
        sink.queues[Fixture.queueName] = try Fixture.queueState("e")
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
        let recreated = try Fixture.queueState("7")
        XCTAssertNotEqual(transaction.record.queueIncarnation, recreated.incarnation)
        sink.queues[Fixture.queueName] = recreated

        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueIncarnationUnverified))
        XCTAssertFalse(sink.log.contains(.removeQueue(Fixture.queueName)))
        XCTAssertEqual(sink.queues[Fixture.queueName]?.incarnation, recreated.incarnation)
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.files[Fixture.filterPath])
    }

    func testAQueuePresentWithoutAnIncarnationIsNeverRemoved() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.queues[Fixture.queueName] = SchedulerQueueState(
            incarnation: nil, destination: .known(Fixture.destination)
        )
        var recovery = Fixture.recordValidated(transaction)
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
        var recovery = Fixture.recordValidated(transaction)
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
        var recovery = Fixture.recordValidated(transaction)
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
        var recovery = Fixture.recordValidated(transaction)
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
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("9"),
            accessControl: .noWriteGrantsBeyondOwner
        )
        var recovery = Fixture.recordValidated(transaction)
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
        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .fileStateUnknown))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.descriptionPath)))
    }

    func testAnUnverifiedFileRemovalIsResidualNotRolledBack() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.removalsWithoutEffect.insert(Fixture.descriptionPath)
        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .fileRemovalUnverified))
        XCTAssertTrue(recovery.record.owns(.file(try AbsolutePath(Fixture.descriptionPath))))
    }

    func testAFailedRemovalEffectIsResidualNotRolledBack() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.removeFileFailures.insert(Fixture.filterPath)
        var recovery = Fixture.recordValidated(transaction)
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
            intent: Fixture.intent(queueName: "SomeOtherQueue"),
            phase: .inProgress,
            createdArtifacts: []
        )
        XCTAssertEqual(sameIDDifferentQueue.transactionID, transaction.record.transactionID)
        sink.journalOverrideOnRead = sameIDDifferentQueue.canonicalText

        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .unexpectedArtifactState))
        XCTAssertFalse(sink.log.contains(.removeFile(Fixture.recordPath)))
        XCTAssertNotNil(sink.files[Fixture.recordPath])
        XCTAssertFalse(sink.log.contains(.removeEmptyDirectory(Fixture.rootPath)))
    }

    /// Finding K: the journal rewrite must be conditional, or the first
    /// successful removal overwrites a foreign journal before anything reads it
    /// — which would make the journal check above unreachable in a real sink.
    ///
    /// Finding 1: and the condition has to be tested *before* the first
    /// destructive effect, not after it. If another transaction had already
    /// replaced the durable record — recreating the root and writing its own
    /// inventory — then noticing the conflict on the write that follows the
    /// removal is noticing it one queue too late.
    func testAReplacedJournalStopsRecoveryBeforeAnyDestructiveEffect() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let foreign = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "b", count: 32)),
            intent: transaction.record.intent, phase: .inProgress, createdArtifacts: []
        ).canonicalText
        // Something replaced the journal behind our back, before recovery even
        // begins.
        sink.persistedRecord = foreign

        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .journalConflict))
        // The foreign journal survives: the rewrite was refused, not applied.
        XCTAssertEqual(sink.persistedRecord, foreign)
        // And nothing at all was destroyed — not the queue that the conflicting
        // transaction may own, and not one of its files either.
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.queues[Fixture.queueName])
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertNotNil(sink.files[Fixture.rootPath])
    }

    /// Finding 12: the stand-in's compare-and-swap has to be a *byte* compare,
    /// because that is what a file holds and what the seam contract says. Swift
    /// `String` equality is Unicode canonical equivalence, under which ASCII `K`
    /// and U+212A KELVIN SIGN are equal — so a journal replaced by a
    /// canonically equivalent one would pass a `String` comparison and be
    /// overwritten, and the conditional-write regressions above would be testing
    /// nothing.
    func testJournalCompareAndSwapIsByBytesNotCanonicalEquivalence() throws {
        // The premise, pinned rather than assumed.
        XCTAssertEqual("K", "\u{212A}")
        XCTAssertNotEqual(Array("K".utf8), Array("\u{212A}".utf8))

        var sink = try Fixture.cleanSink()
        let intent = try Fixture.intent(queueName: "LabelDriver-Kiosk")
        let plan = try Fixture.plan(with: &sink, intent: intent)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &sink)
        let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
        try transaction.createQueue(authorizedBy: validated, using: &sink)
        _ = try transaction.complete(using: &sink)

        let ours = try XCTUnwrap(transaction.lastDurableText)
        XCTAssertTrue(ours.contains("K"))
        let equivalent = ours.replacingOccurrences(of: "K", with: "\u{212A}")
        // Equal as Swift strings, different as bytes: exactly the substitution a
        // canonical-equivalence compare would wave through.
        XCTAssertEqual(equivalent, ours)
        XCTAssertNotEqual(Array(equivalent.utf8), Array(ours.utf8))
        sink.persistedRecord = equivalent

        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .journalConflict))
        XCTAssertEqual(Array(try XCTUnwrap(sink.persistedRecord).utf8), Array(equivalent.utf8))
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.queues["LabelDriver-Kiosk"])
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

        // Nothing is there at all, which the artifact observation says before
        // anything is read.
        var empty = try Fixture.cleanSink()
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &empty
        )) {
            XCTAssertEqual(
                $0 as? QueueInstallationError, .stagedArtifactInvalid(.ownershipRecord, .absent)
            )
        }
        XCTAssertFalse(empty.log.contains(.readRecord(Fixture.recordPath)))

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
            intent: elsewhere, phase: .inProgress, createdArtifacts: []
        ).canonicalText
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &misplaced
        )) { XCTAssertEqual($0 as? QueueInstallationError, .recordHasNoJournal) }
    }

    /// Finding 2: a record is only as trustworthy as the inventory it carries,
    /// and a decoded one arrives from outside this process. It must be the exact
    /// four-artifact topology an intent describes — not a longer list, not a
    /// missing journal, not a reordered pair of kinds, and above all not a
    /// root-owned file that lives somewhere other than one component below this
    /// transaction's own protected root. Record-validated recovery deletes what
    /// the record names, so an unconstrained list is a delete-arbitrary-file
    /// primitive that only needs a matching digest and mode.
    func testARecordRefusesAnInventoryThatIsNotItsIntent() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText

        // A filter that is not inside the protected root at all, named both as
        // planned and as created, which is what a record-validated recovery
        // would then delete. Every other field — kind, owner, mode, digest —
        // still matches, which is precisely why path containment has to be the
        // thing that refuses it.
        let escaped = text.replacingOccurrences(
            of: Fixture.filterPath, with: "/usr/local/libexec/somebody-elses-tool"
        )
        XCTAssertNotEqual(escaped, text)
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(escaped)) {
            XCTAssertEqual($0 as? QueueInstallationError, .artifactOutsideProtectedRoot)
        }

        // A sibling of the root rather than a child of it.
        let sibling = text.replacingOccurrences(
            of: Fixture.descriptionPath, with: Fixture.stagingParent + "/capture.ppd"
        )
        XCTAssertNotEqual(sibling, text)
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(sibling)) {
            XCTAssertEqual($0 as? QueueInstallationError, .artifactOutsideProtectedRoot)
        }

        // Nested deeper than one component: recovery must stay finite.
        let nested = text.replacingOccurrences(
            of: Fixture.filterPath, with: Fixture.rootPath + "/bin/labelcapture-filter"
        )
        XCTAssertNotEqual(nested, text)
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(nested)) {
            XCTAssertEqual($0 as? QueueInstallationError, .artifactOutsideProtectedRoot)
        }

        // The journal line removed: a record with nowhere to keep its evidence.
        let journalless = text.replacingOccurrences(
            of: "file=ownership-record|\(Fixture.recordPath)|0|0|0644|-\n", with: ""
        ).replacingOccurrences(of: "created=\(Fixture.recordPath)\n", with: "")
        XCTAssertNotEqual(journalless, text)
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(journalless)) {
            XCTAssertEqual($0 as? QueueInstallationError, .recordInventoryMismatch)
        }

        // A fifth artifact nobody plans.
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let descriptionLine = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("file=printer-description") })
        lines.insert(
            "file=printer-description|\(Fixture.rootPath)/second.ppd|0|0|0644|\(Fixture.digest("c"))",
            at: descriptionLine + 1
        )
        let extra = lines.joined(separator: "\n")
        XCTAssertNotEqual(extra, text)
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(extra)) {
            XCTAssertEqual($0 as? QueueInstallationError, .recordInventoryMismatch)
        }

        // And the intact record still decodes, so the refusals above are about
        // the inventory and not about the editing.
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text), transaction.record)
    }

    // MARK: - Durable ownership record

    func testOwnershipRecordRoundTripsCanonically() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        let text = transaction.record.canonicalText
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text), transaction.record)
        XCTAssertEqual(try QueueInstallationOwnershipRecord.decode(text).canonicalText, text)
        XCTAssertTrue(text.hasPrefix("schemaVersion=3\ntransactionID=\(Fixture.transactionHex)\n"))
        XCTAssertTrue(text.contains("queue=\(Fixture.queueName)\nqueueDestination=inert-discard-sink\n"))
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

        let corrupted: [String] = [
            String(text.dropLast()),
            text + "unexpected=value\n",
            text.replacingOccurrences(of: "schemaVersion=3", with: "schemaVersion=4"),
            text.replacingOccurrences(of: "queueDestination=inert-discard-sink", with: "queueDestination=-"),
            text.replacingOccurrences(
                of: "queueDestination=inert-discard-sink", with: "queueDestination=usb-device|04b|0005"
            ),
            text.replacingOccurrences(
                of: "queueDestination=inert-discard-sink", with: "queueDestination=usb-device|0A5F|00a3"
            ),
            text.replacingOccurrences(of: "queueDestination=inert-discard-sink\n", with: ""),
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
                transactionID: id, intent: intent,
                queueIncarnation: incarnation, queueAcquisition: acquisition,
                phase: phase, pendingArtifact: pending,
                createdArtifacts: created
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
        // Completed while some planned artifact was never created. The queue
        // after a gap is not a prefix of the creation order at all, which is
        // caught before the phase rule is reached.
        XCTAssertThrowsError(try build(
            phase: .completed, incarnation: incarnation, acquisition: .exclusiveCreation,
            created: Array(everyFile.dropLast()) + [.schedulerQueue]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .createdArtifactsOutOfOrder) }
        // Completed with something still pending.
        XCTAssertThrowsError(try build(
            phase: .completed, incarnation: incarnation, acquisition: .exclusiveCreation,
            pending: .schedulerQueue, created: everyFile
        )) { XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase) }
        // Rolled back while still listing live artifacts, or with a pending step.
        XCTAssertThrowsError(try build(phase: .rolledBack, created: everyFile)) {
            XCTAssertEqual($0 as? QueueInstallationError, .inconsistentRecordPhase)
        }
        XCTAssertThrowsError(try build(phase: .rolledBack, pending: everyFile[0], created: [])) {
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
            intent: intent,
            queueIncarnation: Fixture.incarnation(), queueAcquisition: .exclusiveCreation,
            phase: .completed,
            createdArtifacts: permuted + [.schedulerQueue]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .createdArtifactsOutOfOrder) }

        // The queue must also be last, not merely present.
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            intent: intent,
            queueIncarnation: Fixture.incarnation(), queueAcquisition: .exclusiveCreation,
            phase: .completed,
            createdArtifacts: [.schedulerQueue] + everyFile
        )) { XCTAssertEqual($0 as? QueueInstallationError, .createdArtifactsOutOfOrder) }
    }

    /// Finding 3: the same rule has to hold for the *interrupted* phases, which
    /// are the only ones recovery ever reverses. A record claiming
    /// `[root, filter, journal]` would have recovery remove the journal before
    /// the filter, so a failure at the filter would leave an owned artifact with
    /// no durable evidence naming it.
    func testAnInterruptedRecordRequiresPrefixCreationOrder() throws {
        let intent = try Fixture.intent()
        let ids = intent.creationOrderedFiles.map { QueueInstallationArtifactID.file($0.path) }
        let root = ids[0], journal = ids[1], filter = ids[2], description = ids[3]

        func build(
            phase: QueueInstallationRecordedPhase,
            pending: QueueInstallationArtifactID? = nil,
            created: [QueueInstallationArtifactID]
        ) throws -> QueueInstallationOwnershipRecord {
            try QueueInstallationOwnershipRecord(
                transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
                intent: intent, phase: phase, pendingArtifact: pending, createdArtifacts: created
            )
        }

        for phase in [QueueInstallationRecordedPhase.inProgress, .residual] {
            // The journal recorded after the filter: exactly the permutation
            // that costs recovery its own evidence.
            XCTAssertThrowsError(try build(phase: phase, created: [root, filter, journal])) {
                XCTAssertEqual($0 as? QueueInstallationError, .createdArtifactsOutOfOrder)
            }
            // A gap in the middle is not a prefix either.
            XCTAssertThrowsError(try build(phase: phase, created: [root, journal, description])) {
                XCTAssertEqual($0 as? QueueInstallationError, .createdArtifactsOutOfOrder)
            }
            // A pending step that is not the one immediately after what is
            // created would hide the step actually in flight.
            XCTAssertThrowsError(try build(phase: phase, pending: description, created: [root, journal])) {
                XCTAssertEqual($0 as? QueueInstallationError, .createdArtifactsOutOfOrder)
            }
            XCTAssertNoThrow(try build(phase: phase, pending: root, created: []))
            // What a transaction actually produces is admitted.
            XCTAssertNoThrow(try build(phase: phase, created: [root, journal, filter]))
            XCTAssertNoThrow(try build(phase: phase, pending: filter, created: [root, journal]))
        }

        // A canonical journal carrying the bad order is refused on decode too,
        // which is where it would arrive from outside this process.
        let good = try build(phase: .inProgress, created: [root, journal, filter])
        let text = good.canonicalText
        let swapped = text.replacingOccurrences(
            of: "created=\(Fixture.recordPath)\ncreated=\(Fixture.filterPath)\n",
            with: "created=\(Fixture.filterPath)\ncreated=\(Fixture.recordPath)\n"
        )
        XCTAssertNotEqual(swapped, text)
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord.decode(swapped)) {
            XCTAssertEqual($0 as? QueueInstallationError, .createdArtifactsOutOfOrder)
        }
    }

    func testARecordCannotClaimAnArtifactItDoesNotPlan() throws {
        let intent = try Fixture.intent()
        let unplanned = QueueInstallationArtifactID.file(
            try AbsolutePath("/Library/Printers/OtherModel/labelcapture-filter")
        )
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            intent: intent, phase: .inProgress,
            createdArtifacts: [unplanned]
        )) { XCTAssertEqual($0 as? QueueInstallationError, .notOwnedByTransaction) }

        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            intent: intent, phase: .inProgress,
            pendingArtifact: unplanned, createdArtifacts: []
        )) { XCTAssertEqual($0 as? QueueInstallationError, .notOwnedByTransaction) }

        let root = QueueInstallationArtifactID.file(try AbsolutePath(Fixture.rootPath))
        XCTAssertThrowsError(try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: Fixture.transactionHex),
            intent: intent, phase: .inProgress,
            createdArtifacts: [root, root]
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

    // MARK: - The seam's stated contract, made observable

    /// Finding 5: "atomic conditional replacement" is satisfied by an ordinary
    /// temp-file rename, under which a power loss can restore the older journal
    /// and lose the entry naming an artifact that by then exists. So the write
    /// has to say what it achieved, and a step whose journal entry is not proved
    /// durable must not run.
    func testAJournalWriteMustBeProvedDurableBeforeItsStepRuns() throws {
        for durability in [JournalDurability.notSynchronized, .unknown] {
            var sink = try Fixture.cleanSink()
            let plan = try Fixture.plan(with: &sink)
            var transaction = try QueueInstallationTransaction(plan: plan)
            sink.journalDurability = durability
            XCTAssertThrowsError(try transaction.stage(using: &sink), durability.rawValue) {
                XCTAssertEqual($0 as? QueueInstallationError, .journalWriteNotDurable)
            }
            // The payload that entry was supposed to precede was never created,
            // and the transaction claims no durable bytes of its own.
            XCTAssertNil(sink.files[Fixture.filterPath])
            XCTAssertFalse(sink.log.contains(.createFile(Fixture.filterPath)))
            XCTAssertNil(transaction.lastDurableText)
        }

        // In recovery the same write precedes a *destruction*, so an unprovable
        // one stops the pass before anything is removed.
        var recovering = try Fixture.cleanSink()
        let (installed, _) = try Fixture.installed(&recovering)
        recovering.journalDurability = .notSynchronized
        var recovery = Fixture.recordValidated(installed)
        XCTAssertEqual(recovery.recover(using: &recovering), .residual(recovery.record, .journalNotDurable))
        XCTAssertTrue(recovering.removalEvents.isEmpty)
        XCTAssertNotNil(recovering.queues[Fixture.queueName])

        // The same sequence with a durable write completes, so the refusals
        // above are about durability and nothing else.
        var durable = try Fixture.cleanSink()
        XCTAssertTrue(try Fixture.installed(&durable).1.isCompleted)
    }

    /// Finding 9: the decoder's 16 KiB cap is reached only after a `String`
    /// exists, so the read itself has to be bounded. A conforming seam says it
    /// exceeded the cap; a non-conforming one that hands back more anyway is
    /// refused rather than decoded.
    func testAnOversizeJournalIsRefusedRatherThanDecoded() throws {
        let limit = QueueInstallationOwnershipRecord.maximumEncodedByteCount
        let journal = try Fixture.intent().ownershipRecord

        var conforming = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&conforming)
        conforming.journalExceedsReadLimit = true
        var recovery = Fixture.recordValidated(transaction)
        XCTAssertEqual(recovery.recover(using: &conforming), .residual(recovery.record, .fileStateUnknown))
        XCTAssertFalse(conforming.log.contains(.removeFile(Fixture.recordPath)))
        XCTAssertNotNil(conforming.files[Fixture.recordPath])

        var loading = try Fixture.cleanSink()
        _ = try Fixture.installed(&loading)
        loading.journalExceedsReadLimit = true
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: journal, authority: .recordValidated, using: &loading
        )) { XCTAssertEqual($0 as? QueueInstallationError, .ownershipRecordTooLarge) }

        // A seam that ignores the cap is not believed either.
        var unbounded = try Fixture.cleanSink()
        let (second, _) = try Fixture.installed(&unbounded)
        let padded = second.record.canonicalText + String(repeating: "#", count: limit) + "\n"
        XCTAssertGreaterThan(padded.utf8.count, limit)
        unbounded.unboundedJournalOnRead = padded
        var secondRecovery = Fixture.recordValidated(second)
        XCTAssertEqual(
            secondRecovery.recover(using: &unbounded), .residual(secondRecovery.record, .fileStateUnknown)
        )
        XCTAssertFalse(unbounded.log.contains(.removeFile(Fixture.recordPath)))
        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: journal, authority: .recordValidated, using: &unbounded
        )) { XCTAssertEqual($0 as? QueueInstallationError, .ownershipRecordTooLarge) }

        // A record inside the cap still reads back, so the refusals above are
        // about size and not about the override.
        var ordinary = try Fixture.cleanSink()
        let (third, _) = try Fixture.installed(&ordinary)
        XCTAssertLessThanOrEqual(third.record.canonicalText.utf8.count, limit)
        var third_recovery = Fixture.recordValidated(third)
        XCTAssertEqual(third_recovery.recover(using: &ordinary), .rolledBack(third_recovery.record))
    }

    /// Finding 10: macOS ACLs can grant another principal `add_file` or
    /// `delete_child` while `stat` still reports root:wheel and mode 0755. A
    /// staging parent admitted on its mode bits alone can therefore be one
    /// another user is able to race, and an inheritable entry carries the same
    /// grant onto the root this transaction creates inside it.
    func testAnACLWriteGrantDefeatsTheProtectedStagingParent() throws {
        var granting = try Fixture.cleanSink()
        granting.files[Fixture.stagingParent] = try ObservedFileState(
            kind: .directory, uid: 0, gid: 0, modeBits: 0o755,
            accessControl: .grantsWriteToOtherPrincipals
        )
        // The mode bits say this parent is fine. They are not the whole story.
        XCTAssertEqual(try XCTUnwrap(granting.files[Fixture.stagingParent]).modeBits, 0o755)
        XCTAssertEqual(try XCTUnwrap(granting.files[Fixture.stagingParent]).uid, 0)
        XCTAssertThrowsError(try Fixture.plan(with: &granting)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.stagingParentUnsuitable))
        }

        // An observer that never enumerated access control has not proved
        // anything, and unknown is not "no grants".
        var unlooked = try Fixture.cleanSink()
        unlooked.files[Fixture.stagingParent] = try ObservedFileState(
            kind: .directory, uid: 0, gid: 0, modeBits: 0o755
        )
        XCTAssertEqual(try XCTUnwrap(unlooked.files[Fixture.stagingParent]).accessControl, .unknown)
        XCTAssertThrowsError(try Fixture.plan(with: &unlooked)) {
            XCTAssertEqual($0 as? QueueInstallationError, .refused(.stagingParentStateUnknown))
        }

        // And the grant inherited onto the created root fails validation there.
        var inherited = try Fixture.cleanSink()
        let plan = try Fixture.plan(with: &inherited)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &inherited)
        inherited.files[Fixture.rootPath] = try ObservedFileState(
            kind: .directory, uid: 0, gid: 0, modeBits: 0o755,
            accessControl: .grantsWriteToOtherPrincipals
        )
        XCTAssertThrowsError(try transaction.validateStagedArtifacts(staged, using: &inherited)) {
            XCTAssertEqual(
                $0 as? QueueInstallationError,
                .stagedArtifactInvalid(.protectedRoot, .accessControlGrantsOtherPrincipals)
            )
        }
        XCTAssertTrue(inherited.queues.isEmpty)
    }

    /// Finding 11: the read operation hands back bytes and nothing else, so the
    /// artifact those bytes came out of has to be validated *first*. Otherwise a
    /// symbolic link or a wrong-owner file holding a copied canonical record
    /// hydrates a record-validated recovery and authorizes destructive cleanup.
    func testLoadValidatesTheJournalArtifactBeforeReadingIt() throws {
        let journal = try Fixture.intent().ownershipRecord
        let hostile: [(String, ObservedFileState, ArtifactValidationFailure)] = [
            ("symbolic link", try ObservedFileState(
                kind: .symbolicLink, uid: 0, gid: 0, modeBits: 0o644,
                accessControl: .noWriteGrantsBeyondOwner
            ), .symbolicLink),
            ("directory", try ObservedFileState(
                kind: .directory, uid: 0, gid: 0, modeBits: 0o644,
                accessControl: .noWriteGrantsBeyondOwner
            ), .wrongFileKind),
            ("wrong owner", try ObservedFileState(
                kind: .regularFile, uid: 501, gid: 0, modeBits: 0o644,
                accessControl: .noWriteGrantsBeyondOwner
            ), .ownershipMismatch),
            ("wrong mode", try ObservedFileState(
                kind: .regularFile, uid: 0, gid: 0, modeBits: 0o600,
                accessControl: .noWriteGrantsBeyondOwner
            ), .modeMismatch),
            ("acl write grant", try ObservedFileState(
                kind: .regularFile, uid: 0, gid: 0, modeBits: 0o644,
                accessControl: .grantsWriteToOtherPrincipals
            ), .accessControlGrantsOtherPrincipals),
            ("unenumerated acl", try ObservedFileState(
                kind: .regularFile, uid: 0, gid: 0, modeBits: 0o644
            ), .accessControlUnknown),
        ]
        for (label, state, failure) in hostile {
            var sink = try Fixture.cleanSink()
            let (installed, _) = try Fixture.installed(&sink)
            // The bytes at the path are a perfectly canonical record — this
            // transaction's own — so only the artifact check can refuse them.
            XCTAssertEqual(sink.persistedRecord, installed.record.canonicalText)
            let readsBefore = sink.log.filter { $0 == .readRecord(Fixture.recordPath) }.count
            sink.files[Fixture.recordPath] = state
            XCTAssertThrowsError(try QueueInstallationRecovery.load(
                journalAt: journal, authority: .recordValidated, using: &sink
            ), label) {
                XCTAssertEqual(
                    $0 as? QueueInstallationError, .stagedArtifactInvalid(.ownershipRecord, failure)
                )
            }
            // Nothing was read, so nothing was decoded and nothing was authorized.
            XCTAssertEqual(
                sink.log.filter { $0 == .readRecord(Fixture.recordPath) }.count, readsBefore, label
            )
            XCTAssertTrue(sink.removalEvents.isEmpty, label)
        }
    }

    // MARK: - The destination is part of the plan

    /// Finding 6: a create operation given only a name and a description must
    /// take its target from ambient state, so the same authorized plan could
    /// produce a queue aimed at an inert sink or at a physical printer, and a
    /// token-only readback could not tell the two apart. The destination is
    /// therefore a closed typed value in the intent and the durable record, it
    /// is passed to the create operation, and it must read back exactly.
    func testTheQueueDestinationIsBoundToThePlanAndMustReadBackExactly() throws {
        // The inert sink and a device are different values, and neither is
        // built by interpolating a string.
        let device = try Fixture.deviceDestination()
        XCTAssertNotEqual(QueueDestination.inertDiscardSink, device)
        XCTAssertEqual(QueueDestination.inertDiscardSink.canonicalText, "inert-discard-sink")
        XCTAssertEqual(device.canonicalText, "usb-device|0a5f|00a3")
        XCTAssertEqual(try QueueDestination.decode("inert-discard-sink"), .inertDiscardSink)
        XCTAssertEqual(try QueueDestination.decode("usb-device|0a5f|00a3"), device)
        for rejected in ["", "usb-device", "usb-device|0a5f", "usb-device|0a5f|00a3|1", "usb-device|0A5F|00a3"] {
            XCTAssertThrowsError(try QueueDestination.decode(rejected), rejected) {
                XCTAssertEqual($0 as? QueueInstallationError, .invalidDestination)
            }
        }

        // A queue created pointing somewhere the plan did not ask for is
        // refused, although it carries this transaction's own token.
        var elsewhere = try Fixture.cleanSink()
        elsewhere.createQueueDestination = device
        let plan = try Fixture.plan(with: &elsewhere)
        XCTAssertEqual(plan.intent.destination, Fixture.destination)
        var transaction = try QueueInstallationTransaction(plan: plan)
        let staged = try transaction.stage(using: &elsewhere)
        let validated = try transaction.validateStagedArtifacts(staged, using: &elsewhere)
        XCTAssertThrowsError(try transaction.createQueue(authorizedBy: validated, using: &elsewhere)) {
            XCTAssertEqual($0 as? QueueInstallationError, .queueDestinationUnconfirmed)
        }
        XCTAssertEqual(elsewhere.queues[Fixture.queueName]?.incarnation, try Fixture.incarnation())
        XCTAssertFalse(transaction.record.createdArtifacts.contains(.schedulerQueue))
        XCTAssertEqual(transaction.record.pendingArtifact, .schedulerQueue)

        // A destination the seam cannot read back is unknown, and unknown is
        // not a match.
        var unreadable = try Fixture.cleanSink()
        unreadable.destinationReadFails = true
        let secondPlan = try Fixture.plan(with: &unreadable)
        var second = try QueueInstallationTransaction(plan: secondPlan)
        let secondStaged = try second.stage(using: &unreadable)
        let secondValidated = try second.validateStagedArtifacts(secondStaged, using: &unreadable)
        XCTAssertThrowsError(try second.createQueue(authorizedBy: secondValidated, using: &unreadable)) {
            XCTAssertEqual($0 as? QueueInstallationError, .queueDestinationUnconfirmed)
        }

        // It travels in the durable record, so a recovery that never saw the
        // plan still knows where the queue was pointed.
        var sink = try Fixture.cleanSink()
        let (installed, outcome) = try Fixture.installed(&sink)
        XCTAssertTrue(outcome.isCompleted)
        XCTAssertEqual(installed.record.destination, Fixture.destination)
        XCTAssertTrue(try XCTUnwrap(sink.persistedRecord).contains("queueDestination=inert-discard-sink\n"))
        let loaded = try QueueInstallationRecovery.load(
            journalAt: plan.intent.ownershipRecord, authority: .recordValidated, using: &sink
        )
        XCTAssertEqual(loaded.record.destination, Fixture.destination)
    }

    /// Finding 6, completion arm: exact readback is required before completion
    /// too, not only at creation.
    func testCompletionRequiresTheDestinationToStillMatch() throws {
        for observed in [
            ObservedQueueDestination.known(try Fixture.deviceDestination()), .unknown,
        ] {
            var sink = try Fixture.cleanSink()
            let plan = try Fixture.plan(with: &sink)
            var transaction = try QueueInstallationTransaction(plan: plan)
            let staged = try transaction.stage(using: &sink)
            let validated = try transaction.validateStagedArtifacts(staged, using: &sink)
            try transaction.createQueue(authorizedBy: validated, using: &sink)
            // The queue is re-pointed between creation and completion.
            sink.queues[Fixture.queueName] = SchedulerQueueState(
                incarnation: try Fixture.incarnation(), destination: observed
            )
            let outcome = try transaction.complete(using: &sink)
            XCTAssertFalse(outcome.isCompleted)
            XCTAssertTrue(outcome.requiresManualRecovery)
            XCTAssertEqual(outcome, .residual(transaction.record, .queueDestinationUnverified))
        }
    }

    /// Finding 6, recovery arm: a queue carrying this record's token but
    /// delivering somewhere else has been modified, and is retained for a human
    /// rather than deleted.
    func testRecoveryRetainsAQueueWhoseDestinationNoLongerMatches() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.queues[Fixture.queueName] = SchedulerQueueState(
            incarnation: try Fixture.incarnation(), destination: .known(try Fixture.deviceDestination())
        )
        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueDestinationUnverified))
        XCTAssertTrue(sink.removalEvents.isEmpty)
        XCTAssertNotNil(sink.queues[Fixture.queueName])
        XCTAssertNotNil(sink.files[Fixture.filterPath])
    }

    // MARK: - Conditional destruction

    /// Finding 7: the incarnation check and the deletion were two seam calls, so
    /// the queue could be deleted and the name recreated in between and the
    /// deletion would land on the replacement. The deletion now carries the
    /// incarnation it was authorized against.
    func testQueueDeletionIsConditionalOnTheCheckedIncarnation() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        // Between the observation that authorized the deletion and the deletion
        // itself, somebody else recreates the name.
        sink.queueRecreatedBeforeRemoval = try Fixture.queueState("7")
        var recovery = Fixture.recordValidated(transaction)
        let outcome = recovery.recover(using: &sink)
        XCTAssertEqual(outcome, .residual(recovery.record, .queueIncarnationUnverified))
        // The replacement survives, and the queue is still recorded as ours to
        // account for.
        XCTAssertEqual(sink.queues[Fixture.queueName]?.incarnation, try Fixture.incarnation("7"))
        XCTAssertEqual(sink.removalEvents, [.removeQueue(Fixture.queueName)])
        XCTAssertTrue(recovery.record.owns(.schedulerQueue))
        XCTAssertNotNil(sink.files[Fixture.filterPath])

        // An outcome the operation cannot determine is residual and is never
        // replayed: a second attempt could delete a queue that appeared since.
        var ambiguous = try Fixture.cleanSink()
        let (second, _) = try Fixture.installed(&ambiguous)
        ambiguous.queueRemovalOutcomeUnknown = true
        var secondRecovery = Fixture.recordValidated(second)
        XCTAssertEqual(
            secondRecovery.recover(using: &ambiguous),
            .residual(secondRecovery.record, .queueRemovalUnverified)
        )
        XCTAssertEqual(ambiguous.removalEvents, [.removeQueue(Fixture.queueName)])
        XCTAssertTrue(secondRecovery.record.owns(.schedulerQueue))
        XCTAssertNotNil(ambiguous.files[Fixture.filterPath])
    }

    /// The same rule for a file: what is deleted is the artifact that was
    /// validated, not whatever occupies the path by the time the call runs.
    func testFileDeletionIsConditionalOnTheValidatedArtifact() throws {
        var sink = try Fixture.cleanSink()
        let (transaction, _) = try Fixture.installed(&sink)
        sink.fileChangedBeforeRemoval[Fixture.descriptionPath] = try ObservedFileState(
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o644, contentSHA256: Fixture.digest("9"),
            accessControl: .noWriteGrantsBeyondOwner
        )
        var recovery = Fixture.recordValidated(transaction)
        XCTAssertEqual(recovery.recover(using: &sink), .residual(recovery.record, .unexpectedArtifactState))
        XCTAssertNotNil(sink.files[Fixture.descriptionPath])
        XCTAssertNotNil(sink.files[Fixture.filterPath])
        XCTAssertTrue(recovery.record.owns(.file(try AbsolutePath(Fixture.descriptionPath))))

        var ambiguous = try Fixture.cleanSink()
        let (second, _) = try Fixture.installed(&ambiguous)
        ambiguous.fileRemovalOutcomeUnknown.insert(Fixture.descriptionPath)
        var secondRecovery = Fixture.recordValidated(second)
        XCTAssertEqual(
            secondRecovery.recover(using: &ambiguous),
            .residual(secondRecovery.record, .fileRemovalUnverified)
        )
        XCTAssertTrue(secondRecovery.record.owns(.file(try AbsolutePath(Fixture.descriptionPath))))
    }

    // MARK: - The final boundary

    /// Finding 8: the queue is live from the moment `createQueue` returns, and
    /// what it points at can change before completion is claimed. Checking the
    /// queue's own token says nothing about the filter it runs.
    func testCompletionRevalidatesTheStagedArtifacts() throws {
        // The filter is replaced after the queue exists.
        var replaced = try Fixture.cleanSink()
        var transaction = try Fixture.queueCreated(&replaced)
        replaced.files[Fixture.filterPath] = try ObservedFileState(
            kind: .regularFile, uid: 0, gid: 0, modeBits: 0o755, contentSHA256: Fixture.digest("9"),
            accessControl: .noWriteGrantsBeyondOwner
        )
        let outcome = try transaction.complete(using: &replaced)
        XCTAssertFalse(outcome.isCompleted)
        XCTAssertTrue(outcome.requiresManualRecovery)
        XCTAssertEqual(outcome, .residual(transaction.record, .stagedArtifactChangedBeforeCompletion))
        XCTAssertEqual(transaction.record.phase, .residual)

        // Or removed outright.
        var removed = try Fixture.cleanSink()
        var second = try Fixture.queueCreated(&removed)
        removed.files.removeValue(forKey: Fixture.filterPath)
        XCTAssertEqual(
            try second.complete(using: &removed),
            .residual(second.record, .stagedArtifactChangedBeforeCompletion)
        )

        // Or the journal itself diverges.
        var diverged = try Fixture.cleanSink()
        var third = try Fixture.queueCreated(&diverged)
        diverged.journalOverrideOnRead = try QueueInstallationOwnershipRecord(
            transactionID: QueueInstallationTransactionID(hex: String(repeating: "a", count: 32)),
            intent: third.plan.intent, phase: .inProgress, createdArtifacts: []
        ).canonicalText
        XCTAssertEqual(
            try third.complete(using: &diverged),
            .residual(third.record, .stagedArtifactChangedBeforeCompletion)
        )

        // Untouched, the same sequence completes.
        var untouched = try Fixture.cleanSink()
        var fourth = try Fixture.queueCreated(&untouched)
        XCTAssertTrue(try fourth.complete(using: &untouched).isCompleted)
    }

    // MARK: - Loading a journal the record does not claim

    /// Finding 4: a canonical record may plan the journal while claiming to have
    /// created nothing. Its recovery plan is empty, so recovery would report a
    /// successful rollback while leaving that journal — and the root containing
    /// it — on disk. `load` has just proved the file exists, so it refuses.
    func testLoadRefusesAJournalTheRecordDoesNotClaimToOwn() throws {
        var sink = try Fixture.cleanSink()
        let intent = try Fixture.intent()
        let plan = try Fixture.plan(with: &sink, intent: intent)
        var transaction = try QueueInstallationTransaction(plan: plan)
        _ = try transaction.stage(using: &sink)
        XCTAssertNotNil(sink.files[Fixture.recordPath])

        let disowning = try QueueInstallationOwnershipRecord(
            transactionID: plan.transactionID, intent: intent, phase: .inProgress, createdArtifacts: []
        )
        XCTAssertFalse(disowning.owns(.file(try AbsolutePath(Fixture.recordPath))))
        // This is the shape of the problem: an empty plan reports a rollback.
        XCTAssertTrue(try QueueInstallationRecoveryPlan(record: disowning).steps.isEmpty)
        sink.journalOverrideOnRead = disowning.canonicalText

        XCTAssertThrowsError(try QueueInstallationRecovery.load(
            journalAt: intent.ownershipRecord, authority: .recordValidated, using: &sink
        )) { XCTAssertEqual($0 as? QueueInstallationError, .journalNotOwnedByRecord) }
        XCTAssertNotNil(sink.files[Fixture.recordPath])
        XCTAssertNotNil(sink.files[Fixture.rootPath])
    }
}
