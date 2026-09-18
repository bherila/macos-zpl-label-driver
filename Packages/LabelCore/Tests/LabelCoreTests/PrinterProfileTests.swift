import XCTest
@testable import LabelCore

final class PrinterProfileTests: XCTestCase {
    func testConnectionIdentityDumpDoesNotExposePrivateProfileValue() throws {
        let identity = try StableConnectionIdentity(opaqueValue: "usb://synthetic.example.test/private-token")
        var output = ""
        dump([identity], to: &output)
        XCTAssertFalse(output.contains("synthetic.example.test"))
        XCTAssertFalse(output.contains("private-token"))
        XCTAssertTrue(Mirror(reflecting: identity).children.isEmpty)
        XCTAssertEqual(identity.privateProfileValue, "usb://synthetic.example.test/private-token")
        XCTAssertEqual(identity, try StableConnectionIdentity(opaqueValue: identity.privateProfileValue))
    }

    func testGC420dReferencePreservesModelAndInstalledFactBoundaries() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 7)
        XCTAssertEqual(profile.schemaVersion, 1)
        XCTAssertEqual(profile.revision, 7)
        XCTAssertEqual(profile.capabilities.model, "GC420d")
        XCTAssertEqual(profile.capabilities.thermalTransfer.state, .unsupported)
        XCTAssertEqual(profile.capabilities.cutter.state, .unknown)
        XCTAssertEqual(profile.installedHardware.cutter.state, .unsupported)
        XCTAssertEqual(profile.installedHardware.peeler.state, .unknown)
        XCTAssertNil(profile.installedHardware.observedSpeedIps)
        XCTAssertNil(profile.installedHardware.observedDarkness)
        XCTAssertNil(profile.installedHardware.observedTracking)
        XCTAssertEqual(profile.installedHardware.transport, .usb)
        XCTAssertEqual(profile.media.form, .observed(.preCut, evidence: .reportedInstallation))
        XCTAssertEqual(profile.media.nominalLabelFace, .observed(
            try PhysicalSize(width: Millimeters.inches(4), height: Millimeters.inches(6)),
            evidence: .reportedInstallation
        ))
        XCTAssertEqual(profile.media.configuredTracking, .unobserved)
        XCTAssertEqual(profile.media.calibration, .unobserved)
        XCTAssertEqual(profile.connection.transport, .usb)
        XCTAssertEqual(profile.connection.stableIdentity, .unobserved)
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
        XCTAssertNil(profile.installedHardware.observedSpeedIps)
    }

    func testProfileVersionIsBounded() throws {
        let reference = try PrinterProfile.gc420dUSBReference()
        XCTAssertThrowsError(try PrinterProfile(
            schemaVersion: 9,
            revision: 1,
            capabilities: reference.capabilities,
            installedHardware: reference.installedHardware,
            media: reference.media,
            connection: reference.connection
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
                installedHardware: reference.installedHardware,
                media: reference.media,
                connection: reference.connection
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
            installedHardware: reference.installedHardware,
            media: reference.media,
            connection: reference.connection
        )) { XCTAssertEqual($0 as? PrinterProfileError, .invalidPrintSpeedChoice) }

        let impossibleObservation = InstalledHardware(
            transport: reference.installedHardware.transport,
            selectedFinishing: reference.installedHardware.selectedFinishing,
            cutter: reference.installedHardware.cutter,
            peeler: reference.installedHardware.peeler,
            observedSpeedIps: 0,
            observedDarkness: reference.installedHardware.observedDarkness,
            observedTracking: reference.installedHardware.observedTracking
        )
        XCTAssertThrowsError(try PrinterProfile(
            schemaVersion: 1,
            revision: 1,
            capabilities: reference.capabilities,
            installedHardware: impossibleObservation,
            media: reference.media,
            connection: reference.connection
        )) { XCTAssertEqual($0 as? PrinterProfileError, .invalidInstalledPrintSpeed) }
    }

    func testMediaCalibrationCannotBeInventedFromNominalStock() throws {
        XCTAssertThrowsError(try MediaCalibration(
            widthDots: 0,
            lengthDots: 1,
            originXDot: 0,
            originYDot: 0
        )) { XCTAssertEqual($0 as? MediaConfigurationError, .invalidCalibrationDimensions) }

        let profile = try PrinterProfile.gc420dUSBReference()
        guard case .observed(let face, evidence: .reportedInstallation) = profile.media.nominalLabelFace else {
            return XCTFail("expected the reported nominal face")
        }
        XCTAssertEqual(face.width.value, 101.6, accuracy: 0.000_001)
        XCTAssertEqual(face.height.value, 152.4, accuracy: 0.000_001)
        XCTAssertEqual(profile.media.calibration, .unobserved)
    }

    func testExplicitMediaGeometryIsValidatedThenRejectedUntilQualified() throws {
        XCTAssertThrowsError(try MediaGeometryRequest(widthDots: 0)) {
            XCTAssertEqual($0 as? MediaConfigurationError, .invalidCalibrationDimensions)
        }

        let profile = try PrinterProfile.gc420dUSBReference()
        let request = try MediaGeometryRequest(
            widthDots: 813,
            lengthDots: 1_219,
            originXDot: 0,
            originYDot: 0
        )
        XCTAssertThrowsError(try profile.resolveControls(job: .init(mediaGeometry: request))) {
            XCTAssertEqual($0 as? PrinterProfileError, .unavailableMediaGeometry)
        }
        XCTAssertThrowsError(try profile.resolveControls(
            job: .init(),
            workflowDefaults: .init(mediaGeometry: request)
        )) { XCTAssertEqual($0 as? PrinterProfileError, .unavailableMediaGeometry) }
    }

    func testConnectionIdentityIsValidatedAndRedactedByDefault() throws {
        XCTAssertThrowsError(try StableConnectionIdentity(opaqueValue: ""))
        XCTAssertThrowsError(try StableConnectionIdentity(opaqueValue: "usb identity"))
        let identity = try StableConnectionIdentity(opaqueValue: "synthetic-usb-identity")
        XCTAssertEqual(String(describing: identity), "StableConnectionIdentity(redacted)")
        XCTAssertEqual(String(reflecting: identity), "StableConnectionIdentity(redacted)")
    }

    func testProfileCannotSubstituteRawTCPForInstalledUSB() throws {
        let reference = try PrinterProfile.gc420dUSBReference()
        let substitutedConnection = ConnectionConfiguration(transport: .rawTCP, stableIdentity: .unobserved)
        XCTAssertThrowsError(try PrinterProfile(
            schemaVersion: 1,
            revision: 1,
            capabilities: reference.capabilities,
            installedHardware: reference.installedHardware,
            media: reference.media,
            connection: substitutedConnection
        )) { XCTAssertEqual($0 as? PrinterProfileError, .inconsistentConnectionTransport) }
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

    func testObservationsNeitherAuthorizeCommandsNorBreakUnchangedJobs() throws {
        let reference = try PrinterProfile.gc420dUSBReference(revision: 42)
        let observedHardware = InstalledHardware(
            transport: reference.installedHardware.transport,
            selectedFinishing: reference.installedHardware.selectedFinishing,
            cutter: reference.installedHardware.cutter,
            peeler: reference.installedHardware.peeler,
            observedSpeedIps: 3,
            observedDarkness: 12,
            observedTracking: .gap
        )
        let observedProfile = try PrinterProfile(
            schemaVersion: reference.schemaVersion,
            revision: reference.revision,
            capabilities: reference.capabilities,
            installedHardware: observedHardware,
            media: reference.media,
            connection: reference.connection
        )

        let unchanged = try observedProfile.resolveControls(job: .init())
        XCTAssertEqual(unchanged.printSpeedIps, .leaveUnchanged)
        XCTAssertEqual(unchanged.darkness, .leaveUnchanged)
        XCTAssertEqual(unchanged.tracking, .leaveUnchanged)
        XCTAssertEqual(
            String(decoding: try ZPLControlEncoder().encode(unchanged), as: UTF8.self),
            "^MMT\n"
        )
        XCTAssertEqual(
            try observedProfile.resolveControls(job: .init(printSpeedIps: 3)).printSpeedIps,
            .value(3)
        )
        XCTAssertThrowsError(try observedProfile.resolveControls(job: .init(darkness: 12))) {
            XCTAssertEqual($0 as? PrinterProfileError, .unavailableDarkness)
        }
        XCTAssertThrowsError(try observedProfile.resolveControls(job: .init(tracking: .gap))) {
            XCTAssertEqual($0 as? PrinterProfileError, .unavailableTracking(.gap))
        }
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
