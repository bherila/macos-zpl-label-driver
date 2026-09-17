import CryptoKit
import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class PrinterProfileStoreTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "PrinterProfileStore-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testFinishingProfileRevisionColdReadbackAndConflictingPolicyPreserveOriginal() throws {
        let root = try temporaryRoot(), base = try PrinterProfile.gc420dUSBReference()
        let fact = CapabilityFact(state: .supported,
            evidence: .documentedModel(sourceID: "synthetic-finishing-storage"))
        func qualified(_ maximum: Int) throws -> PrinterProfile {
            try .init(schemaVersion: 8, revision: 12, capabilities: base.capabilities,
                installedHardware: base.installedHardware, media: base.media, connection: base.connection,
                finishingConfiguration: .init(finishing: .init(modes: [.tearOff: fact], enabledModes: [.tearOff]),
                    stock: .init(media: base.media, compatibleModes: [
                        .tearOff: .observed(true, evidence: .reportedInstallation)]),
                    schedules: .init(batch: fact, maximumBatchSize: maximum)))
        }
        let original = try qualified(5), store = try PrinterProfileStore(root: root)
        let reference = try store.save(id: "synthetic-finishing", profile: original)
        XCTAssertEqual(reference.schemaVersion, 8)
        let cold = try PrinterProfileStore(root: root)
        XCTAssertEqual(try cold.load(reference: reference), original)
        XCTAssertThrowsError(try cold.save(id: reference.id, profile: qualified(4))) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .profileConflict)
        }
        XCTAssertEqual(try cold.load(reference: reference), original)
        XCTAssertEqual(try cold.load(reference: reference).finishingConfiguration?.schedules.maximumBatchSize, 5)
    }

    private func profile(model: String = "GC420d", revision: Int = 7) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: revision)
        return try PrinterProfile(
            schemaVersion: base.schemaVersion,
            revision: base.revision,
            capabilities: PrinterCapabilities(
                model: model,
                thermalTransfer: base.capabilities.thermalTransfer,
                cutter: base.capabilities.cutter,
                peeler: base.capabilities.peeler,
                rewind: base.capabilities.rewind,
                tracking: base.capabilities.tracking,
                printSpeedChoicesIps: base.capabilities.printSpeedChoicesIps,
                darkness: base.capabilities.darkness
            ),
            installedHardware: base.installedHardware,
            media: base.media,
            connection: base.connection
        )
    }

    func testImmutableProfileRoundTripReturnsCanonicalReference() throws {
        let store = try PrinterProfileStore(root: temporaryRoot())
        let value = try profile()
        let reference = try store.save(id: "gc420d-usb", profile: value)
        XCTAssertEqual(try store.save(id: "gc420d-usb", profile: value), reference)
        XCTAssertEqual(try store.load(reference: reference), value)
        let stored = try store.load(id: reference.id, revision: reference.revision)
        XCTAssertEqual(stored.reference, reference)
        XCTAssertEqual(stored.profile, value)
        XCTAssertFalse(PrinterProfileStore.fileName(reference.id, reference.revision).contains("/"))
    }

    func testWrongDigestAndConflictingBytesFailClosed() throws {
        let store = try PrinterProfileStore(root: temporaryRoot())
        let reference = try store.save(id: "gc420d-usb", profile: profile())
        let wrong = try ImmutableProfileReference(
            id: reference.id, revision: reference.revision,
            sha256: String(repeating: "d", count: 64)
        )
        XCTAssertThrowsError(try store.load(reference: wrong)) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .profileIdentityMismatch)
        }
        XCTAssertThrowsError(try store.save(id: "gc420d-usb", profile: profile(model: "Changed"))) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .profileConflict)
        }
        XCTAssertEqual(try store.load(reference: reference), try profile())
        XCTAssertThrowsError(try store.save(id: "../printer", profile: profile())) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .profileIdentityMismatch)
        }
    }

    func testTamperedRevisionAndUnsafeRootAreRejected() throws {
        let root = try temporaryRoot()
        let store = try PrinterProfileStore(root: root)
        let reference = try store.save(id: "gc420d-usb", profile: profile())
        let target = root.appending(path: "printer-profiles").appending(
            path: PrinterProfileStore.fileName(reference.id, reference.revision)
        )
        try PrinterProfileJSON.encode(profile(revision: 8)).write(to: target)
        XCTAssertThrowsError(try store.load(reference: reference)) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .profileIdentityMismatch)
        }
        try Data("{}".utf8).write(to: target)
        XCTAssertThrowsError(try store.load(reference: reference)) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .cannotRead)
        }

        let insecure = FileManager.default.temporaryDirectory.appending(
            path: "PrinterProfileStore-insecure-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: insecure) }
        try FileManager.default.createDirectory(at: insecure, withIntermediateDirectories: false)
        chmod(insecure.path, 0o755)
        XCTAssertThrowsError(try PrinterProfileStore(root: insecure)) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .unsafeStoreDirectory)
        }
    }

    func testConcurrentConflictingWritersLeaveOneCompleteWinner() async throws {
        let store = try PrinterProfileStore(root: temporaryRoot())
        let first = try profile()
        let second = try profile(model: "Changed")
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { (try? store.save(id: "gc420d-usb", profile: first)) != nil }
            group.addTask { (try? store.save(id: "gc420d-usb", profile: second)) != nil }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let stored = try store.load(id: "gc420d-usb", revision: 7).profile
        XCTAssertTrue(stored == first || stored == second)
    }

    func testPostRenameSyncFailureReturnsExactRecoverableIdentity() throws {
        let root = try temporaryRoot()
        let storage = try PrivateImmutableDirectory(
            root: root, syncDirectory: { _ in -1 }
        )
        let faulted = PrinterProfileStore(root: root, storage: storage)
        let value = try profile()
        let bytes = try PrinterProfileJSON.encode(value)
        let identity = ImmutablePublicationIdentity(
            id: "gc420d-usb", schemaVersion: value.schemaVersion,
            revision: value.revision, sha256: Self.digest(bytes)
        )
        XCTAssertThrowsError(try faulted.save(id: identity.id, profile: value)) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .commitUncertain(identity))
        }

        let normal = try PrinterProfileStore(root: root)
        let stored = try normal.load(id: identity.id, revision: identity.revision)
        XCTAssertEqual(stored.profile, value)
        XCTAssertEqual(stored.reference.sha256, identity.sha256)
        XCTAssertEqual(try normal.save(id: identity.id, profile: value), stored.reference)
        XCTAssertThrowsError(try normal.save(
            id: identity.id, profile: profile(model: "Changed")
        )) { XCTAssertEqual($0 as? PrinterProfileStore.Error, .profileConflict) }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func testBoundedCatalogUsesExactIdentityAndCanonicalRevisionNames() throws {
        let store = try PrinterProfileStore(root: temporaryRoot())
        let first = try store.save(id: "synthetic-printer", profile: profile(revision: 7))
        let second = try store.save(id: "synthetic-printer", profile: profile(revision: 8))
        _ = try store.save(id: "another-printer", profile: profile(revision: 9))
        XCTAssertEqual(try store.savedProfiles(id: "synthetic-printer").map(\.reference), [second, first])
        XCTAssertTrue(try store.savedProfiles(id: "absent-printer").isEmpty)
        XCTAssertThrowsError(try store.savedProfiles(id: "synthetic-printer", maximumProfiles: 2))
        XCTAssertThrowsError(try store.savedProfiles(id: "../printer"))
        let target = store.root.appending(path: "printer-profiles").appending(path: PrinterProfileStore.fileName("synthetic-printer", 7))
        try PrinterProfileJSON.encode(profile(revision: 10)).write(to: target)
        XCTAssertThrowsError(try store.savedProfiles(id: "synthetic-printer"))
    }

    func testCatalogRejectsNoncanonicalRecordBytesAndSymlinkSubstitution() throws {
        let store = try PrinterProfileStore(root: temporaryRoot())
        let reference = try store.save(id: "synthetic-printer", profile: profile())
        let target = store.root.appending(path: "printer-profiles").appending(path: PrinterProfileStore.fileName(reference.id, reference.revision))
        let bytes = try Data(contentsOf: target)
        try (bytes + Data("\n".utf8)).write(to: target)
        XCTAssertThrowsError(try store.savedProfiles(id: reference.id))
        try FileManager.default.removeItem(at: target)
        let outside = store.root.appending(path: "synthetic-outside.json")
        try bytes.write(to: outside)
        XCTAssertEqual(symlink(outside.path, target.path), 0)
        XCTAssertThrowsError(try store.savedProfiles(id: reference.id))
    }

    func testCapacityAdmissionPreservesExistingRecordsAndIdempotentReadback() throws {
        let store = try PrinterProfileStore(root: temporaryRoot())
        var first: ImmutableProfileReference?
        for revision in 1...256 {
            let reference = try store.save(id: "synthetic-printer", profile: profile(revision: revision))
            if revision == 1 { first = reference }
        }
        XCTAssertEqual(try store.savedProfiles(id: "synthetic-printer").count, 256)
        XCTAssertThrowsError(try store.save(id: "synthetic-printer", profile: profile(revision: 257))) {
            XCTAssertEqual($0 as? PrinterProfileStore.Error, .catalogCapacityReached)
        }
        XCTAssertEqual(try store.save(id: "synthetic-printer", profile: profile(revision: 1)), first)
        XCTAssertEqual(try store.load(reference: XCTUnwrap(first)), try profile(revision: 1))
    }

}
