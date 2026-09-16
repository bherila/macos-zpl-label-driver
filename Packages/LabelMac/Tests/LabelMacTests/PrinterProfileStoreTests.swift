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
}
