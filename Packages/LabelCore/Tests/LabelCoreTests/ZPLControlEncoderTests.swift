import XCTest
@testable import LabelCore

final class ZPLControlEncoderTests: XCTestCase {
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
