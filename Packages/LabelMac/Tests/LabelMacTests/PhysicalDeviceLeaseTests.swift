import Foundation
import Darwin
import XCTest
@testable import LabelMac

final class PhysicalDeviceLeaseTests: XCTestCase {
    func testRejectsLooseRootAndUnsafeLockMetadataWithoutChangingThem() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try PhysicalDeviceIdentity(stableIdentifier: "synthetic-device")
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)) {
            XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .invalidLockDirectory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let first = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)
        let lock = first.lockFileURL
        first.release()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lock.path)
        XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)) {
            XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .unsafeLockFile)
        }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: lock.path)[.posixPermissions] as? NSNumber, 0o644)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lock.path)
        let contents = Data("untrusted lock content".utf8)
        try contents.write(to: lock)
        XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)) {
            XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .unsafeLockFile)
        }
        XCTAssertEqual(try Data(contentsOf: lock), contents)
    }

    func testRejectsSymlinkRootWithoutCreatingAnythingInTarget() throws {
        let target = try makeDirectory()
        let alias = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        XCTAssertThrowsError(try PhysicalDeviceLease(
            acquiring: PhysicalDeviceIdentity(stableIdentifier: "synthetic-device"),
            inExistingDirectory: alias)) {
                XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .invalidLockDirectory)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
    }

    func testRootReplacementDuringAcquisitionFailsWithoutUsingReplacementNamespace() throws {
        for phase in [PhysicalDeviceLease.AcquisitionCheckpoint.opened, .locked] {
            let root = try makeDirectory()
            let detached = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: root)
                try? FileManager.default.removeItem(at: detached)
            }
            let identity = try PhysicalDeviceIdentity(stableIdentifier: "synthetic-device")
            XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: root, checkpoint: { point in
                guard point == phase else { return }
                try FileManager.default.moveItem(at: root, to: detached)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
            })) { XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .invalidLockDirectory) }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
            let recovered = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: detached)
            recovered.release()
        }
    }

    func testNamedLockReplacementDuringAcquisitionFailsAndClosesOriginalLease() throws {
        for phase in [PhysicalDeviceLease.AcquisitionCheckpoint.opened, .locked] {
            let root = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let identity = try PhysicalDeviceIdentity(stableIdentifier: "synthetic-device")
            let seed = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: root)
            let lock = seed.lockFileURL
            seed.release()
            let detached = root.appendingPathComponent("detached.lock")
            XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: root, checkpoint: { point in
                guard point == phase else { return }
                try FileManager.default.moveItem(at: lock, to: detached)
                XCTAssertEqual(Darwin.close(Darwin.open(lock.path, O_CREAT | O_EXCL | O_WRONLY, mode_t(0o600))), 0)
            })) { XCTAssertEqual($0 as? PhysicalDeviceLeaseError, .unsafeLockFile) }
            try FileManager.default.removeItem(at: lock)
            try FileManager.default.moveItem(at: detached, to: lock)
            let recovered = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: root)
            recovered.release()
        }
    }

    func testAliasCannotAcquireWhileLeaseIsHeldAndReleaseIsReusable() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try PhysicalDeviceIdentity(stableIdentifier: "usb-stable-test-device")
        let first = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)
        XCTAssertTrue(first.isHeld)
        XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)) { error in
            XCTAssertEqual(error as? PhysicalDeviceLeaseError, .alreadyHeld)
        }
        first.release()
        XCTAssertFalse(first.isHeld)
        let second = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)
        XCTAssertTrue(second.isHeld)
        second.release()
    }

    func testIdentifiersAreOpaqueOnDiskAndInvalidInputsAreRejected() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try PhysicalDeviceIdentity(stableIdentifier: ""))
        XCTAssertThrowsError(try PhysicalDeviceIdentity(stableIdentifier: "contains whitespace"))
        let identity = try PhysicalDeviceIdentity(stableIdentifier: "usb-stable-test-device")
        let lease = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)
        XCTAssertFalse(lease.lockFileURL.lastPathComponent.contains("usb-stable-test-device"))
        XCTAssertEqual(lease.lockFileURL.pathExtension, "lock")
        lease.release()
    }

    func testRejectsMissingLockDirectory() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let identity = try PhysicalDeviceIdentity(stableIdentifier: "usb-stable-test-device")
        XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: missing)) { error in
            XCTAssertEqual(error as? PhysicalDeviceLeaseError, .invalidLockDirectory)
        }
    }

    func testChildTerminationReleasesKernelLease() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = "usb-stable-child-lifetime-test"
        let child = Process()
        child.executableURL = diagnosticsURL()
        child.arguments = ["--hold-device-lease", directory.path, identifier, "5000"]
        let output = Pipe()
        child.standardOutput = output
        try child.run()
        XCTAssertEqual(String(data: output.fileHandleForReading.availableData, encoding: .utf8), "lease-acquired\n")

        let identity = try PhysicalDeviceIdentity(stableIdentifier: identifier)
        XCTAssertThrowsError(try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)) { error in
            XCTAssertEqual(error as? PhysicalDeviceLeaseError, .alreadyHeld)
        }
        child.terminate()
        child.waitUntilExit()
        let lease = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: directory)
        XCTAssertTrue(lease.isHeld)
        lease.release()
    }

    private func makeDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func diagnosticsURL() -> URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("label-driver-diagnostics")
    }
}
