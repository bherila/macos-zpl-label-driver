import XCTest
@testable import LabelCore

final class ZPLPreparedLabelEncoderTests: XCTestCase {
    func testSingleProductionEnvelopeCombinesTypedControlsAndGraphics() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let controls = try profile.resolveControls(job: .init(printSpeedIps: 3))
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0xA5])
        let text = String(decoding: try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: controls), as: UTF8.self)
        XCTAssertEqual(text, "^XA\n^MMT\n^PR3\n^FO0,0^GFA,1,1,1,A5^FS\n^XZ\n")
        XCTAssertEqual(text.components(separatedBy: "^XA").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "^XZ").count - 1, 1)
        for command in ["^PQ", "^JU", "~SD", "^MD", "^LL", "^PW", "~DG"] { XCTAssertFalse(text.contains(command)) }
    }
    func testEnvelopePreflightsTotalLimit() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let controls = try profile.resolveControls(job: .init())
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0])
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder(maxOutputBytes: 12).encode(bitmap: bitmap, controls: controls))
    }
}
