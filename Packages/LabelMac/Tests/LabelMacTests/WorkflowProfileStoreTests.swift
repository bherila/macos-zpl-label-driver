import CryptoKit
import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class WorkflowProfileStoreTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "WorkflowProfileStore-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func profile(revision: Int = 1, x: Double = 0.1) throws -> WorkflowProfile {
        let page = try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        let region = try NormalizedRect(x: x, y: 0.2, width: 0.4, height: 0.5)
        return try WorkflowProfile(
            id: "letter/profile", revision: revision,
            outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(
                width: try Millimeters.inches(4), height: try Millimeters.inches(6)
            ),
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(
                    uprightPhysicalSize: try page.effectivePhysicalSize()
                ),
                disposition: .extract([try ExtractionRegion(
                    id: "label", normalizedRect: region, outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "border", kind: .border, normalizedRect: region
                )]
            )]
        )
    }

    func testImmutableProfileRoundTripAndIdempotentSave() throws {
        let store = try WorkflowProfileStore(root: temporaryRoot())
        let value = try profile()
        try store.save(value)
        try store.save(value)
        XCTAssertEqual(try store.load(profileID: value.id, revision: value.revision), value)
        XCTAssertFalse(WorkflowProfileStore.profileFileName(value.id, value.revision).contains("/"))
    }

    func testSameIdentityWithDifferentBytesIsAConflict() throws {
        let store = try WorkflowProfileStore(root: temporaryRoot())
        try store.save(profile())
        XCTAssertThrowsError(try store.save(profile(x: 0.2))) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .profileConflict)
        }
        XCTAssertEqual(try store.load(profileID: "letter/profile", revision: 1), try profile())
    }

    func testQualificationIsSeparateExactAndNotImported() throws {
        let store = try WorkflowProfileStore(root: temporaryRoot())
        let value = try profile()
        let imported = try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(value))
        try store.save(imported)
        XCTAssertNil(try store.qualification(for: imported))

        try store.confirmForUnattendedUse(imported)
        XCTAssertNotNil(try store.qualification(for: imported))
        XCTAssertThrowsError(try store.qualification(for: profile(revision: 2))) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .cannotRead)
        }
        XCTAssertThrowsError(try store.qualification(for: profile(x: 0.2))) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .profileConflict)
        }
    }

    func testTamperedQualificationFailsClosed() throws {
        let root = try temporaryRoot()
        let store = try WorkflowProfileStore(root: root)
        let value = try profile()
        try store.save(value)
        try store.confirmForUnattendedUse(value)
        let qualification = root.appending(path: "qualifications").appending(
            path: WorkflowProfileStore.qualificationFileName(value.id, value.revision)
        )
        let tampered = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "profileID": value.id,
            "profileRevision": value.revision,
            "profileSHA256": String(repeating: "0", count: 64),
        ], options: [.sortedKeys])
        try tampered.write(to: qualification)
        XCTAssertThrowsError(try store.qualification(for: value)) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .qualificationMismatch)
        }
    }

    func testRejectsSymlinkAndInsecureStoreRoots() throws {
        let parent = try temporaryRoot()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let target = parent.appending(path: "target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        chmod(target.path, 0o700)
        let link = parent.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try WorkflowProfileStore(root: link)) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .cannotOpenStore)
        }

        let insecure = parent.appending(path: "insecure")
        try FileManager.default.createDirectory(at: insecure, withIntermediateDirectories: false)
        chmod(insecure.path, 0o755)
        XCTAssertThrowsError(try WorkflowProfileStore(root: insecure)) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .unsafeStoreDirectory)
        }
    }

    func testConcurrentConflictingWritersNeverReplaceWinner() async throws {
        let store = try WorkflowProfileStore(root: temporaryRoot())
        let first = try profile(x: 0.1)
        let second = try profile(x: 0.2)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { (try? store.save(first)) != nil }
            group.addTask { (try? store.save(second)) != nil }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let stored = try store.load(profileID: first.id, revision: first.revision)
        XCTAssertTrue(stored == first || stored == second)
    }

    func testProfilePublicationReportsAndRecoversExactCommitUncertainty() throws {
        let root = try temporaryRoot()
        let sync = FailingDirectorySync()
        let storage = try PrivateImmutableDirectory(
            root: root, syncDirectory: sync.call
        )
        let faulted = WorkflowProfileStore(root: root, storage: storage)
        let value = try profile()
        let bytes = try WorkflowProfileJSON.encode(value)
        let identity = ImmutablePublicationIdentity(
            id: value.id, schemaVersion: value.schemaVersion,
            revision: value.revision, sha256: Self.digest(bytes)
        )
        for _ in 0..<2 {
            XCTAssertThrowsError(try faulted.save(value)) {
                XCTAssertEqual($0 as? WorkflowProfileStore.Error, .commitUncertain(identity))
            }
        }
        XCTAssertEqual(sync.count, 2)

        let normal = try WorkflowProfileStore(root: root)
        XCTAssertEqual(try normal.load(
            profileID: value.id, revision: value.revision
        ), value)
        try normal.save(value)
        XCTAssertThrowsError(try normal.save(profile(x: 0.2))) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .profileConflict)
        }
    }

    func testQualificationPublicationReportsAndRecoversExactCommitUncertainty() throws {
        let root = try temporaryRoot()
        let normal = try WorkflowProfileStore(root: root)
        let value = try profile()
        try normal.save(value)
        let bytes = try WorkflowProfileJSON.encode(value)
        let identity = ImmutablePublicationIdentity(
            id: value.id, schemaVersion: value.schemaVersion,
            revision: value.revision, sha256: Self.digest(bytes)
        )
        let sync = FailingDirectorySync()
        let storage = try PrivateImmutableDirectory(
            root: root, syncDirectory: sync.call
        )
        let faulted = WorkflowProfileStore(root: root, storage: storage)
        for _ in 0..<2 {
            XCTAssertThrowsError(try faulted.confirmForUnattendedUse(value)) {
                XCTAssertEqual($0 as? WorkflowProfileStore.Error, .commitUncertain(identity))
            }
        }
        XCTAssertEqual(sync.count, 2)
        XCTAssertNotNil(try normal.qualification(for: value))
        try normal.confirmForUnattendedUse(value)
    }

    func testFailureBeforeRenameLeavesNoPublishedRecord() throws {
        enum Injected: Swift.Error { case stop }
        let root = try temporaryRoot()
        let storage = try PrivateImmutableDirectory(
            root: root,
            injectFault: { point in
                if point == .beforeRename { throw Injected.stop }
            }
        )
        XCTAssertThrowsError(try storage.publish(
            Data("bounded".utf8), directory: "profiles",
            fileName: "before-rename.json", maximumBytes: 32
        )) { XCTAssertEqual($0 as? PrivateImmutableDirectory.Error, .cannotWrite) }
        XCTAssertThrowsError(try storage.read(
            directory: "profiles", fileName: "before-rename.json", maximumBytes: 32
        )) { XCTAssertEqual($0 as? PrivateImmutableDirectory.Error, .notFound) }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: root.appending(path: "profiles"),
                includingPropertiesForKeys: nil
            ), []
        )
    }

    func testFirstPublicationRequiresCategoryRootAndContainingDirectoryBarriers() throws {
        let root = try temporaryRoot()
        let sync = SequencedDirectorySync(results: [0, 0, -1])
        let storage = try PrivateImmutableDirectory(
            root: root, syncDirectory: sync.call
        )
        let faulted = WorkflowProfileStore(root: root, storage: storage)
        let value = try profile()
        let bytes = try WorkflowProfileJSON.encode(value)
        let identity = ImmutablePublicationIdentity(
            id: value.id, schemaVersion: value.schemaVersion,
            revision: value.revision, sha256: Self.digest(bytes)
        )

        XCTAssertThrowsError(try faulted.save(value)) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .commitUncertain(identity))
        }
        XCTAssertEqual(sync.count, 3)
        XCTAssertEqual(try faulted.load(
            profileID: value.id, revision: value.revision
        ), value)

        try faulted.save(value)
        XCTAssertEqual(sync.count, 6)
        XCTAssertThrowsError(try faulted.save(profile(x: 0.2))) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .profileConflict)
        }
    }

    func testIdenticalUncertainRetryReconcilesBeforeFallibleStaging() throws {
        let root = try temporaryRoot()
        let value = try profile()
        let bytes = try WorkflowProfileJSON.encode(value)
        let identity = ImmutablePublicationIdentity(
            id: value.id, schemaVersion: value.schemaVersion,
            revision: value.revision, sha256: Self.digest(bytes)
        )
        let initialSync = FailingDirectorySync()
        let initial = WorkflowProfileStore(
            root: root,
            storage: try PrivateImmutableDirectory(
                root: root, syncDirectory: initialSync.call
            )
        )
        XCTAssertThrowsError(try initial.save(value)) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .commitUncertain(identity))
        }

        let fault = CountingInjectedFault()
        let retrySync = SequencedDirectorySync(results: [0, -1])
        let retry = WorkflowProfileStore(
            root: root,
            storage: try PrivateImmutableDirectory(
                root: root, syncDirectory: retrySync.call,
                injectFault: fault.call
            )
        )
        XCTAssertThrowsError(try retry.save(value)) {
            XCTAssertEqual($0 as? WorkflowProfileStore.Error, .commitUncertain(identity))
        }
        XCTAssertEqual(fault.count, 0)
        XCTAssertEqual(retrySync.count, 2)
        XCTAssertEqual(try retry.load(
            profileID: value.id, revision: value.revision
        ), value)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class FailingDirectorySync: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int {
        lock.withLock { calls }
    }

    func call(_ descriptor: Int32) -> Int32 {
        _ = descriptor
        lock.withLock { calls += 1 }
        return -1
    }
}

private final class SequencedDirectorySync: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Int32]
    private var calls = 0

    init(results: [Int32]) {
        self.results = results
    }

    var count: Int {
        lock.withLock { calls }
    }

    func call(_ descriptor: Int32) -> Int32 {
        _ = descriptor
        return lock.withLock {
            calls += 1
            return results.isEmpty ? 0 : results.removeFirst()
        }
    }
}

private final class CountingInjectedFault: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int {
        lock.withLock { calls }
    }

    func call(_ point: PrivateImmutableDirectory.FaultPoint) throws {
        _ = point
        lock.withLock { calls += 1 }
        throw PrivateImmutableDirectory.Error.cannotWrite
    }
}
