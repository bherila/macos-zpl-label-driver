import XCTest
@testable import LabelCore

final class PrinterProfileTests: XCTestCase {
    func testGC420dReferencePreservesModelAndInstalledFactBoundaries() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        XCTAssertEqual(profile.schemaVersion, 1)
        XCTAssertEqual(profile.revision, 7)
        XCTAssertEqual(profile.capabilities.model, "GC420d")
        XCTAssertEqual(profile.capabilities.thermalTransfer.state, .unsupported)
        XCTAssertEqual(profile.capabilities.cutter.state, .unknown)
        XCTAssertEqual(profile.installedHardware.cutter.state, .unsupported)
        XCTAssertEqual(profile.installedHardware.peeler.state, .unknown)
        XCTAssertNil(profile.installedHardware.currentSpeedIps)
        XCTAssertNil(profile.installedHardware.currentDarkness)
        XCTAssertNil(profile.installedHardware.currentTracking)
        XCTAssertEqual(profile.installedHardware.transport, .usb)
    }

    func testGC420dAcceptsOnlyDocumentedSpeedChoicesAndTearOff() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        XCTAssertNoThrow(try profile.validate(.init(
            thermalMethod: .directThermal,
            finishing: .tearOff,
            printSpeedIps: 3
        )))
        for speed in [1, 5] {
            XCTAssertThrowsError(try profile.validate(.init(printSpeedIps: speed))) {
                XCTAssertEqual($0 as? PrinterProfileError, .unsupportedPrintSpeed(speed))
            }
        }
    }

    func testGC420dRejectsForgedUnsupportedAndUnverifiedControls() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let cases: [(PrinterControlRequest, PrinterProfileError)] = [
            (.init(thermalMethod: .thermalTransfer), .unsupportedThermalMethod(.thermalTransfer)),
            (.init(finishing: .cut), .unsupportedFinishing(.cut)),
            (.init(finishing: .peel), .unsupportedFinishing(.peel)),
            (.init(finishing: .rewind), .unsupportedFinishing(.rewind)),
            (.init(darkness: 10), .unavailableDarkness),
            (.init(tracking: .gap), .unavailableTracking(.gap)),
            (.init(tracking: .continuous), .unavailableTracking(.continuous)),
        ]
        for (request, expected) in cases {
            XCTAssertThrowsError(try profile.validate(request)) { XCTAssertEqual($0 as? PrinterProfileError, expected) }
        }
    }

    func testAbsentControlMeansLeaveUnchangedRatherThanGuessedDefault() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        XCTAssertNoThrow(try profile.validate(.init()))
        XCTAssertNil(profile.installedHardware.currentSpeedIps)
    }

    func testProfileVersionIsBounded() throws {
        let reference = try PrinterProfile.gc420dUSBReference()
        XCTAssertThrowsError(try PrinterProfile(
            schemaVersion: 2,
            revision: 1,
            capabilities: reference.capabilities,
            installedHardware: reference.installedHardware
        )) { XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion) }
    }
}
