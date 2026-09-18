import XCTest
@testable import LabelCore

final class ZPLControlEncoderTests: XCTestCase {
    func testBaselineEncoderRejectsUnsupportedCallerDeclaredSpeeds() throws {
        let reference = try PrinterProfile.gc420dUSBReference()
        let facts = reference.capabilities
        for speed in [5, 99, Int.max] {
            let declared = PrinterCapabilities(
                model: facts.model, thermalTransfer: facts.thermalTransfer,
                cutter: facts.cutter, peeler: facts.peeler, rewind: facts.rewind,
                tracking: facts.tracking, printSpeedChoicesIps: [speed], darkness: facts.darkness
            )
            let profile = try PrinterProfile(
                schemaVersion: reference.schemaVersion, revision: reference.revision,
                capabilities: declared, installedHardware: reference.installedHardware,
                media: reference.media, connection: reference.connection
            )
            let controls = try profile.resolveControls(job: .init(printSpeedIps: speed))
            XCTAssertThrowsError(try ZPLControlEncoder().encode(controls)) {
                XCTAssertEqual($0 as? ZPLControlEncodingError, .unsupportedPrintSpeed(speed))
            }
        }
    }

    func testAllDocumentedBaselineSpeedsHaveExactOutput() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        for speed in [2, 3, 4] {
            let controls = try profile.resolveControls(job: .init(printSpeedIps: speed))
            XCTAssertEqual(String(decoding: try ZPLControlEncoder().encode(controls), as: UTF8.self),
                           "^MMT\n^PR\(speed)\n")
        }
    }

    func testGC420dTearOffAndSpeedAreTypedAndBounded() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let controls = try profile.resolveControls(job: .init(printSpeedIps: 3))
        let text = String(decoding: try ZPLControlEncoder().encode(controls), as: UTF8.self)
        XCTAssertEqual(text, "^MMT\n^PR3\n")
    }

    func testNoUnsafeOrUnqualifiedCommandsCanEnterBaselineOutput() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let controls = try profile.resolveControls(job: .init())
        let text = String(decoding: try ZPLControlEncoder().encode(controls), as: UTF8.self)
        XCTAssertEqual(text, "^MMT\n")
        for command in ["^J", "~J", "^JU", "~SD", "^MD", "^LL", "^PW", "^LS", "^LT", "^PQ", "~DG"] {
            XCTAssertFalse(text.contains(command), command)
        }
    }

    func testProtocolTableRecordsSourcesAndNoDarknessClaim() {
        XCTAssertEqual(ZPLControlProtocol.gc420dBaseline.map(\.sourceID), ["R11", "R22"])
        XCTAssertFalse(ZPLControlProtocol.gc420dBaseline.contains { $0.option == "darkness" })
    }

    func testOutputIsBounded() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let controls = try profile.resolveControls(job: .init())
        XCTAssertThrowsError(try ZPLControlEncoder(maxOutputBytes: 4).encode(controls)) {
            XCTAssertEqual($0 as? ZPLControlEncodingError, .outputLimit)
        }
    }
}
