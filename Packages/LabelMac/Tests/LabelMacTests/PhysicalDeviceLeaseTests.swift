import Foundation
import XCTest
@testable import LabelMac

final class PhysicalDeviceLeaseTests: XCTestCase {
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
