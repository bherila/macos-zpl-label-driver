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

    func testProfileRejectsUnsafeIdentityAndImpossibleSpeedObservations() throws {
        let reference = try PrinterProfile.gc420dUSBReference()
        let badModels = ["", "GC420d\nforged"]
        for model in badModels {
            let capabilities = PrinterCapabilities(
                model: model,
                thermalTransfer: reference.capabilities.thermalTransfer,
                cutter: reference.capabilities.cutter,
                peeler: reference.capabilities.peeler,
                rewind: reference.capabilities.rewind,
                tracking: reference.capabilities.tracking,
                printSpeedChoicesIps: reference.capabilities.printSpeedChoicesIps,
                darkness: reference.capabilities.darkness
            )
            XCTAssertThrowsError(try PrinterProfile(
                schemaVersion: 1,
                revision: 1,
                capabilities: capabilities,
                installedHardware: reference.installedHardware
            )) { XCTAssertEqual($0 as? PrinterProfileError, .invalidModelIdentifier) }
        }

        let invalidChoices = PrinterCapabilities(
            model: reference.capabilities.model,
            thermalTransfer: reference.capabilities.thermalTransfer,
            cutter: reference.capabilities.cutter,
            peeler: reference.capabilities.peeler,
            rewind: reference.capabilities.rewind,
            tracking: reference.capabilities.tracking,
            printSpeedChoicesIps: [0, 2],
            darkness: reference.capabilities.darkness
        )
        XCTAssertThrowsError(try PrinterProfile(
            schemaVersion: 1,
            revision: 1,
            capabilities: invalidChoices,
            installedHardware: reference.installedHardware
        )) { XCTAssertEqual($0 as? PrinterProfileError, .invalidPrintSpeedChoice) }

        let impossibleObservation = InstalledHardware(
            transport: reference.installedHardware.transport,
            selectedFinishing: reference.installedHardware.selectedFinishing,
            cutter: reference.installedHardware.cutter,
            peeler: reference.installedHardware.peeler,
            currentSpeedIps: 0,
            currentDarkness: reference.installedHardware.currentDarkness,
            currentTracking: reference.installedHardware.currentTracking
        )
        XCTAssertThrowsError(try PrinterProfile(
            schemaVersion: 1,
            revision: 1,
            capabilities: reference.capabilities,
            installedHardware: impossibleObservation
        )) { XCTAssertEqual($0 as? PrinterProfileError, .invalidInstalledPrintSpeed) }
    }

    func testResolutionBindsProfileRevisionAndPreservesUnknownSettings() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 41)
        let resolved = try profile.resolveControls(job: .init())
        XCTAssertEqual(resolved.profileSchemaVersion, 1)
        XCTAssertEqual(resolved.profileRevision, 41)
        XCTAssertEqual(resolved.thermalMethod, .value(.directThermal))
        XCTAssertEqual(resolved.finishing, .value(.tearOff))
        XCTAssertEqual(resolved.printSpeedIps, .leaveUnchanged)
        XCTAssertEqual(resolved.darkness, .leaveUnchanged)
        XCTAssertEqual(resolved.tracking, .leaveUnchanged)
    }

    func testJobControlsOverrideWorkflowDefaultsAndUnsupportedDefaultsFail() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let resolved = try profile.resolveControls(
            job: .init(printSpeedIps: 4),
            workflowDefaults: .init(printSpeedIps: 2)
        )
        XCTAssertEqual(resolved.printSpeedIps, .value(4))
        XCTAssertThrowsError(try profile.resolveControls(
            job: .init(), workflowDefaults: .init(printSpeedIps: 5)
        )) { XCTAssertEqual($0 as? PrinterProfileError, .unsupportedPrintSpeed(5)) }
    }
}
